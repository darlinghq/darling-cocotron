// NSSound without an output device: the documented API that does not depend on playing. Sounds are made in
// memory (a WAV header and zero samples), sound files are written to ~/Library/Sounds for the +soundNamed: lookup.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL line %d: %s -- ", __LINE__, #cond); printf(__VA_ARGS__); printf("\n"); } } while (0)

// 16-bit mono PCM WAV of `seconds` of silence
static NSData *silentWAV(double seconds, int rate) {
    uint32_t n = (uint32_t) (seconds * rate), dataLen = n * 2, riff = 36 + dataLen, fmtLen = 16, sr = rate, br = rate * 2;
    uint16_t pcm = 1, ch = 1, ba = 2, bits = 16;
    NSMutableData *d = [NSMutableData data];
    [d appendBytes: "RIFF" length: 4]; [d appendBytes: &riff length: 4]; [d appendBytes: "WAVEfmt " length: 8];
    [d appendBytes: &fmtLen length: 4]; [d appendBytes: &pcm length: 2]; [d appendBytes: &ch length: 2];
    [d appendBytes: &sr length: 4]; [d appendBytes: &br length: 4]; [d appendBytes: &ba length: 2];
    [d appendBytes: &bits length: 2]; [d appendBytes: "data" length: 4]; [d appendBytes: &dataLen length: 4];
    [d setLength: 44 + dataLen];
    return d;
}

@interface Counter : NSObject <NSSoundDelegate> { @public int calls; }
@end
@implementation Counter
- (void) sound: (NSSound *) sound didFinishPlaying: (BOOL) ok { calls++; }
@end

int main(void) {
    @autoreleasepool {
        // Initializers: the audio is checked when the sound is created
        NSSound *s = [[NSSound alloc] initWithData: silentWAV(1.0, 22050)];
        CHECK(s != nil, "initWithData");
        CHECK(fabs([s duration] - 1.0) < 0.001, "duration %f", [s duration]);
        CHECK([s volume] == 1.0f && ![s loops] && [s currentTime] == 0 && ![s isPlaying], "defaults");
        CHECK([s name] == nil && [s playbackDeviceIdentifier] == nil, "no name or device by default");
        CHECK([[NSSound alloc] initWithData: [NSData dataWithBytes: "junkjunkjunk" length: 12]] == nil, "junk data");
        CHECK([[NSSound alloc] initWithData: nil] == nil, "nil data");
        CHECK([[NSSound alloc] initWithContentsOfFile: @"/nonexistent/x.wav" byReference: YES] == nil, "missing file");
        CHECK([[NSSound alloc] initWithContentsOfFile: nil byReference: YES] == nil, "nil path");

        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                [NSString stringWithFormat: @"nssound-api-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: nil];
        NSString *path = [dir stringByAppendingPathComponent: @"half.wav"];
        [silentWAV(0.5, 8000) writeToFile: path atomically: NO];
        for (int byRef = 0; byRef < 2; byRef++) {
            NSSound *f = [[NSSound alloc] initWithContentsOfFile: path byReference: byRef];
            CHECK(f != nil && fabs([f duration] - 0.5) < 0.001, "file byReference %d", byRef);
            NSSound *u = [[NSSound alloc] initWithContentsOfURL: [NSURL fileURLWithPath: path] byReference: byRef];
            CHECK(u != nil && fabs([u duration] - 0.5) < 0.001, "URL byReference %d", byRef);
        }

        // Settings
        s.volume = 0.25f; CHECK([s volume] == 0.25f, "volume");
        s.volume = 7; CHECK([s volume] == 1.0f, "volume clamps high");
        s.volume = -1; CHECK([s volume] == 0.0f, "volume clamps low");
        s.currentTime = 0.4; CHECK(fabs([s currentTime] - 0.4) < 0.001, "idle currentTime %f", [s currentTime]);
        s.currentTime = 5; CHECK(fabs([s currentTime] - 1.0) < 0.001, "currentTime clamps to the duration");
        s.currentTime = -1; CHECK([s currentTime] == 0, "currentTime clamps at 0");
        s.loops = YES; CHECK([s loops], "loops"); s.loops = NO;
        s.playbackDeviceIdentifier = @"some-device"; CHECK([[s playbackDeviceIdentifier] isEqual: @"some-device"], "device");
        s.playbackDeviceIdentifier = nil; CHECK([s playbackDeviceIdentifier] == nil, "device nil");

        // A sound that does not play: no delegate message, and the documented results of pause, resume and stop
        Counter *counter = [Counter new];
        s.delegate = counter;
        CHECK(![s pause] && ![s resume], "pause and resume of an idle sound return NO");
        CHECK([s stop] && !counter->calls, "stop of an idle sound");
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
        CHECK(counter->calls == 0, "no delegate message");

        // Registry
        CHECK([s setName: @"nssound-api-registered"], "setName");
        CHECK([[s name] isEqual: @"nssound-api-registered"], "name");
        CHECK([NSSound soundNamed: @"nssound-api-registered"] == s, "registered sound is found by name");
        NSSound *other = [[NSSound alloc] initWithData: silentWAV(0.1, 8000)];
        CHECK(![other setName: @"nssound-api-registered"], "a name in use by another sound");
        CHECK([s setName: @"nssound-api-registered"], "the same name again");
        CHECK([s setName: nil] && [s name] == nil && [NSSound soundNamed: @"nssound-api-registered"] == nil, "unregister");

        // Lookup of sound files by name. A file in the user's Sounds folder is found without its extension, and the
        // extension is accepted too; the same object comes back; names are case sensitive; the lookup of a name that
        // does not exist gives nil.
        NSString *soundsDir = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex: 0]
                stringByAppendingPathComponent: @"Sounds"];
        NSString *unique = [NSString stringWithFormat: @"NSSoundApiTest%d", getpid()];
        [[NSFileManager defaultManager] createDirectoryAtPath: soundsDir withIntermediateDirectories: YES attributes: nil error: nil];
        NSString *file = [soundsDir stringByAppendingPathComponent: [unique stringByAppendingPathExtension: @"wav"]];
        [silentWAV(0.25, 8000) writeToFile: file atomically: NO];
        NSSound *named = [NSSound soundNamed: unique];
        CHECK(named != nil && [[named name] isEqual: unique] && fabs([named duration] - 0.25) < 0.001, "soundNamed finds ~/Library/Sounds");
        CHECK([NSSound soundNamed: unique] == named, "soundNamed returns the same sound");
        CHECK([NSSound soundNamed: [unique stringByAppendingString: @".wav"]] == named, "soundNamed accepts the extension");
        CHECK([NSSound soundNamed: [unique lowercaseString]] == nil, "names are case sensitive");
        CHECK([NSSound soundNamed: @"NoSuchSoundNssoundApiTest"] == nil && [NSSound soundNamed: @""] == nil && [NSSound soundNamed: nil] == nil, "no such sound");
        unlink([file fileSystemRepresentation]);
        unlink([path fileSystemRepresentation]);
        rmdir([dir fileSystemRepresentation]);

        // Types
        NSArray *ext = [NSSound soundUnfilteredFileTypes];
        CHECK([ext containsObject: @"wav"] && [ext containsObject: @"aiff"], "file types %s", [[ext description] UTF8String]);
        NSArray *utis = [NSSound soundUnfilteredTypes];
        CHECK([utis containsObject: @"com.microsoft.waveform-audio"] && [utis containsObject: @"public.aiff-audio"], "UTIs %s", [[utis description] UTF8String]);

    }
    printf(failures ? "FAILED (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
