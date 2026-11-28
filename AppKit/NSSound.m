/* Copyright (c) 2006-2008 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSRaise.h>
#import <AppKit/NSSound.h>
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <dispatch/dispatch.h>
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

// NSSound plays through the Audio Toolbox: AudioFile and ExtAudioFile read and decode the sound and an
// AudioQueue plays it.
//
// The playback state lives in an engine object that is attached to the sound, because the ivar layout of
// NSSound is part of the legacy AppKit ABI and must not change. A "session" is the output queue with its
// buffers; it exists while the sound is playing or paused. Natural end of the sound is noticed when the queue
// has played everything and stopped by itself (the queue is told to stop once the last data has been handed
// to it); the delegate is then told on the main thread.

enum { SoundBufferCount = 6 };

@class _NSSoundEngine;

static void NSSoundBufferDone(void *ctx, AudioQueueRef queue, AudioQueueBufferRef buffer);
static void NSSoundRunningChanged(void *ctx, AudioQueueRef queue, AudioQueuePropertyID property);

@interface _NSSoundEngine : NSObject {
@public
    NSSound *owner; // not retained; see ownerHeld
    pthread_mutex_t lock;

    // The sound
    NSData *data;
    const void *bytes;
    SInt64 length;
    AudioFileID file;
    ExtAudioFileRef ext;
    double sampleRate;
    UInt32 channels;
    SInt64 frames;
    NSTimeInterval duration;

    // Settings
    float volume;
    BOOL loops;
    NSString *deviceID;
    NSString *name;

    // Playback; all guarded by the lock except where noted
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[SoundBufferCount];
    UInt32 bufferFrames;
    float *raw;
    BOOL started;           // the queue runs
    BOOL paused;            // there is a queue, it has been paused
    BOOL eof;               // everything has been read
    BOOL ownerHeld;         // the sound is retained while it plays
    volatile uint32_t draining;   // atomic: the queue has been told to stop after what it holds
    volatile uint32_t generation; // atomic: changes whenever a queue goes away
    double restFrame;       // the position while there is no queue, and while paused
    double anchorFrame;     // the position at anchorTime of the queue
    Float64 anchorTime;
}
- (id) initWithURL: (NSURL *) url data: (NSData *) data owner: (NSSound *) owner;
- (double) positionLocked;
- (BOOL) play;
- (BOOL) pause;
- (BOOL) resume;
- (BOOL) stop;
- (BOOL) isPlaying;
- (void) setCurrentFrame: (double) frame;
- (void) setVolume: (float) volume;
- (void) setLoops: (BOOL) loops;
- (void) setDeviceID: (NSString *) deviceID;
- (NSString *) nameOfSound;
- (void) refill: (AudioQueueBufferRef) buffer queue: (AudioQueueRef) q;
- (void) finishWithGeneration: (uint32_t) generation;
@end

static char NSSoundDelegateAssociationKey;
static char NSSoundEngineAssociationKey;

static NSMutableDictionary *NSSoundRegistry(void) {
    static NSMutableDictionary *registry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        registry = [[NSMutableDictionary alloc] init];
    });
    return registry;
}

static OSStatus NSSoundReadData(void *ctx, SInt64 pos, UInt32 request, void *buffer, UInt32 *actual) {
    _NSSoundEngine *e = ctx;
    if (pos >= e->length) {
        *actual = 0;
        return noErr;
    }
    UInt32 n = request;
    if (pos + n > e->length)
        n = (UInt32) (e->length - pos);
    memcpy(buffer, (const char *) e->bytes + pos, n);
    *actual = n;
    return noErr;
}

static OSStatus NSSoundWriteData(void *ctx, SInt64 pos, UInt32 request, const void *buffer, UInt32 *actual) {
    return kAudioFilePermissionsError;
}

static SInt64 NSSoundDataSize(void *ctx) {
    return ((_NSSoundEngine *) ctx)->length;
}

static OSStatus NSSoundSetDataSize(void *ctx, SInt64 size) {
    return kAudioFilePermissionsError;
}

@implementation _NSSoundEngine

// Opens the sound from the URL (a file read in place) or from the data. Returns nil if the audio is not readable.
- (id) initWithURL: (NSURL *) url data: (NSData *) soundData owner: (NSSound *) soundOwner {
    self = [super init];
    if (self == nil)
        return nil;

    owner = soundOwner;
    pthread_mutex_init(&lock, NULL);
    volume = 1.0f;

    OSStatus status;
    if (url != nil) {
        status = AudioFileOpenURL((CFURLRef) url, kAudioFileReadPermission, 0, &file);
    } else {
        data = [soundData copy];
        bytes = [data bytes];
        length = (SInt64) [data length];
        status = AudioFileOpenWithCallbacks(self, NSSoundReadData, NSSoundWriteData, NSSoundDataSize,
                                            NSSoundSetDataSize, 0, &file);
    }
    if (status != noErr) {
        file = NULL;
        [self release];
        return nil;
    }

    AudioStreamBasicDescription format;
    UInt32 size = sizeof(format);
    if (ExtAudioFileWrapAudioFileID(file, false, &ext) != noErr) {
        ext = NULL;
        [self release];
        return nil;
    }
    if (ExtAudioFileGetProperty(ext, kExtAudioFileProperty_FileDataFormat, &size, &format) != noErr ||
        format.mSampleRate <= 0 || format.mChannelsPerFrame == 0) {
        [self release];
        return nil;
    }
    size = sizeof(frames);
    if (ExtAudioFileGetProperty(ext, kExtAudioFileProperty_FileLengthFrames, &size, &frames) != noErr ||
        frames < 0) {
        [self release];
        return nil;
    }

    // The client side of the converter: float samples with the channels of the file. They are mixed down to
    // the stereo the queue plays.
    AudioStreamBasicDescription client;
    memset(&client, 0, sizeof(client));
    client.mSampleRate = format.mSampleRate;
    client.mFormatID = kAudioFormatLinearPCM;
    client.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    client.mChannelsPerFrame = format.mChannelsPerFrame;
    client.mBitsPerChannel = 32;
    client.mFramesPerPacket = 1;
    client.mBytesPerFrame = client.mBytesPerPacket = 4 * client.mChannelsPerFrame;
    if (ExtAudioFileSetProperty(ext, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client) != noErr) {
        [self release];
        return nil;
    }

    sampleRate = format.mSampleRate;
    channels = format.mChannelsPerFrame;
    duration = (NSTimeInterval) frames / sampleRate;
    return self;
}

- (void) dealloc {
    pthread_mutex_lock(&lock);
    AudioQueueRef q = [self detachQueueLocked];
    pthread_mutex_unlock(&lock);
    if (q != NULL)
        AudioQueueDispose(q, true);
    if (ext != NULL)
        ExtAudioFileDispose(ext);
    if (file != NULL)
        AudioFileClose(file);
    pthread_mutex_destroy(&lock);
    free(raw);
    [data release];
    [deviceID release];
    [name release];
    [super dealloc];
}

// Called with the lock held: forgets the queue; the caller disposes of it after releasing the lock (a callback
// that is running needs the lock, and the disposal waits for it).
- (AudioQueueRef) detachQueueLocked {
    AudioQueueRef q = queue;
    queue = NULL;
    started = NO;
    paused = NO;
    eof = NO;
    __atomic_store_n(&draining, 0, __ATOMIC_SEQ_CST);
    __atomic_add_fetch(&generation, 1, __ATOMIC_SEQ_CST);
    return q;
}

// The sound is retained while it plays, so that a sound nobody else holds goes on playing and tells its
// delegate when it ends. The matching release happens on the main thread with the notification.
- (void) notifyFinished: (BOOL) successfully releaseHold: (BOOL) hold {
    NSSound *sound = [owner retain];
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            id<NSSoundDelegate> delegate = [sound delegate];
            if ([delegate respondsToSelector: @selector(sound:didFinishPlaying:)])
                [delegate sound: sound didFinishPlaying: successfully];
        }
        if (hold)
            [sound release];
        [sound release];
    });
}

- (void) holdOwnerLocked {
    if (!ownerHeld) {
        ownerHeld = YES;
        [owner retain];
    }
}

// Gives up the hold without a notification (pause); the release is deferred to the main thread, because the
// caller may be a method of the sound itself.
- (void) dropHoldLocked {
    if (ownerHeld) {
        ownerHeld = NO;
        NSSound *sound = owner;
        dispatch_async(dispatch_get_main_queue(), ^{
            [sound release];
        });
    }
}

// ---- reading ----

// Reads up to `capacity` frames from the current position, mixed to interleaved stereo. A looping sound starts
// over at its end. Sets eof when there is nothing more.
- (UInt32) readInto: (float *) out capacity: (UInt32) capacity {
    UInt32 filled = 0;
    BOOL rewound = NO;

    while (filled < capacity && !eof) {
        UInt32 n = capacity - filled;
        AudioBufferList list;
        list.mNumberBuffers = 1;
        list.mBuffers[0].mNumberChannels = channels;
        list.mBuffers[0].mDataByteSize = n * channels * sizeof(float);
        list.mBuffers[0].mData = raw;
        if (ExtAudioFileRead(ext, &n, &list) != noErr) {
            eof = YES;
            break;
        }
        if (n == 0) {
            if (loops && frames > 0 && !rewound) {
                rewound = YES;
                if (ExtAudioFileSeek(ext, 0) != noErr)
                    eof = YES;
                continue;
            }
            eof = YES;
            break;
        }
        rewound = NO;
        float *dst = out + (size_t) filled * 2;
        for (UInt32 i = 0; i < n; i++) {
            const float *s = raw + (size_t) i * channels;
            dst[i * 2] = s[0];
            dst[i * 2 + 1] = channels > 1 ? s[1] : s[0];
        }
        filled += n;
    }
    return filled;
}

// Once everything has been read and the queue runs, it is told to stop after it has played what it holds.
- (void) drainIfDoneLocked {
    if (queue != NULL && eof && started && !__atomic_load_n(&draining, __ATOMIC_SEQ_CST)) {
        __atomic_store_n(&draining, 1, __ATOMIC_SEQ_CST);
        AudioQueueStop(queue, false);
    }
}

- (void) refill: (AudioQueueBufferRef) buffer queue: (AudioQueueRef) q {
    pthread_mutex_lock(&lock);
    if (q == queue) {
        UInt32 n = eof ? 0 : [self readInto: (float *) buffer->mAudioData capacity: bufferFrames];
        if (n > 0) {
            buffer->mAudioDataByteSize = n * 2 * sizeof(float);
            AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
        }
        [self drainIfDoneLocked];
    }
    pthread_mutex_unlock(&lock);
}

// ---- sessions ----

// Called with the lock held. Creates the queue and fills its buffers from `frame`. The queue is not started.
- (BOOL) startSessionLocked: (double) frame {
    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = sampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 32;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = format.mBytesPerPacket = 8;

    bufferFrames = (UInt32) (sampleRate / 20);
    if (bufferFrames < 1024)
        bufferFrames = 1024;

    AudioQueueRef q = NULL;
    if (AudioQueueNewOutput(&format, NSSoundBufferDone, self, NULL, NULL, 0, &q) != noErr)
        return NO;

    free(raw);
    raw = malloc((size_t) bufferFrames * channels * sizeof(float));
    BOOL ok = raw != NULL;
    for (int i = 0; ok && i < SoundBufferCount; i++)
        ok = AudioQueueAllocateBuffer(q, bufferFrames * 2 * sizeof(float), &buffers[i]) == noErr;
    if (!ok) {
        AudioQueueDispose(q, true);
        return NO;
    }

    AudioQueueAddPropertyListener(q, kAudioQueueProperty_IsRunning, NSSoundRunningChanged, self);
    AudioQueueSetParameter(q, kAudioQueueParam_Volume, volume);
    if (deviceID != nil) {
        CFStringRef uid = (CFStringRef) deviceID;
        AudioQueueSetProperty(q, kAudioQueueProperty_CurrentDevice, &uid, sizeof(uid));
    }

    if (frame >= (double) frames)
        frame = 0;
    ExtAudioFileSeek(ext, (SInt64) frame);
    restFrame = anchorFrame = frame;
    anchorTime = 0;
    eof = NO;
    started = paused = NO;
    __atomic_store_n(&draining, 0, __ATOMIC_SEQ_CST);
    queue = q;

    for (int i = 0; i < SoundBufferCount; i++) {
        UInt32 n = [self readInto: (float *) buffers[i]->mAudioData capacity: bufferFrames];
        if (n == 0)
            break;
        buffers[i]->mAudioDataByteSize = n * 2 * sizeof(float);
        AudioQueueEnqueueBuffer(queue, buffers[i], 0, NULL);
    }
    return YES;
}

// Called with the lock held. Starts or resumes the (primed or paused) queue.
- (BOOL) startQueueLocked {
    if (AudioQueueStart(queue, NULL) != noErr)
        return NO;
    started = YES;
    paused = NO;
    anchorFrame = restFrame;
    AudioTimeStamp stamp;
    Boolean discontinuity;
    anchorTime = AudioQueueGetCurrentTime(queue, NULL, &stamp, &discontinuity) == noErr &&
                         (stamp.mFlags & kAudioTimeStampSampleTimeValid)
                 ? stamp.mSampleTime
                 : 0;
    [self holdOwnerLocked];
    [self drainIfDoneLocked];
    return YES;
}

// The position in frames: where the audible sound is.
- (double) positionLocked {
    if (queue == NULL || !started)
        return restFrame;

    AudioTimeStamp stamp;
    Boolean discontinuity;
    Float64 t = anchorTime;
    if (AudioQueueGetCurrentTime(queue, NULL, &stamp, &discontinuity) == noErr &&
        (stamp.mFlags & kAudioTimeStampSampleTimeValid))
        t = stamp.mSampleTime;

    double position = anchorFrame + (t - anchorTime);
    if (position < 0)
        position = 0;
    if (loops && frames > 0)
        position = fmod(position, (double) frames);
    else if (position > (double) frames)
        position = (double) frames;
    return position;
}

// ---- operations ----

- (BOOL) play {
    BOOL ok = YES;
    pthread_mutex_lock(&lock);
    if (started) {
        ok = NO; // already playing
    } else if (queue == NULL) {
        if (frames <= 0 || ![self startSessionLocked: restFrame])
            ok = NO;
    }
    if (ok && !started && ![self startQueueLocked]) {
        AudioQueueRef q = [self detachQueueLocked];
        pthread_mutex_unlock(&lock);
        AudioQueueDispose(q, true);
        return NO;
    }
    pthread_mutex_unlock(&lock);
    return ok;
}

- (BOOL) pause {
    BOOL ok = NO;
    pthread_mutex_lock(&lock);
    if (queue != NULL && started) {
        restFrame = [self positionLocked];
        AudioQueuePause(queue);
        started = NO;
        paused = YES;
        __atomic_store_n(&draining, 0, __ATOMIC_SEQ_CST);
        [self dropHoldLocked];
        ok = YES;
    }
    pthread_mutex_unlock(&lock);
    return ok;
}

- (BOOL) resume {
    BOOL ok = NO;
    pthread_mutex_lock(&lock);
    if (queue != NULL && paused)
        ok = [self startQueueLocked];
    pthread_mutex_unlock(&lock);
    return ok;
}

- (BOOL) stop {
    // QUIRK: stop returns YES for a sound that is not playing (the documentation does not say).
    // Evidence: black-box observation on macOS 26.7.3 (tier 2); pause and resume of an idle sound return NO.
    // Test: tests/appkit-sound-api.m, "stop of an idle sound".
    pthread_mutex_lock(&lock);
    AudioQueueRef q = [self detachQueueLocked];
    const BOOL hadSession = q != NULL;
    const BOOL hold = ownerHeld;
    ownerHeld = NO;
    restFrame = 0;
    pthread_mutex_unlock(&lock);

    if (hadSession) {
        AudioQueueDispose(q, true);
        [self notifyFinished: NO releaseHold: hold];
    }
    return YES;
}

- (BOOL) isPlaying {
    pthread_mutex_lock(&lock);
    const BOOL playing = queue != NULL && started;
    pthread_mutex_unlock(&lock);
    return playing;
}

// The queue stopped by itself after the last data: the sound has ended. Runs on the main thread.
- (void) finishWithGeneration: (uint32_t) expected {
    pthread_mutex_lock(&lock);
    if (queue == NULL || __atomic_load_n(&generation, __ATOMIC_SEQ_CST) != expected ||
        !__atomic_load_n(&draining, __ATOMIC_SEQ_CST)) {
        pthread_mutex_unlock(&lock);
        return;
    }
    AudioQueueRef q = [self detachQueueLocked];
    const BOOL hold = ownerHeld;
    ownerHeld = NO;
    restFrame = 0;
    pthread_mutex_unlock(&lock);

    AudioQueueDispose(q, true);
    [self notifyFinished: YES releaseHold: hold];
}

- (void) setCurrentFrame: (double) frame {
    pthread_mutex_lock(&lock);
    if (queue == NULL) {
        restFrame = frame;
        pthread_mutex_unlock(&lock);
        return;
    }

    // Playing or paused: the sound goes on from the new position in a new queue.
    const BOOL wasStarted = started;
    AudioQueueRef old = [self detachQueueLocked];
    BOOL ok = [self startSessionLocked: frame];
    if (ok && wasStarted)
        ok = [self startQueueLocked];
    if (ok && !wasStarted)
        paused = YES; // a paused sound stays paused at its new position
    AudioQueueRef failed = NULL;
    BOOL hold = NO;
    if (!ok) {
        failed = [self detachQueueLocked];
        hold = ownerHeld;
        ownerHeld = NO;
        restFrame = 0;
    }
    pthread_mutex_unlock(&lock);

    AudioQueueDispose(old, true);
    if (failed != NULL)
        AudioQueueDispose(failed, true);
    if (!ok)
        [self notifyFinished: NO releaseHold: hold];
}

- (void) setVolume: (float) newVolume {
    pthread_mutex_lock(&lock);
    volume = newVolume;
    if (queue != NULL)
        AudioQueueSetParameter(queue, kAudioQueueParam_Volume, volume);
    pthread_mutex_unlock(&lock);
}

- (void) setLoops: (BOOL) newLoops {
    pthread_mutex_lock(&lock);
    if (loops != newLoops) {
        // The position was counted in the old mode: keep it where it is.
        if (queue != NULL && started) {
            const double position = [self positionLocked];
            AudioTimeStamp stamp;
            Boolean discontinuity;
            if (AudioQueueGetCurrentTime(queue, NULL, &stamp, &discontinuity) == noErr &&
                (stamp.mFlags & kAudioTimeStampSampleTimeValid))
                anchorTime = stamp.mSampleTime;
            anchorFrame = position;
        }
        loops = newLoops;
    }
    pthread_mutex_unlock(&lock);
}

- (NSString *) nameOfSound {
    return name;
}

- (void) setDeviceID: (NSString *) newDevice {
    pthread_mutex_lock(&lock);
    if (deviceID != newDevice) {
        [deviceID release];
        deviceID = [newDevice copy];
    }
    if (queue != NULL && deviceID != nil) {
        CFStringRef uid = (CFStringRef) deviceID;
        AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, &uid, sizeof(uid));
    }
    pthread_mutex_unlock(&lock);
}

@end

static void NSSoundBufferDone(void *ctx, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    [(_NSSoundEngine *) ctx refill: buffer queue: queue];
}

static void NSSoundRunningChanged(void *ctx, AudioQueueRef queue, AudioQueuePropertyID property) {
    _NSSoundEngine *engine = ctx;
    UInt32 running = 1, size = sizeof(running);

    if (AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &running, &size) != noErr || running)
        return;
    if (!__atomic_load_n(&engine->draining, __ATOMIC_SEQ_CST))
        return; // stopped on purpose

    const uint32_t generation = __atomic_load_n(&engine->generation, __ATOMIC_SEQ_CST);
    [engine retain];
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            [engine finishWithGeneration: generation];
        }
        [engine release];
    });
}

@implementation NSSound

static _NSSoundEngine *NSSoundGetEngine(NSSound *sound) {
    return objc_getAssociatedObject(sound, &NSSoundEngineAssociationKey);
}

// The delegate is stored out of line: NSSound's ivar layout is part of the
// legacy AppKit ABI and must not change.
- (id<NSSoundDelegate>) delegate {
    return objc_getAssociatedObject(self, &NSSoundDelegateAssociationKey);
}

- (void) setDelegate: (id<NSSoundDelegate>) delegate {
    objc_setAssociatedObject(self, &NSSoundDelegateAssociationKey, delegate,
                             OBJC_ASSOCIATION_ASSIGN);
}

// Extensions of the audio files the Audio Toolbox reads
+ (NSArray *) soundUnfilteredFileTypes {
    static NSArray *types;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];
        UInt32 size = sizeof(CFArrayRef);
        CFArrayRef all = NULL;
        if (AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AllExtensions, 0, NULL, &size, &all) == noErr &&
            all != NULL) {
            for (NSString *extension in (NSArray *) all) {
                NSString *lower = [extension lowercaseString];
                if (![list containsObject: lower])
                    [list addObject: lower];
            }
            CFRelease(all);
        }
        types = [list copy];
    });
    return types;
}

+ (NSArray<NSString *> *) soundUnfilteredTypes {
    NSMutableArray *list = [NSMutableArray array];
    UInt32 size = sizeof(CFArrayRef);
    CFArrayRef all = NULL;
    if (AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AllUTIs, 0, NULL, &size, &all) == noErr && all != NULL) {
        [list addObjectsFromArray: (NSArray *) all];
        CFRelease(all);
    }
    [list addObject: @"com.apple.cocoa.pasteboard.sound"];
    return list;
}

// The sound files of a name live in these directories, in this order, after the main bundle.
static NSArray *NSSoundSearchDirectories(void) {
    NSMutableArray *dirs = [NSMutableArray array];
    const NSSearchPathDomainMask domains[] = {NSUserDomainMask, NSLocalDomainMask, NSNetworkDomainMask,
                                              NSSystemDomainMask};
    for (size_t i = 0; i < sizeof(domains) / sizeof(domains[0]); i++) {
        for (NSString *library in NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, domains[i], YES))
            [dirs addObject: [library stringByAppendingPathComponent: @"Sounds"]];
    }
    return dirs;
}

+ (NSSound *) soundNamed: (NSSoundName) name {
    if ([name length] == 0)
        return nil;

    NSMutableDictionary *registry = NSSoundRegistry();
    @synchronized(registry) {
        NSSound *sound = [registry objectForKey: name];
        if (sound != nil)
            return sound;

        // A name may carry the extension of the file
        NSArray *types = [NSSound soundUnfilteredFileTypes];
        NSString *base = name;
        if ([types containsObject: [[name pathExtension] lowercaseString]]) {
            base = [name stringByDeletingPathExtension];
            sound = [registry objectForKey: base];
            if (sound != nil)
                return sound;
        }

        NSString *path = [[NSBundle mainBundle] pathForSoundResource: base];
        if (path == nil) {
            // QUIRK: a name matches a sound file only in its own case, whatever the case sensitivity of the file
            // system, and a name with the extension of the file ("Glass.aiff") finds the same sound as without it.
            // Evidence: black-box observation of +soundNamed: on macOS 26.7.3 (tier 2): "Glass" and "Glass.aiff"
            // give a sound named "Glass", "glass" gives nil.
            // Test: tests/appkit-sound-api.m, "names are case sensitive" and "soundNamed accepts the extension".
            NSFileManager *manager = [NSFileManager defaultManager];
            for (NSString *dir in NSSoundSearchDirectories()) {
                NSArray *entries = [manager contentsOfDirectoryAtPath: dir error: NULL];
                for (NSString *type in types) {
                    NSString *file = [base stringByAppendingPathExtension: type];
                    if ([entries containsObject: file]) {
                        path = [dir stringByAppendingPathComponent: file];
                        break;
                    }
                }
                if (path != nil)
                    break;
            }
        }
        if (path == nil)
            return nil;

        sound = [[[NSSound alloc] initWithContentsOfFile: path byReference: YES] autorelease];
        if (sound != nil)
            [sound setName: base];
        return sound;
    }
}

- (id) initWithContentsOfURL: (NSURL *) url byReference: (BOOL) byReference {
    self = [super init];
    if (self == nil)
        return nil;

    _NSSoundEngine *engine = nil;
    if (url != nil) {
        if ([url isFileURL] && byReference) {
            engine = [[_NSSoundEngine alloc] initWithURL: url data: nil owner: self];
        } else {
            NSData *contents = [NSData dataWithContentsOfURL: url];
            if (contents != nil)
                engine = [[_NSSoundEngine alloc] initWithURL: nil data: contents owner: self];
        }
    }
    if (engine == nil) {
        [self release];
        return nil;
    }
    objc_setAssociatedObject(self, &NSSoundEngineAssociationKey, engine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [engine release];
    return self;
}

- (id) initWithContentsOfFile: (NSString *) path
                  byReference: (BOOL) byReference
{
    if (path == nil) {
        [self release];
        return nil;
    }
    return [self initWithContentsOfURL: [NSURL fileURLWithPath: path] byReference: byReference];
}

- (id) initWithData: (NSData *) soundData {
    self = [super init];
    if (self == nil)
        return nil;

    _NSSoundEngine *engine = nil;
    if (soundData != nil)
        engine = [[_NSSoundEngine alloc] initWithURL: nil data: soundData owner: self];
    if (engine == nil) {
        [self release];
        return nil;
    }
    objc_setAssociatedObject(self, &NSSoundEngineAssociationKey, engine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [engine release];
    return self;
}

- (void) dealloc {
    NSString *name = [self name];
    if (name != nil) {
        NSMutableDictionary *registry = NSSoundRegistry();
        @synchronized(registry) {
            if ([registry objectForKey: name] == self)
                [registry removeObjectForKey: name];
        }
    }
    [super dealloc];
}

- (NSSoundName) name {
    return [NSSoundGetEngine(self) nameOfSound];
}

// Registers the sound under the name; the name is free for another sound again once this one is unnamed or gone.
- (BOOL) setName: (NSSoundName) newName {
    _NSSoundEngine *engine = NSSoundGetEngine(self);
    NSMutableDictionary *registry = NSSoundRegistry();

    @synchronized(registry) {
        if (newName != nil) {
            id existing = [registry objectForKey: newName];
            if (existing != nil && existing != self)
                return NO;
        }
        if (engine->name != nil && [registry objectForKey: engine->name] == self)
            [registry removeObjectForKey: engine->name];
        [engine->name release];
        engine->name = [newName copy];
        if (newName != nil)
            [registry setObject: self forKey: newName];
    }
    return YES;
}

- (BOOL) play {
    return [NSSoundGetEngine(self) play];
}

- (BOOL) pause {
    return [NSSoundGetEngine(self) pause];
}

- (BOOL) resume {
    return [NSSoundGetEngine(self) resume];
}

- (BOOL) stop {
    return [NSSoundGetEngine(self) stop];
}

- (BOOL) isPlaying {
    return [NSSoundGetEngine(self) isPlaying];
}

- (NSTimeInterval) duration {
    return NSSoundGetEngine(self)->duration;
}

- (float) volume {
    return NSSoundGetEngine(self)->volume;
}

- (void) setVolume: (float) volume {
    if (volume < 0.0f)
        volume = 0.0f;
    else if (volume > 1.0f)
        volume = 1.0f;
    [NSSoundGetEngine(self) setVolume: volume];
}

- (NSTimeInterval) currentTime {
    _NSSoundEngine *engine = NSSoundGetEngine(self);
    pthread_mutex_lock(&engine->lock);
    const double position = [engine positionLocked];
    pthread_mutex_unlock(&engine->lock);
    return position / engine->sampleRate;
}

- (void) setCurrentTime: (NSTimeInterval) seconds {
    // QUIRK: a time outside the sound is moved into it (the documentation does not say what happens): past the
    // end it becomes the duration, below zero it becomes 0.
    // Evidence: black-box observation on macOS 26.7.3 (tier 2): currentTime = 5 on a 1 s sound reads 1.0,
    // currentTime = -1 reads 0.
    // Test: tests/appkit-sound-api.m, "currentTime clamps".
    _NSSoundEngine *engine = NSSoundGetEngine(self);
    if (!(seconds > 0))
        seconds = 0;
    if (seconds > engine->duration)
        seconds = engine->duration;
    [engine setCurrentFrame: floor(seconds * engine->sampleRate)];
}

- (BOOL) loops {
    return NSSoundGetEngine(self)->loops;
}

- (void) setLoops: (BOOL) loops {
    [NSSoundGetEngine(self) setLoops: loops];
}

- (NSSoundPlaybackDeviceIdentifier) playbackDeviceIdentifier {
    return NSSoundGetEngine(self)->deviceID;
}

- (void) setPlaybackDeviceIdentifier: (NSSoundPlaybackDeviceIdentifier) identifier {
    [NSSoundGetEngine(self) setDeviceID: identifier];
}

@end

@implementation NSBundle (NSSound)

- (NSString *) pathForSoundResource: (NSString *) name {
    NSArray *types = [NSSound soundUnfilteredFileTypes];
    int i, count = [types count];

    for (i = 0; i < count; i++) {
        NSString *type = [types objectAtIndex: i];
        NSString *path = [self pathForResource: name ofType: type];

        if (path != nil)
            return path;
    }

    return nil;
}

@end
