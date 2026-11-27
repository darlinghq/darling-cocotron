/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <Foundation/NSBundle.h>
#import <AppKit/AppKitIvarLayout.h>

@protocol NSSoundDelegate;

typedef NSString *NSSoundName;
typedef NSString *NSSoundPlaybackDeviceIdentifier;

@interface NSSound : NSObject {
    NS_LEGACY_IVAR_PAD(_NSSoundReserved, 36)
}

// The delegate is notified when playback finishes. It is not retained.
@property(nonatomic, assign) id<NSSoundDelegate> delegate;

+ (NSArray *) soundUnfilteredFileTypes;
// Uniform Type Identifiers of the audio the class can play
+ (NSArray<NSString *> *) soundUnfilteredTypes;

// The sound registered under the name (see -setName:), or else the sound file of that name found in the main
// bundle, ~/Library/Sounds, /Library/Sounds, /Network/Library/Sounds and /System/Library/Sounds, in that order.
+ (NSSound *) soundNamed: (NSSoundName) name;

- (id) initWithContentsOfFile: (NSString *) path
                  byReference: (BOOL) byReference;
- (id) initWithContentsOfURL: (NSURL *) url byReference: (BOOL) byReference;
- (id) initWithData: (NSData *) data;
- (BOOL) setName: (NSSoundName) name;
- (NSSoundName) name;

- (BOOL) play;
- (BOOL) pause;
- (BOOL) resume;
- (BOOL) stop;
- (BOOL) isPlaying;

// Seconds
@property(readonly) NSTimeInterval duration;
// 0 to 1, for this sound only
@property float volume;
@property NSTimeInterval currentTime;
// A looping sound does not tell its delegate that it has finished, unless it is stopped.
@property BOOL loops;
// The UID of the audio device to play on; nil follows the default output device
@property(copy) NSSoundPlaybackDeviceIdentifier playbackDeviceIdentifier;

@end

@interface NSBundle (NSSound)
- (NSString *) pathForSoundResource: (NSString *) sound;
@end

@protocol NSSoundDelegate <NSObject>

@optional
- (void) sound: (NSSound *) sound didFinishPlaying: (BOOL) successfully;

@end
