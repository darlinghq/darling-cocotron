/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

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

#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSCachedImageRep.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSCustomImageRep.h>
#import <AppKit/NSEPSImageRep.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSImage.h>
#import "NSCoder+AppKit.h"
#import <AppKit/NSAppearance.h>
#import "NSImageDrawingCache.h"
#import <AppKit/NSImageRep.h>
#import <AppKit/NSPDFImageRep.h>
#import <AppKit/NSPasteboard.h>
#import "NSPasteboardAliases.h"
#import <AppKit/NSRaise.h>
#import <Foundation/NSKeyedArchiver.h>

@interface NSImageSymbolConfiguration (Private)
- (CGFloat) _placeholderSide;
@end

NSImageName const NSImageNameActionTemplate = @"NSActionTemplate";
NSImageName const NSImageNameAddTemplate = @"NSAddTemplate";
NSImageName const NSImageNameAdvanced = @"NSAdvanced";
NSImageName const NSImageNameApplicationIcon = @"NSApplicationIcon";
NSImageName const NSImageNameBluetoothTemplate = @"NSBluetoothTemplate";
NSImageName const NSImageNameBonjour = @"NSBonjour";
NSImageName const NSImageNameBookmarksTemplate = @"NSBookmarksTemplate";
NSImageName const NSImageNameCaution = @"NSCaution";
NSImageName const NSImageNameColorPanel = @"NSColorPanel";
NSImageName const NSImageNameColumnViewTemplate = @"NSColumnViewTemplate";
NSImageName const NSImageNameComputer = @"NSComputer";
NSImageName const NSImageNameDotMac = @"NSDotMac";
NSImageName const NSImageNameEnterFullScreenTemplate =
        @"NSEnterFullScreenTemplate";
NSImageName const NSImageNameEveryone = @"NSEveryone";
NSImageName const NSImageNameExitFullScreenTemplate =
        @"NSExitFullScreenTemplate";
NSImageName const NSImageNameFlowViewTemplate = @"NSFlowViewTemplate";
NSImageName const NSImageNameFolder = @"NSFolder";
NSImageName const NSImageNameFolderBurnable = @"NSFolderBurnable";
NSImageName const NSImageNameFolderSmart = @"NSFolderSmart";
NSImageName const NSImageNameFollowLinkFreestandingTemplate =
        @"NSFollowLinkFreestandingTemplate";
NSImageName const NSImageNameFontPanel = @"NSFontPanel";
NSImageName const NSImageNameGoLeftTemplate = @"NSGoLeftTemplate";
NSImageName const NSImageNameGoRightTemplate = @"NSGoRightTemplate";
NSImageName const NSImageNameHomeTemplate = @"NSHomeTemplate";
NSImageName const NSImageNameIChatTheaterTemplate = @"NSIChatTheaterTemplate";
NSImageName const NSImageNameIconViewTemplate = @"NSIconViewTemplate";
NSImageName const NSImageNameInfo = @"NSInfo";
NSImageName const NSImageNameInvalidDataFreestandingTemplate =
        @"NSInvalidDataFreestandingTemplate";
NSImageName const NSImageNameLeftFacingTriangleTemplate =
        @"NSLeftFacingTriangleTemplate";
NSImageName const NSImageNameListViewTemplate = @"NSListViewTemplate";
NSImageName const NSImageNameLockLockedTemplate = @"NSLockLockedTemplate";
NSImageName const NSImageNameLockUnlockedTemplate = @"NSLockUnlockedTemplate";
NSImageName const NSImageNameMenuMixedStateTemplate =
        @"NSMenuMixedStateTemplate";
NSImageName const NSImageNameMenuOnStateTemplate = @"NSMenuOnStateTemplate";
NSImageName const NSImageNameMobileMe = @"NSMobileMe";
NSImageName const NSImageNameMultipleDocuments = @"NSMultipleDocuments";
NSImageName const NSImageNameNetwork = @"NSNetwork";
NSImageName const NSImageNamePathTemplate = @"NSPathTemplate";
NSImageName const NSImageNamePreferencesGeneral = @"NSPreferencesGeneral";
NSImageName const NSImageNameQuickLookTemplate = @"NSQuickLookTemplate";
NSImageName const NSImageNameRefreshFreestandingTemplate =
        @"NSRefreshFreestandingTemplate";
NSImageName const NSImageNameRefreshTemplate = @"NSRefreshTemplate";
NSImageName const NSImageNameRemoveTemplate = @"NSRemoveTemplate";
NSImageName const NSImageNameRevealFreestandingTemplate =
        @"NSRevealFreestandingTemplate";
NSImageName const NSImageNameRightFacingTriangleTemplate =
        @"NSRightFacingTriangleTemplate";
NSImageName const NSImageNameShareTemplate = @"NSShareTemplate";
NSImageName const NSImageNameSlideshowTemplate = @"NSSlideshowTemplate";
NSImageName const NSImageNameSmartBadgeTemplate = @"NSSmartBadgeTemplate";
NSImageName const NSImageNameStatusAvailable = @"NSStatusAvailable";
NSImageName const NSImageNameStatusNone = @"NSStatusNone";
NSImageName const NSImageNameStatusPartiallyAvailable =
        @"NSStatusPartiallyAvailable";
NSImageName const NSImageNameStatusUnavailable = @"NSStatusUnavailable";
NSImageName const NSImageNameStopProgressFreestandingTemplate =
        @"NSStopProgressFreestandingTemplate";
NSImageName const NSImageNameStopProgressTemplate = @"NSStopProgressTemplate";
NSImageName const NSImageNameTrashEmpty = @"NSTrashEmpty";
NSImageName const NSImageNameTrashFull = @"NSTrashFull";
NSImageName const NSImageNameUser = @"NSUser";
NSImageName const NSImageNameUserAccounts = @"NSUserAccounts";
NSImageName const NSImageNameUserGroup = @"NSUserGroup";
NSImageName const NSImageNameUserGuest = @"NSUserGuest";
NSImageName const NSImageNameGoBackTemplate = @"NSGoBackTemplate";
NSImageName const NSImageNameGoForwardTemplate = @"NSGoForwardTemplate";

NSImageHintKey const NSImageHintInterpolation = @"NSImageHintInterpolation";
NSImageHintKey const NSImageHintCTM = @"NSImageHintCTM";

NSImageName const NSImageNameTouchBarDeleteTemplate =
        @"NSTouchBarDeleteTemplate";
NSImageName const NSImageNameTouchBarPauseTemplate = @"NSTouchBarPauseTemplate";
NSImageName const NSImageNameTouchBarPlayTemplate = @"NSTouchBarPlayTemplate";
NSImageName const NSImageNameTouchBarRecordStopTemplate =
        @"NSTouchBarRecordStopTemplate";
NSImageName const NSImageNameTouchBarAddDetailTemplate =
        @"NSTouchBarAddDetailTemplate";
NSImageName const NSImageNameTouchBarAddTemplate =
        @"NSTouchBarAddTemplate";
NSImageName const NSImageNameTouchBarAddTabTemplate =
        @"NSImageNameTouchBarAddTabTemplate";
NSImageName const NSImageNameTouchBarAlarmTemplate =
        @"NSTouchBarAlarmTemplate";
NSImageName const NSImageNameTouchBarAudioInputMuteTemplate =
        @"NSTouchBarAudioInputMuteTemplate";
NSImageName const NSImageNameTouchBarAudioInputTemplate =
        @"NSTouchBarAudioInputTemplate";
NSImageName const NSImageNameTouchBarAudioOutputMuteTemplate =
        @"NSTouchBarAudioOutputMuteTemplate";
NSImageName const NSImageNameTouchBarAudioOutputVolumeHighTemplate =
        @"NSTouchBarAudioOutputVolumeHighTemplate";
NSImageName const NSImageNameTouchBarAudioOutputVolumeLowTemplate =
        @"NSTouchBarAudioOutputVolumeLowTemplate";
NSImageName const NSImageNameTouchBarAudioOutputVolumeMediumTemplate =
        @"NSTouchBarAudioOutputVolumeMediumTemplate";
NSImageName const NSImageNameTouchBarAudioOutputVolumeOffTemplate =
        @"NSTouchBarAudioOutputVolumeOffTemplate";
NSImageName const NSImageNameTouchBarBookmarksTemplate =
        @"NSTouchBarBookmarksTemplate";
NSImageName const NSImageNameTouchBarColorPickerFill =
        @"NSTouchBarColorPickerFill";
NSImageName const NSImageNameTouchBarColorPickerFont =
        @"NSTouchBarColorPickerFont";
NSImageName const NSImageNameTouchBarColorPickerStroke =
        @"NSTouchBarColorPickerStroke";
NSImageName const NSImageNameTouchBarCommunicationAudioTemplate =
        @"NSTouchBarCommunicationAudioTemplate";
NSImageName const NSImageNameTouchBarCommunicationVideoTemplate =
        @"NSTouchBarCommunicationVideoTemplate";
NSImageName const NSImageNameTouchBarComposeTemplate =
        @"NSTouchBarComposeTemplate";
NSImageName const NSImageNameTouchBarDownloadTemplate =
        @"NSTouchBarDownloadTemplate";
NSImageName const NSImageNameTouchBarEnterFullScreenTemplate =
        @"NSTouchBarEnterFullScreenTemplate";
NSImageName const NSImageNameTouchBarExitFullScreenTemplate =
        @"NSTouchBarExitFullScreenTemplate";
NSImageName const NSImageNameTouchBarFastForwardTemplate =
        @"NSTouchBarFastForwardTemplate";
NSImageName const NSImageNameTouchBarFolderCopyToTemplate =
        @"NSTouchBarFolderCopyToTemplate";
NSImageName const NSImageNameTouchBarFolderMoveToTemplate =
        @"NSTouchBarFolderMoveToTemplate";
NSImageName const NSImageNameTouchBarFolderTemplate =
        @"NSTouchBarFolderTemplate";
NSImageName const NSImageNameTouchBarGetInfoTemplate =
        @"NSTouchBarGetInfoTemplate";
NSImageName const NSImageNameTouchBarGoBackTemplate =
        @"NSTouchBarGoBackTemplate";
NSImageName const NSImageNameTouchBarGoDownTemplate =
        @"NSTouchBarGoDownTemplate";
NSImageName const NSImageNameTouchBarGoForwardTemplate =
        @"NSTouchBarGoForwardTemplate";
NSImageName const NSImageNameTouchBarGoUpTemplate =
        @"NSTouchBarGoUpTemplate";
NSImageName const NSImageNameTouchBarHistoryTemplate =
        @"NSTouchBarHistoryTemplate";
NSImageName const NSImageNameTouchBarIconViewTemplate =
        @"NSTouchBarIconViewTemplate";
NSImageName const NSImageNameTouchBarListViewTemplate =
        @"NSTouchBarListViewTemplate";
NSImageName const NSImageNameTouchBarMailTemplate =
        @"NSTouchBarMailTemplate";
NSImageName const NSImageNameTouchBarNewFolderTemplate =
        @"NSTouchBarNewFolderTemplate";
NSImageName const NSImageNameTouchBarNewMessageTemplate =
        @"NSTouchBarNewMessageTemplate";
NSImageName const NSImageNameTouchBarOpenInBrowserTemplate =
        @"NSTouchBarOpenInBrowserTemplate";
NSImageName const NSImageNameTouchBarPlayheadTemplate =
        @"NSTouchBarPlayheadTemplate";
NSImageName const NSImageNameTouchBarPlayPauseTemplate =
        @"NSTouchBarPlayPauseTemplate";
NSImageName const NSImageNameTouchBarQuickLookTemplate =
        @"NSTouchBarQuickLookTemplate";
NSImageName const NSImageNameTouchBarRecordStartTemplate =
        @"NSTouchBarRecordStartTemplate";
NSImageName const NSImageNameTouchBarRefreshTemplate =
        @"NSTouchBarRefreshTemplate";
NSImageName const NSImageNameTouchBarRemoveTemplate =
        @"NSTouchBarRemoveTemplate";
NSImageName const NSImageNameTouchBarRewindTemplate =
        @"NSTouchBarRewindTemplate";
NSImageName const NSImageNameTouchBarRotateLeftTemplate =
        @"NSTouchBarRotateLeftTemplate";
NSImageName const NSImageNameTouchBarRotateRightTemplate =
        @"NSTouchBarRotateRightTemplate";
NSImageName const NSImageNameTouchBarSearchTemplate =
        @"NSTouchBarSearchTemplate";
NSImageName const NSImageNameTouchBarShareTemplate =
        @"NSTouchBarShareTemplate";
NSImageName const NSImageNameTouchBarSidebarTemplate =
        @"NSTouchBarSidebarTemplate";
NSImageName const NSImageNameTouchBarSkipAhead15SecondsTemplate =
        @"NSTouchBarSkipAhead15SecondsTemplate";
NSImageName const NSImageNameTouchBarSkipAhead30SecondsTemplate =
        @"NSTouchBarSkipAhead30SecondsTemplate";
NSImageName const NSImageNameTouchBarSkipAheadTemplate =
        @"NSTouchBarSkipAheadTemplate";
NSImageName const NSImageNameTouchBarSkipBack15SecondsTemplate =
        @"NSTouchBarSkipBack15SecondsTemplate";
NSImageName const NSImageNameTouchBarSkipBack30SecondsTemplate =
        @"NSTouchBarSkipBack30SecondsTemplate";
NSImageName const NSImageNameTouchBarSkipBackTemplate =
        @"NSTouchBarSkipBackTemplate";
NSImageName const NSImageNameTouchBarSkipToEndTemplate =
        @"NSTouchBarSkipToEndTemplate";
NSImageName const NSImageNameTouchBarSkipToStartTemplate =
        @"NSTouchBarSkipToStartTemplate";
NSImageName const NSImageNameTouchBarSlideshowTemplate =
        @"NSTouchBarSlideshowTemplate";
NSImageName const NSImageNameTouchBarTagIconTemplate =
        @"NSTouchBarTagIconTemplate";
NSImageName const NSImageNameTouchBarTextBoldTemplate =
        @"NSTouchBarTextBoldTemplate";
NSImageName const NSImageNameTouchBarTextBoxTemplate =
        @"NSTouchBarTextBoxTemplate";
NSImageName const NSImageNameTouchBarTextCenterAlignTemplate =
        @"NSTouchBarTextCenterAlignTemplate";
NSImageName const NSImageNameTouchBarTextItalicTemplate =
        @"NSTouchBarTextItalicTemplate";
NSImageName const NSImageNameTouchBarTextJustifiedAlignTemplate =
        @"NSTouchBarTextJustifiedAlignTemplate";
NSImageName const NSImageNameTouchBarTextLeftAlignTemplate =
        @"NSTouchBarTextLeftAlignTemplate";
NSImageName const NSImageNameTouchBarTextListTemplate =
        @"NSTouchBarTextListTemplate";
NSImageName const NSImageNameTouchBarTextRightAlignTemplate =
        @"NSTouchBarTextRightAlignTemplate";
NSImageName const NSImageNameTouchBarTextStrikethroughTemplate =
        @"NSTouchBarTextStrikethroughTemplate";
NSImageName const NSImageNameTouchBarTextUnderlineTemplate =
        @"NSTouchBarTextUnderlineTemplate";
NSImageName const NSImageNameTouchBarUserAddTemplate =
        @"NSTouchBarUserAddTemplate";
NSImageName const NSImageNameTouchBarUserGroupTemplate =
        @"NSTouchBarUserGroupTemplate";
NSImageName const NSImageNameTouchBarUserTemplate =
        @"NSTouchBarUserTemplate";
NSImageName const NSImageNameTouchBarVolumeDownTemplate =
        @"NSTouchBarVolumeDownTemplate";
NSImageName const NSImageNameTouchBarVolumeUpTemplate =
        @"NSTouchBarVolumeUpTemplate";

// Private class used so the context knows the flipped status of a locked image
// 10.4 does something like that - probably for more than just getting the
// flippiness - 10.6 uses some special NSSnapshotBitmapGraphicsContext
@interface NSImageCacheView : NSView {
    BOOL _flipped;
}
- (id) initWithFlipped: (BOOL) flipped;
@end
@implementation NSImageCacheView
- (id) initWithFlipped: (BOOL) flipped {
    if ((self = [super init])) {
        _flipped = flipped;
    }
    return self;
}
- (BOOL) isFlipped {
    return _flipped;
}
@end

@interface NSImage (NineParts)
- (BOOL) _drawNinePartInRect: (NSRect) rect
                    fromRect: (NSRect) source
                   operation: (NSCompositingOperation) operation
                    fraction: (CGFloat) fraction;
- (void) _drawPlainInRect: (NSRect) rect
                 fromRect: (NSRect) source
                operation: (NSCompositingOperation) operation
                 fraction: (CGFloat) fraction;
@end

@implementation NSImage

+ (NSArray *) imageFileTypes {
    return [self imageUnfilteredFileTypes];
}

+ (NSArray *) imageTypes {
    return [NSImageRep imageTypes];
}

+ (NSArray *) imageUnfilteredTypes {
    return [self imageTypes];
}

+ (NSArray *) imageUnfilteredFileTypes {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *allClasses = [NSImageRep registeredImageRepClasses];
    int i, count = [allClasses count];

    for (i = 0; i < count; i++)
        [result addObjectsFromArray: [[allClasses objectAtIndex: i]
                                             imageUnfilteredFileTypes]];

    return result;
}

+ (NSArray *) imagePasteboardTypes {
    return [self imageUnfilteredPasteboardTypes];
}

+ (NSArray *) imageUnfilteredPasteboardTypes {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *allClasses = [NSImageRep registeredImageRepClasses];
    int i, count = [allClasses count];

    for (i = 0; i < count; i++)
        [result addObjectsFromArray: [[allClasses objectAtIndex: i]
                                             imageUnfilteredPasteboardTypes]];

    return result;
}

+ (BOOL) canInitWithPasteboard: (NSPasteboard *) pasteboard {
    NSString *available = [pasteboard
            availableTypeFromArray: [self imageUnfilteredPasteboardTypes]];

    return (available != nil) ? YES : NO;
}

+ (NSArray *) _checkBundles {
    return [NSArray
            arrayWithObjects: [NSBundle
                                      mainBundle], // Check the main bundle
                                                   // first according to the doc
                              [NSBundle bundleForClass: self], nil];
}

+ (NSMutableDictionary *) allImages {
    NSMutableDictionary *result = [[[NSThread currentThread] threadDictionary]
            objectForKey: @"__allImages"];

    if (result == nil) {
        result = [NSMutableDictionary dictionary];
        [[[NSThread currentThread] threadDictionary] setObject: result
                                                        forKey: @"__allImages"];
    }

    return result;
}

+ imageNamed: (NSString *) name {
    if (name == nil)
        return nil;

    NSImage *image = [[self allImages] objectForKey: name];
    if (image == nil) {
        NSArray *bundles = [self _checkBundles];
        int i, count = [bundles count];

        for (i = 0; i < count; i++) {
            NSBundle *bundle = [bundles objectAtIndex: i];
            NSString *path = [bundle pathForImageResource: name];

            if (path != nil) {
                image = [[[NSImage alloc] initWithContentsOfFile: path]
                        autorelease];
                [image setName: name];
                if (image) {
                    break;
                }
            }
        }
    }

    // Cocoa AppKit always returns the same shared cached image
    return image;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        NSUInteger length;
        const unsigned char *tiff =
                [keyed decodeBytesForKey: @"NSTIFFRepresentation"
                          returnedLength: &length];
        NSBitmapImageRep *rep;

        if (tiff == NULL) {
            [self release];
            return nil;
        }

        rep = [NSBitmapImageRep
                imageRepWithData: [NSData dataWithBytes: tiff length: length]];
        if (rep == nil) {
            [self release];
            return nil;
        }

        _name = nil;
        _size = NSMakeSize(0, 0);
        NS_EXTRA(NSImage, self)->_representations = [NSMutableArray new];

        [NS_EXTRA(NSImage, self)->_representations addObject: rep];
    } else {
        NSInteger version = [coder versionForClassName: @"NSImage"];

        NS_EXTRA(NSImage, self)->_representations = [NSMutableArray new];

        if (version >= 17) {
            // Layouts as recorded from Mac archives: the name, a byte per flag (12 bytes up to
            // version 44, 13 at 45, 14 at 46, 15 at 47 and 14 from 48 on), an explicit size when
            // flag byte 2 is set, a short, then for each of that many representations a byte and
            // the representation, then the background colour and the delegate.
            _name = [[coder decodeObject] retain];

            int count = version <= 44 ? 12 : version == 45 ? 13 : version == 46 ? 14 : version == 47 ? 15 : 14;
            char flags[16] = { 0 };
            // An image that is archived by name (one of the first two bytes set) has nothing
            // else but those two bytes; it stands for the named image.
            for (int i = 0; i < 2; i++) {
                [coder decodeValuesOfObjCTypes: "c", &flags[i]];
            }
            if (flags[0] || flags[1]) {
                NSImage *named = [NSImage imageNamed: _name];

                if (named != nil && named != self) {
                    [self release];
                    return [named retain];
                }
                return self;
            }

            // Only the first four bytes are read when the fourth selects the shorter layout.
            for (int i = 2; i < 4; i++) {
                [coder decodeValuesOfObjCTypes: "c", &flags[i]];
            }

            if (flags[3]) {
                // A shorter layout follows the first four bytes: the explicit size when byte 2
                // is set, a rectangle-like pair of floats and one object (of unknown meaning,
                // read and dropped).
                float unknownFloats[2];
                if (flags[2]) {
                    float width, height;
                    [coder decodeValuesOfObjCTypes: "ff", &width, &height];
                    _size = NSMakeSize(width, height);
                }
                [coder decodeValuesOfObjCTypes: "ff", &unknownFloats[0], &unknownFloats[1]];
                [coder decodeObject];
                return self;
            }

            for (int i = 4; i < count; i++) {
                [coder decodeValuesOfObjCTypes: "c", &flags[i]];
            }

            if (flags[2]) {
                float width, height;
                [coder decodeValuesOfObjCTypes: "ff", &width, &height];
                _size = NSMakeSize(width, height);
            }

            // The bytes are the image's flag word, one byte per bit: scales when resized (4),
            // data retained (5), cached separately (6), uses EPS on resolution mismatch (7),
            // prefers colour match (8), matches on multiple resolution (9) and flipped (12, from
            // version 45). Bytes 0, 1, 10, 11, 13 and 14 have unknown meaning.
            NS_EXTRA(NSImage, self)->_scalesWhenResized = flags[4] != 0;
            NS_EXTRA(NSImage, self)->_isDataRetained = flags[5] != 0;
            NS_EXTRA(NSImage, self)->_isCachedSeparately = flags[6] != 0;
            NS_EXTRA(NSImage, self)->_usesEPSOnResolutionMismatch = flags[7] != 0;
            NS_EXTRA(NSImage, self)->_prefersColorMatch = flags[8] != 0;
            NS_EXTRA(NSImage, self)->_matchesOnMultipleResolution = flags[9] != 0;
            NS_EXTRA(NSImage, self)->_isFlipped = count > 12 && flags[12] != 0;

            short repCount;
            [coder decodeValueOfObjCType: @encode(short) at: &repCount];
            for (int i = 0; i < repCount; i++) {
                char unknownByte;
                [coder decodeValueOfObjCType: @encode(char) at: &unknownByte];
                id rep = [coder decodeObject];
                if ([rep isKindOfClass: [NSImageRep class]]) {
                    [NS_EXTRA(NSImage, self)->_representations addObject: rep];
                }
            }

            NS_EXTRA(NSImage, self)->_backgroundColor = [[coder decodeObject] retain];
            NS_EXTRA(NSImage, self)->_delegate = [coder decodeObject];
        } else {
            // Up to version 16: a short and the name as one call, a short, and from version 3
            // two objects (version 2: a NeXT colour and one object). What the shorts and the
            // objects mean is unknown beyond the name; objects that are representations are kept.
            short unknownShort1, unknownShort2;
            char *name = NULL;

            [coder decodeValuesOfObjCTypes: "s*", &unknownShort1, &name];
            if (name != NULL) {
                _name = [[NSString alloc] initWithBytesNoCopy: name
                                                       length: strlen(name)
                                                     encoding: NSNEXTSTEPStringEncoding
                                                 freeWhenDone: YES];
            }
            [coder decodeValueOfObjCType: @encode(short) at: &unknownShort2];

            if (version == 2) {
                [coder decodeNXColor];
                id rep = [coder decodeObject];
                if ([rep isKindOfClass: [NSImageRep class]]) {
                    [NS_EXTRA(NSImage, self)->_representations addObject: rep];
                }
            } else if (version >= 3) {
                id first = [coder decodeObject];
                id second = [coder decodeObject];
                if ([first isKindOfClass: [NSImageRep class]]) {
                    [NS_EXTRA(NSImage, self)->_representations addObject: first];
                }
                if ([second isKindOfClass: [NSImageRep class]]) {
                    [NS_EXTRA(NSImage, self)->_representations addObject: second];
                }
            }
        }
    }
    return self;
}

+ (instancetype) imageWithSize: (NSSize) size
                       flipped: (BOOL) flipped
                drawingHandler: (BOOL (^)(NSRect)) handler {
    NSCustomImageRep *rep = [[[NSCustomImageRep alloc]
            initWithSize: size flipped: flipped drawingHandler: handler]
            autorelease];
    if (rep == nil)
        return nil;
    NSImage *image = [[[self alloc] initWithSize: size] autorelease];
    [image addRepresentation: rep];
    return image;
}

- initWithSize: (NSSize) size {
    _name = nil;
    _size = size;
    NS_EXTRA(NSImage, self)->_representations = [NSMutableArray new];
    return self;
}

- init {
    return [self initWithSize: NSMakeSize(0, 0)];
}

// Not in the public headers: wraps a single representation in a new image.
- initWithImageRep: (NSImageRep *) rep {
    if (rep == nil) {
        [self release];
        return nil;
    }
    self = [self initWithSize: [rep size]];
    [self addRepresentation: rep];
    return self;
}

- initWithData: (NSData *) data {
    Class repClass = [NSImageRep imageRepClassForData: data];
    NSArray *reps = nil;

    if ([repClass respondsToSelector: @selector(imageRepsWithData:)])
        reps = [repClass performSelector: @selector(imageRepsWithData:)
                              withObject: data];
    else if ([repClass respondsToSelector: @selector(imageRepWithData:)]) {
        NSImageRep *rep =
                [repClass performSelector: @selector(imageRepWithData:)
                               withObject: data];

        if (rep != nil)
            reps = [NSArray arrayWithObject: rep];
    }

    if ([reps count] == 0) {
        [self release];
        return nil;
    }

    _name = nil;
    _size = NSMakeSize(0, 0);
    NS_EXTRA(NSImage, self)->_representations = [NSMutableArray new];

    [NS_EXTRA(NSImage, self)->_representations addObjectsFromArray: reps];

    return self;
}

- initWithContentsOfFile: (NSString *) path {
    NSArray *reps = [NSImageRep imageRepsWithContentsOfFile: path];

    if ([reps count] == 0) {
        [self release];
        return nil;
    }

    _name = nil;
    _size = NSMakeSize(0, 0);
    NS_EXTRA(NSImage, self)->_representations = [NSMutableArray new];

    [NS_EXTRA(NSImage, self)->_representations addObjectsFromArray: reps];

    return self;
}

- initWithContentsOfURL: (NSURL *) url {
    NSData *data = [NSData dataWithContentsOfURL: url];

    if (data == nil) {
        [self release];
        return nil;
    }

    return [self initWithData: data];
}

- initWithCGImage: (CGImageRef) cgImage size: (NSSize) size; {
    if (self = [self initWithSize: size]) {
        NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
                initWithCGImage: cgImage] autorelease];
        [NS_EXTRA(NSImage, self)->_representations addObject: rep];
    }
    return self;
}

- (CGImageRef) CGImageForProposedRect: (NSRect *) proposedDestRect
                              context: (NSGraphicsContext *) context
                                hints: (NSDictionary *) hints
{
    NSSize size = (proposedDestRect != NULL) ? proposedDestRect->size : [self size];
    if (!(size.width > 0 && size.height > 0 && isfinite(size.width) && isfinite(size.height)))
        return NULL;
    size_t width = ceil(size.width), height = ceil(size.height);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    // An explicit byte order: Onyx2D stores the default order as ABGR, unlike Apple's RGBA.
    CGContextRef bitmap = CGBitmapContextCreate(NULL, width, height, 8, width * 4,
            colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (bitmap == NULL)
        return NULL;
    CGContextClearRect(bitmap, CGRectMake(0, 0, width, height));

    // The thread dictionary may be the only owner of the current context.
    NSGraphicsContext *previous = [[NSGraphicsContext currentContext] retain];
    [NSGraphicsContext setCurrentContext:
            [NSGraphicsContext graphicsContextWithGraphicsPort: bitmap flipped: NO]];
    [self drawInRect: NSMakeRect(0, 0, width, height)
            fromRect: NSZeroRect
           operation: NSCompositeSourceOver
            fraction: 1.0];
    [NSGraphicsContext setCurrentContext: previous];
    [previous release];
    CGImageRef image = CGBitmapContextCreateImage(bitmap);
    CGContextRelease(bitmap);

    // The caller doesn't own the result.
    return (CGImageRef) [(id) image autorelease];
}

- initWithPasteboard: (NSPasteboard *) pasteboard {

    NSString *available =
            [pasteboard availableTypeFromArray:
                                [[self class] imageUnfilteredPasteboardTypes]];
    NSData *data = [pasteboard dataForType: available];
    if (data == nil) {
        [self release];
        return nil;
    }
    return [self initWithData: data];
}

#pragma mark NSPasteboardWriting, NSPasteboardReading

- (NSArray<NSPasteboardType> *) writableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return [NSArray arrayWithObject: NSPasteboardTypeTIFF];
}

- (id) pasteboardPropertyListForType: (NSPasteboardType) type {
    if (!NSPasteboardTypeConformsTo(type, NSPasteboardTypeTIFF))
        return nil;
    return [self TIFFRepresentation];
}

+ (NSArray<NSPasteboardType> *) readableTypesForPasteboard: (NSPasteboard *) pasteboard {
    NSMutableArray *types = [NSMutableArray arrayWithObjects: NSPasteboardTypeTIFF, NSPasteboardTypePNG,
                                                              NSPasteboardTypePDF, nil];
    for (NSPasteboardType type in NSPasteboardCanonicalTypes([self imageUnfilteredPasteboardTypes])) {
        if (![types containsObject: type])
            [types addObject: type];
    }
    return types;
}

- (id) initWithPasteboardPropertyList: (id) propertyList ofType: (NSPasteboardType) type {
    if (![propertyList isKindOfClass: [NSData class]]) {
        [self release];
        return nil;
    }
    return [self initWithData: propertyList];
}

- initByReferencingFile: (NSString *) path {
    return [self initWithContentsOfFile: path];
}

- initByReferencingURL: (NSURL *) url {
    // Better than nothing
    return [self initWithContentsOfURL: url];
}

- (void) dealloc {
    [_name release];
    [NS_EXTRA(NSImage, self)->_backgroundColor release];
    [NS_EXTRA(NSImage, self)->_representations release];
    [NS_EXTRA(NSImage, self)->_accessibilityDescription release];
    [NS_EXTRA(NSImage, self)->_symbolConfiguration release];
    [NS_EXTRA(NSImage, self)->_scaledRepCache release];
    [NS_EXTRA(NSImage, self)->_drawingHandlerRepCache release];
    NS_EXTRA_FREE(NSImage, self);
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSImage *result = NSCopyObject(self, 0, zone);
    NS_EXTRA_COPY(NSImage, result, self);

    result->_name = [_name copy];
    NS_EXTRA(NSImage, result)->_backgroundColor = [NS_EXTRA(NSImage, self)->_backgroundColor copy];
    NS_EXTRA(NSImage, result)->_representations = [NS_EXTRA(NSImage, self)->_representations mutableCopy];
    NS_EXTRA(NSImage, result)->_accessibilityDescription = [NS_EXTRA(NSImage, self)->_accessibilityDescription copy];
    NS_EXTRA(NSImage, result)->_symbolConfiguration = [NS_EXTRA(NSImage, self)->_symbolConfiguration retain];
    NS_EXTRA(NSImage, result)->_scaledRepCache = nil;
    NS_EXTRA(NSImage, result)->_drawingHandlerRepCache = nil;

    return result;
}

- (NSString *) name {
    return _name;
}

- (NSSize) size {
    if (_size.width == 0.0 && _size.height == 0.0) {
        int i, count = [NS_EXTRA(NSImage, self)->_representations count];
        NSSize largestSize = NSMakeSize(0, 0);

        for (i = 0; i < count; i++) {
            NSImageRep *check = [NS_EXTRA(NSImage, self)->_representations objectAtIndex: i];
            NSSize checkSize = [check size];

            if (checkSize.width * checkSize.height >
                largestSize.width * largestSize.height)
                largestSize = checkSize;
        }

        return largestSize;
    }

    return _size;
}

- (NSRect) alignmentRect {
    if (NS_EXTRA(NSImage, self)->_hasCustomAlignmentRect)
        return NS_EXTRA(NSImage, self)->_alignmentRect;

    NSSize size = [self size];
    return NSMakeRect(0, 0, size.width, size.height);
}

- (void) setAlignmentRect: (NSRect) rect {
    NS_EXTRA(NSImage, self)->_alignmentRect = rect;
    NS_EXTRA(NSImage, self)->_hasCustomAlignmentRect = YES;
}

- (NSColor *) backgroundColor {
    return NS_EXTRA(NSImage, self)->_backgroundColor;
}

- (BOOL) isFlipped {
    return NS_EXTRA(NSImage, self)->_isFlipped;
}

- (BOOL) isTemplate {
    return NS_EXTRA(NSImage, self)->_isTemplate;
}

- (BOOL) scalesWhenResized {
    return NS_EXTRA(NSImage, self)->_scalesWhenResized;
}

- (BOOL) matchesOnMultipleResolution {
    return NS_EXTRA(NSImage, self)->_matchesOnMultipleResolution;
}

- (BOOL) usesEPSOnResolutionMismatch {
    return NS_EXTRA(NSImage, self)->_usesEPSOnResolutionMismatch;
}

- (BOOL) prefersColorMatch {
    return NS_EXTRA(NSImage, self)->_prefersColorMatch;
}

- (NSImageCacheMode) cacheMode {
    return NS_EXTRA(NSImage, self)->_cacheMode;
}

- (BOOL) isCachedSeparately {
    return NS_EXTRA(NSImage, self)->_isCachedSeparately;
}

- (BOOL) cacheDepthMatchesImageDepth {
    return NS_EXTRA(NSImage, self)->_cacheDepthMatchesImageDepth;
}

- (BOOL) isDataRetained {
    return NS_EXTRA(NSImage, self)->_isDataRetained;
}

- delegate {
    return NS_EXTRA(NSImage, self)->_delegate;
}

- (BOOL) setName: (NSString *) name {
    if (_name != nil && [[NSImage allImages] objectForKey: _name] == self)
        [[NSImage allImages] removeObjectForKey: _name];

    name = [name copy];
    [_name release];
    _name = name;

    if ([[NSImage allImages] objectForKey: _name] != nil)
        return NO;

    [[NSImage allImages] setObject: self forKey: _name];
    return YES;
}

- (void) setSize: (NSSize) size {
    _size = size;
    [self recache];
}

- (void) setBackgroundColor: (NSColor *) value {
    [NS_EXTRA(NSImage, self)->_drawingHandlerRepCache removeAllObjects];
    value = [value copy];
    [NS_EXTRA(NSImage, self)->_backgroundColor release];
    NS_EXTRA(NSImage, self)->_backgroundColor = value;
}

- (void) setFlipped: (BOOL) value {
    [NS_EXTRA(NSImage, self)->_drawingHandlerRepCache removeAllObjects];
    NS_EXTRA(NSImage, self)->_isFlipped = value;
}

- (void) setTemplate: (BOOL) value {
    NS_EXTRA(NSImage, self)->_isTemplate = value;
}

- (void) setScalesWhenResized: (BOOL) value {
    NS_EXTRA(NSImage, self)->_scalesWhenResized = value;
}

- (void) setMatchesOnMultipleResolution: (BOOL) value {
    NS_EXTRA(NSImage, self)->_matchesOnMultipleResolution = value;
}

- (void) setUsesEPSOnResolutionMismatch: (BOOL) value {
    NS_EXTRA(NSImage, self)->_usesEPSOnResolutionMismatch = value;
}

- (void) setPrefersColorMatch: (BOOL) value {
    NS_EXTRA(NSImage, self)->_prefersColorMatch = value;
}

- (void) setCacheMode: (NSImageCacheMode) value {
    [NS_EXTRA(NSImage, self)->_drawingHandlerRepCache removeAllObjects];
    NS_EXTRA(NSImage, self)->_cacheMode = value;
}

- (void) setCachedSeparately: (BOOL) value {
    NS_EXTRA(NSImage, self)->_isCachedSeparately = value;
}

- (void) setCacheDepthMatchesImageDepth: (BOOL) value {
    NS_EXTRA(NSImage, self)->_cacheDepthMatchesImageDepth = value;
}

- (void) setDataRetained: (BOOL) value {
    NS_EXTRA(NSImage, self)->_isDataRetained = value;
}

- (void) setDelegate: delegate {
    NS_EXTRA(NSImage, self)->_delegate = delegate;
}

- (BOOL) isValid {
    NSUnimplementedMethod();
    return 0;
}

- (NSArray *) representations {
    return NS_EXTRA(NSImage, self)->_representations;
}

- (void) addRepresentation: (NSImageRep *) representation {
    if (representation != nil) {
        [NS_EXTRA(NSImage, self)->_representations addObject: representation];
        [NS_EXTRA(NSImage, self)->_drawingHandlerRepCache removeAllObjects];
        [NS_EXTRA(NSImage, self)->_scaledRepCache removeAllObjects];
    }
}

- (void) addRepresentations: (NSArray *) array {
    int i, count = [array count];

    for (i = 0; i < count; i++)
        [self addRepresentation: [array objectAtIndex: i]];
}

- (void) removeRepresentation: (NSImageRep *) representation {
    [NS_EXTRA(NSImage, self)->_drawingHandlerRepCache removeAllObjects];
    [NS_EXTRA(NSImage, self)->_representations removeObjectIdenticalTo: representation];
    [NS_EXTRA(NSImage, self)->_scaledRepCache removeAllObjects];
}

- (NSCachedImageRep *) _cachedImageRepCreateIfNeeded {
    int count = [NS_EXTRA(NSImage, self)->_representations count];

    while (--count >= 0) {
        NSCachedImageRep *check = [NS_EXTRA(NSImage, self)->_representations objectAtIndex: count];

        if ([check isKindOfClass: [NSCachedImageRep class]]) {

            if (NS_EXTRA(NSImage, self)->_cacheIsValid)
                return check;

            [NS_EXTRA(NSImage, self)->_representations removeObjectAtIndex: count];
        }
    }

    NSCachedImageRep *cached =
            [[NSCachedImageRep alloc] initWithSize: [self size]
                                             depth: 0
                                          separate: NS_EXTRA(NSImage, self)->_isCachedSeparately
                                             alpha: YES];
    [self addRepresentation: cached];
    [cached release];
    return cached;
}

- (NSImageRep *) _bestUncachedRepresentationForDevice: (NSDictionary *) device {
    int i, count = [NS_EXTRA(NSImage, self)->_representations count];

    for (i = 0; i < count; i++) {
        NSImageRep *check = [NS_EXTRA(NSImage, self)->_representations objectAtIndex: i];

        if (![check isKindOfClass: [NSCachedImageRep class]]) {
            return check;
        }
    }

    return nil;
}

- (NSImageRep *)
        _bestUncachedFallbackCachedRepresentationForDevice:
                (NSDictionary *) device
                                                      size: (NSSize) size
{
    int i, count = [NS_EXTRA(NSImage, self)->_representations count];
    NSImageRep *best = nil;

    size.width = ABS(size.width);
    size.height = ABS(size.height);

    for (i = 0; i < count; i++) {
        NSImageRep *check = [NS_EXTRA(NSImage, self)->_representations objectAtIndex: i];

        if (![check isKindOfClass: [NSCachedImageRep class]]) {
            if (best == nil)
                best = check;
            else {
                NSSize checkSize = [check size];
                NSSize bestSize = [best size];
                CGFloat checkArea = checkSize.width * checkSize.height;
                CGFloat bestArea = bestSize.width * bestSize.height;
                CGFloat desiredArea = size.width * size.height;

                // downsampling is better than upsampling
                if (bestArea < desiredArea && checkArea >= desiredArea)
                    best = check;
                // downsampling a closer image is better
                if (checkArea < bestArea && checkArea >= desiredArea)
                    best = check;
                // if we have to upsample, biggest is better
                if (checkArea > bestArea && bestArea < desiredArea)
                    best = check;
            }
        }
    }

    if (best != nil)
        return best;

    for (i = 0; i < count; i++) {
        NSImageRep *check = [NS_EXTRA(NSImage, self)->_representations objectAtIndex: i];

        if ([check isKindOfClass: [NSCachedImageRep class]]) {
            return check;
        }
    }

    return nil;
}

- (NSImageRep *) bestRepresentationForDevice: (NSDictionary *) device {
    if (device == nil)
        device = [[NSGraphicsContext currentContext] deviceDescription];

    if ([device objectForKey: NSDeviceIsPrinter] != nil) {
        int i, count = [NS_EXTRA(NSImage, self)->_representations count];

        for (i = 0; i < count; i++) {
            NSImageRep *check = [NS_EXTRA(NSImage, self)->_representations objectAtIndex: i];

            if (![check isKindOfClass: [NSCachedImageRep class]])
                return check;
        }
    }

    if ([device objectForKey: NSDeviceIsScreen] != nil) {
        NSImageRep *uncached =
                [self _bestUncachedRepresentationForDevice: device];
        NSImageCacheMode caching = NS_EXTRA(NSImage, self)->_cacheMode;

        if (caching == NSImageCacheDefault) {
            if ([uncached isKindOfClass: [NSBitmapImageRep class]])
                caching = NSImageCacheBySize;
            else if ([uncached isKindOfClass: [NSPDFImageRep class]])
                caching = NSImageCacheAlways;
            else if ([uncached isKindOfClass: [NSEPSImageRep class]])
                caching = NSImageCacheAlways;
            else if ([uncached isKindOfClass: [NSCustomImageRep class]])
                caching = NSImageCacheAlways;
        }

        switch (caching) {

        case NSImageCacheDefault:
        case NSImageCacheAlways:
            break;

        case NSImageCacheBySize:
            if ([[uncached colorSpaceName]
                        isEqual: [device objectForKey:
                                                 NSDeviceColorSpaceName]]) {
                NSSize size = [self size];

                if ((size.width == [uncached pixelsWide]) &&
                    (size.height == [uncached pixelsHigh])) {
                    int deviceBPS = [[device
                            objectForKey: NSDeviceBitsPerSample] intValue];

                    if (deviceBPS == [uncached bitsPerSample])
                        return uncached;
                }
            }
            break;

        case NSImageCacheNever:
            return uncached;
        }

        NSCachedImageRep *cached = [self _cachedImageRepCreateIfNeeded];

        if (!NS_EXTRA(NSImage, self)->_cacheIsValid) {
            [self lockFocusOnRepresentation: cached];
            BOOL rendered = NO;
            @try {
                NSRect rect;
                rect.origin = NSZeroPoint;
                rect.size = [self size];
                if ([self scalesWhenResized]) {
                    rendered = [self drawRepresentation: uncached inRect: rect];
                } else
                    rendered = [uncached drawAtPoint: rect.origin];
            } @finally {
                [self unlockFocus];
                // Do not leave a partially rendered cache available to other
                // representation-selection paths, including after an exception.
                if (!rendered)
                    [self removeRepresentation: cached];
            }
            NS_EXTRA(NSImage, self)->_cacheIsValid = rendered;
        }

        return NS_EXTRA(NSImage, self)->_cacheIsValid ? cached : uncached;
    }

    return [NS_EXTRA(NSImage, self)->_representations lastObject];
}

- (void) recache {
    [NS_EXTRA(NSImage, self)->_drawingHandlerRepCache removeAllObjects];
    // This doesn't actually remove the cache, it just marks it as invalid
    // This is important because you can change the size of a drawn image
    // and it doesn't destroy the cache. It is recached next time it is drawn.
    NS_EXTRA(NSImage, self)->_cacheIsValid = NO;

    // The pre-scaled representations are derived from the reps and from
    // -size, so they do not survive this. -setSize: goes through here too.
    [NS_EXTRA(NSImage, self)->_scaledRepCache removeAllObjects];
}

- (void) cancelIncrementalLoad {
    NSUnimplementedMethod();
}

- (NSData *) TIFFRepresentation {
    return [self TIFFRepresentationUsingCompression: NSTIFFCompressionNone
                                             factor: 0.0];
}

- (NSData *) TIFFRepresentationUsingCompression: (NSTIFFCompression) compression
                                         factor: (float) factor
{
    NSMutableArray *bitmaps = [NSMutableArray array];

    for (NSImageRep *check in NS_EXTRA(NSImage, self)->_representations) {
        if ([check isKindOfClass: [NSBitmapImageRep class]]) {
            [bitmaps addObject: check];
        } else if ([check isKindOfClass: [NSCachedImageRep class]]) {
            // We don't use the general case else we get flipped results for
            // flipped images since lockFocusOnRepresentation is flipping and
            // the Cache content is already flipped
            NSRect r = {.origin = NSZeroPoint, .size = check.size};
            [self lockFocus];
            NSBitmapImageRep *image =
                    [[NSBitmapImageRep alloc] initWithFocusedViewRect: r];
            [self unlockFocus];

            [bitmaps addObject: image];
            [image release];
        } else {
            NSSize size = [check size];
            NSBitmapImageRep *image = [[NSBitmapImageRep alloc]
                    initWithBitmapDataPlanes: NULL
                                  pixelsWide: size.width
                                  pixelsHigh: size.height
                               bitsPerSample: 8
                             samplesPerPixel: 4
                                    hasAlpha: YES
                                    isPlanar: NO
                              colorSpaceName: NSDeviceRGBColorSpace
                                 bytesPerRow: 0
                                bitsPerPixel: 32];

            [self lockFocusOnRepresentation: image];
            // we should probably use -draw here but not all reps implement it,
            // or not?
            [check draw];
            [self unlockFocus];

            [bitmaps addObject: image];
            [image release];
        }
    }

    return [NSBitmapImageRep TIFFRepresentationOfImageRepsInArray: bitmaps
                                                 usingCompression: compression
                                                           factor: factor];
}

- (void) lockFocus {
    [self lockFocusOnRepresentation: nil];
}

- (void) lockFocusOnRepresentation: (NSImageRep *) representation {
    NSGraphicsContext *context = nil;
    CGContextRef graphicsPort;

    if (representation == nil) {
        // FIXME: Cocoa doesn't add the cached rep until the unlockFocus, it
        // just creates the drawing context then snaps the image during unlock
        // and adds it
        representation = [self _cachedImageRepCreateIfNeeded];

        [self lockFocusOnRepresentation: representation];
        NSRect rect;
        NSImageRep *uncached = [self _bestUncachedRepresentationForDevice: nil];
        rect.origin.x = 0;
        rect.origin.y = 0;
        rect.size = [self size];

        //    if([self scalesWhenResized])
        [uncached drawInRect: rect];
        // drawAtPoint: is not working with NSPDFImageRep
        // Should probably ditch all the caching stuff anyway as it is
        // deprecated
        //   else
        //   [uncached drawAtPoint:rect.origin];

        [self unlockFocus];
        NS_EXTRA(NSImage, self)->_cacheIsValid = YES;
    }

    if ([representation isKindOfClass: [NSCachedImageRep class]])
        context = [NSGraphicsContext
                graphicsContextWithWindow: [(NSCachedImageRep *) representation
                                                   window]];
    else if ([representation isKindOfClass: [NSBitmapImageRep class]])
        context = [NSGraphicsContext
                graphicsContextWithBitmapImageRep: (NSBitmapImageRep *)
                                                           representation];

    if (context == nil) {
        [NSException raise: NSInvalidArgumentException
                    format: @"NSImageRep %@ can not be lockFocus'd", representation];
        return;
    }

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];

    graphicsPort = NSCurrentGraphicsPort();
    CGContextSaveGState(graphicsPort);
    CGContextClipToRect(graphicsPort,
                        NSMakeRect(0, 0, [representation size].width,
                                   [representation size].height));

    // Some fake view, just so the context knows if it's flipped or not
    NSView *view = [[[NSImageCacheView alloc] initWithFlipped: [self isFlipped]]
            autorelease];
    [[context focusStack] addObject: self];

    if ([self isFlipped]) {
        CGAffineTransform flip = {1, 0, 0, -1, 0, [self size].height};
        CGContextConcatCTM(graphicsPort, flip);
    }
}

- (void) unlockFocus {
    // Remove the pushed view
    [[[NSGraphicsContext currentContext] focusStack] removeLastObject];

    CGContextRef graphicsPort = NSCurrentGraphicsPort();

    CGContextRestoreGState(graphicsPort);

    [NSGraphicsContext restoreGraphicsState];
}

- (BOOL) drawRepresentation: (NSImageRep *) representation
                     inRect: (NSRect) rect
{
    NSColor *bg = [self backgroundColor];

    if (bg != nil) {
        [bg setFill];
        NSRectFill(rect);
    }

    return [representation drawInRect: rect];
}

- (void) compositeToPoint: (NSPoint) point
                 fromRect: (NSRect) rect
                operation: (NSCompositingOperation) operation
{
    [self compositeToPoint: point
                  fromRect: rect
                 operation: operation
                  fraction: 1.0];
}

- (void) compositeToPoint: (NSPoint) point
                 fromRect: (NSRect) source
                operation: (NSCompositingOperation) operation
                 fraction: (CGFloat) fraction
{
    /* Compositing is a blitting operation. We simulate it using the draw
       operation.

       Compositing does not honor all aspects of the CTM, e.g. it will keep an
       image upright regardless of the orientation of CTM. To deal with that we
       use a negative height in a flipped coordinate system. There are probably
       other cases which are not right here.
     */

    NSSize size = [self size];
    NSRect rect = NSMakeRect(point.x, point.y, size.width, size.height);

    NSGraphicsContext *graphicsContext = [NSGraphicsContext currentContext];
    CGContextRef context = [graphicsContext graphicsPort];

    CGContextSaveGState(context);
    if ([[NSGraphicsContext currentContext] isFlipped]) {
        rect.size.height = -rect.size.height;
    }

    [self drawInRect: rect
             fromRect: source
            operation: operation
             fraction: fraction];
    CGContextRestoreGState(context);
}

- (void) compositeToPoint: (NSPoint) point
                operation: (NSCompositingOperation) operation
{
    [self compositeToPoint: point operation: operation fraction: 1.0];
}

- (void) compositeToPoint: (NSPoint) point
                operation: (NSCompositingOperation) operation
                 fraction: (CGFloat) fraction
{
    [self compositeToPoint: point
                  fromRect: NSZeroRect
                 operation: operation
                  fraction: 1.0];
}

- (void) dissolveToPoint: (NSPoint) point fraction: (CGFloat) fraction {
    NSUnimplementedMethod();
}

- (void) dissolveToPoint: (NSPoint) point
                fromRect: (NSRect) rect
                fraction: (CGFloat) fraction
{
    NSUnimplementedMethod();
}

- (void) drawAtPoint: (NSPoint) point
            fromRect: (NSRect) source
           operation: (NSCompositingOperation) operation
            fraction: (CGFloat) fraction
{
    NSSize size = [self size];

    [self drawInRect: NSMakeRect(point.x, point.y, size.width, size.height)
             fromRect: source
            operation: operation
             fraction: fraction];
}

/* NSImage.h declares -[NSImage drawInRect:] but nothing implemented it: only the
 * fromRect:operation:fraction: variants below existed, so calling it raised
 * "unrecognized selector". Any app drawing an image the ordinary way hit that. An empty
 * source rect is how the variant below spells "the whole image". */
- (void) drawInRect: (NSRect) rect {
    [self drawInRect: rect
            fromRect: NSZeroRect
           operation: NSCompositeSourceOver
            fraction: 1.0];
}

// Bounds on the pre-scaled representations kept per image. The count bounds
// the linear lookup below and the number of live entries; the byte budget
// bounds what they actually cost, since entries are destination-sized RGBA
// bitmaps and a few large ones outweigh many small ones. Refusing any single
// entry larger than the budget also keeps the pixel counts inside the int
// arithmetic NSBitmapImageRep sizes its allocation with.
enum {
    scaledRepCacheCapacity = 4
};
static const NSUInteger scaledRepCacheByteBudget = 16 * 1024 * 1024;

// A cache entry is {source representation, bitmap pre-scaled from it}, and
// _scaledRepCache holds them least recently used first.
static NSUInteger scaledRepBytes(NSBitmapImageRep *rep) {
    return (NSUInteger) [rep pixelsWide] * (NSUInteger) [rep pixelsHigh] * 4;
}

static NSUInteger scaledRepCacheBytes(NSArray *cache) {
    NSUInteger total = 0;

    for (NSArray *entry in cache)
        total += scaledRepBytes([entry objectAtIndex: 1]);

    return total;
}

// Returns sourceRep rasterized at the device resolution destRect maps to, or
// nil when that would not pay off or cannot be produced.
//
// Only for callers drawing the whole of an unflipped image:
// -lockFocusOnRepresentation: builds its flip transform from -size, which is
// not the size being rasterized here. The returned representation is never
// added to -representations, so it can never become the source of a later
// draw.
- (NSBitmapImageRep *) _scaledRepresentationOf: (NSImageRep *) sourceRep
                                      destRect: (NSRect) destRect
{
    // NSImageCacheNever is the caller asking for no rasterization to be kept
    // on the image.
    if (NS_EXTRA(NSImage, self)->_cacheMode == NSImageCacheNever)
        return nil;

    // A print or PDF destination wants the source representation at its own
    // resolution, not one resampled down to the page's device transform.
    if (![[NSGraphicsContext currentContext] isDrawingToScreen])
        return nil;

    // The pre-scaled copy is made with the default resampling, so with interpolation
    // turned off the source has to be sampled by the draw itself.
    if ([[NSGraphicsContext currentContext] imageInterpolation] == NSImageInterpolationNone)
        return nil;

    CGAffineTransform toDevice = CGContextGetUserSpaceToDeviceSpaceTransform(
            NSCurrentGraphicsPort());

    // The whole saving is that later draws blit one to one, which O2 only
    // does for an axis-aligned unit-scale transform. If the destination is
    // rotated or sheared, or does not land on a whole number of device
    // pixels, the entry would be resampled on every draw anyway and the cache
    // would be pure overhead.
    if (toDevice.b != 0.0 || toDevice.c != 0.0)
        return nil;

    CGFloat wide = destRect.size.width * ABS(toDevice.a);
    CGFloat high = destRect.size.height * ABS(toDevice.d);

    // Inverted so that a NaN or infinite size or transform is rejected too,
    // every comparison against those being false.
    if (!(wide >= 1.0 && high >= 1.0 && wide == floor(wide) &&
          high == floor(high) &&
          wide * high * 4.0 <= (CGFloat) scaledRepCacheByteBudget))
        return nil;

    int pixelsWide = (int) wide;
    int pixelsHigh = (int) high;

    // Nothing to save when the source already rasterizes one to one.
    if (pixelsWide == [sourceRep pixelsWide] &&
        pixelsHigh == [sourceRep pixelsHigh])
        return nil;

    // The source is part of an entry's identity, not just the resolution:
    // -_bestUncachedFallbackCachedRepresentationForDevice:size: picks it by
    // the size in points, so two draws landing on the same device pixels from
    // different point sizes can want different source artwork.
    NSArray *hit = nil;

    for (NSArray *entry in NS_EXTRA(NSImage, self)->_scaledRepCache) {
        NSBitmapImageRep *scaled = [entry objectAtIndex: 1];

        if ([entry objectAtIndex: 0] == sourceRep &&
            [scaled pixelsWide] == pixelsWide &&
            [scaled pixelsHigh] == pixelsHigh) {
            hit = entry;
            break;
        }
    }

    if (hit != nil) {
        // Move to the most recently used end. The retain spans the removal,
        // which would otherwise drop the last reference to the entry.
        [[hit retain] autorelease];
        [NS_EXTRA(NSImage, self)->_scaledRepCache removeObjectIdenticalTo: hit];
        [NS_EXTRA(NSImage, self)->_scaledRepCache addObject: hit];
        return [hit objectAtIndex: 1];
    }

    NSBitmapImageRep *scaled = [[[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes: NULL
                          pixelsWide: pixelsWide
                          pixelsHigh: pixelsHigh
                       bitsPerSample: 8
                     samplesPerPixel: 4
                            hasAlpha: YES
                            isPlanar: NO
                      colorSpaceName: NSDeviceRGBColorSpace
                         bytesPerRow: 0
                        bitsPerPixel: 32] autorelease];

    // Not merely defensive: -lockFocusOnRepresentation: takes nil to mean
    // "recache the whole image", which is not what a failed allocation should
    // trigger.
    if (scaled == nil)
        return nil;

    // The background color is deliberately not baked in: the caller's
    // -drawRepresentation:inRect: applies it to this entry exactly as it would
    // to the source representation.
    [self lockFocusOnRepresentation: scaled];
    BOOL rendered = NO;
    @try {
        rendered = [sourceRep drawInRect:
                NSMakeRect(0, 0, pixelsWide, pixelsHigh)];
    } @finally {
        [self unlockFocus];
    }
    if (!rendered)
        return nil;

    if (NS_EXTRA(NSImage, self)->_scaledRepCache == nil)
        NS_EXTRA(NSImage, self)->_scaledRepCache = [[NSMutableArray alloc] init];

    // Evict least recently used entries until the new one fits both bounds.
    while ([NS_EXTRA(NSImage, self)->_scaledRepCache count] > 0 &&
           ([NS_EXTRA(NSImage, self)->_scaledRepCache count] >= scaledRepCacheCapacity ||
            scaledRepCacheBytes(NS_EXTRA(NSImage, self)->_scaledRepCache) + scaledRepBytes(scaled) >
                    scaledRepCacheByteBudget))
        [NS_EXTRA(NSImage, self)->_scaledRepCache removeObjectAtIndex: 0];

    [NS_EXTRA(NSImage, self)->_scaledRepCache
            addObject: [NSArray arrayWithObjects: sourceRep, scaled, nil]];
    return scaled;
}

- (NSImageDrawingCache *) _drawingHandlerCache {
    if (NS_EXTRA(NSImage, self)->_drawingHandlerRepCache == nil)
        NS_EXTRA(NSImage, self)->_drawingHandlerRepCache = [NSImageDrawingCache new];
    return NS_EXTRA(NSImage, self)->_drawingHandlerRepCache;
}

// Nine-part drawing. The cap insets cut the image into four corners, four edges and a centre.
// The corners are drawn at their natural size in the corners of the destination, and the edges
// and the centre fill what is left, either stretched or, with NSImageResizingModeTile, repeated
// from the lower left corner of each destination part and clipped to it. With no caps the
// whole image is the centre, so tile mode repeats the image. Geometry is in the image's own
// (y up) space; flipping is left to the plain drawing of each part. Returns NO when the image
// is drawn the ordinary way: stretch mode without caps, a partial source rectangle or a
// destination with a negative size (as composite drawing in a flipped context passes).
- (BOOL) _drawNinePartInRect: (NSRect) rect
                    fromRect: (NSRect) source
                   operation: (NSCompositingOperation) operation
                    fraction: (CGFloat) fraction
{
    NSEdgeInsets caps = NS_EXTRA(NSImage, self)->_capInsets;
    BOOL hasCaps = caps.top > 0 || caps.left > 0 || caps.bottom > 0 || caps.right > 0;
    if (!hasCaps && NS_EXTRA(NSImage, self)->_resizingMode != NSImageResizingModeTile)
        return NO;

    NSSize size = [self size];
    NSRect fullRect = {.origin = NSZeroPoint, .size = size};
    if (!NSIsEmptyRect(source) && !NSEqualRects(source, fullRect))
        return NO;
    if (!(size.width > 0) || !(size.height > 0) || !(rect.size.width > 0) || !(rect.size.height > 0) ||
        !isfinite(rect.origin.x) || !isfinite(rect.origin.y) || !isfinite(rect.size.width) ||
        !isfinite(rect.size.height))
        return NO;

    // Caps are clamped so that opposite caps do not exceed the image.
    CGFloat left = MIN(MAX(caps.left, 0), size.width);
    CGFloat right = MIN(MAX(caps.right, 0), size.width - left);
    CGFloat bottom = MIN(MAX(caps.bottom, 0), size.height);
    CGFloat top = MIN(MAX(caps.top, 0), size.height - bottom);

    // Column and row extents in the image and in the destination, lower left first. The
    // centre is empty in the destination when the caps do not fit.
    CGFloat srcX[3] = {0, left, size.width - right};
    CGFloat srcW[3] = {left, size.width - left - right, right};
    CGFloat srcY[3] = {0, bottom, size.height - top};
    CGFloat srcH[3] = {bottom, size.height - bottom - top, top};
    CGFloat dstX[3] = {rect.origin.x, rect.origin.x + left, NSMaxX(rect) - right};
    CGFloat dstW[3] = {left, MAX(rect.size.width - left - right, 0), right};
    CGFloat dstY[3] = {rect.origin.y, rect.origin.y + bottom, NSMaxY(rect) - top};
    CGFloat dstH[3] = {bottom, MAX(rect.size.height - bottom - top, 0), top};

    CGContextRef context = NSCurrentGraphicsPort();

    // Bottom row first, then upwards, each row from left to right: where the caps overlap in
    // a destination smaller than they are, the later part is on top.
    for (int row = 0; row < 3; row++) {
        for (int column = 0; column < 3; column++) {
            if (srcW[column] <= 0 || srcH[row] <= 0 || dstW[column] <= 0 || dstH[row] <= 0)
                continue;
            NSRect from = NSMakeRect(srcX[column], srcY[row], srcW[column], srcH[row]);
            NSRect to = NSMakeRect(dstX[column], dstY[row], dstW[column], dstH[row]);
            BOOL isCorner = (column != 1 && row != 1);
            // A very large number of tiles is drawn stretched instead.
            BOOL tooManyTiles = ceil(to.size.width / from.size.width) * ceil(to.size.height / from.size.height) > 1000000;
            if (isCorner || NS_EXTRA(NSImage, self)->_resizingMode != NSImageResizingModeTile || tooManyTiles) {
                [self _drawPlainInRect: to fromRect: from operation: operation fraction: fraction];
                continue;
            }
            // A tiled part: whole tiles from the lower left, clipped to the part. An edge
            // is as thick as its cap, so it repeats along its length only.
            CGContextSaveGState(context);
            CGContextClipToRect(context, NSRectToCGRect(to));
            for (CGFloat y = to.origin.y; y < NSMaxY(to); y += from.size.height) {
                for (CGFloat x = to.origin.x; x < NSMaxX(to); x += from.size.width) {
                    [self _drawPlainInRect: NSMakeRect(x, y, from.size.width, from.size.height)
                                  fromRect: from
                                 operation: operation
                                  fraction: fraction];
                }
            }
            CGContextRestoreGState(context);
        }
    }
    return YES;
}

- (void) drawInRect: (NSRect) rect
           fromRect: (NSRect) source
          operation: (NSCompositingOperation) operation
           fraction: (CGFloat) fraction
{
    if (![self _drawNinePartInRect: rect
                          fromRect: source
                         operation: operation
                          fraction: fraction])
    {
        [self _drawPlainInRect: rect
                      fromRect: source
                     operation: operation
                      fraction: fraction];
    }
}

// The image drawn as one piece, stretched to fill the rectangle.
- (void) _drawPlainInRect: (NSRect) rect
                 fromRect: (NSRect) source
                operation: (NSCompositingOperation) operation
                 fraction: (CGFloat) fraction
{

    // Keep a lid on any intermediate allocations while producing caches
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    @try {
        NSImageRep *any = [[[self
                _bestUncachedFallbackCachedRepresentationForDevice: nil
                                                              size: rect.size]
                retain] autorelease];
        NSImageRep *cachedRep = nil;
        CGContextRef context;
        NSRect fullRect = {.origin = NSZeroPoint, .size = self.size};
        BOOL drawFullImage =
                (NSIsEmptyRect(source) || NSEqualRects(source, fullRect));
        BOOL canCache = drawFullImage && !NS_EXTRA(NSImage, self)->_isFlipped;

        if (canCache) {
            // If we're drawing the full image unflipped then we can just draw from
            // a cached rep or a bitmap rep (assuming we have one)
            if ([any isKindOfClass: [NSCachedImageRep class]] ||
                [any isKindOfClass: [NSBitmapImageRep class]]) {
                cachedRep = any;
            }
        }

        if (cachedRep == nil) {
            // Looks like we need to create a cached rep for this image
            NSImageRep *uncached = any;
            NSSize uncachedSize = [uncached size];
            BOOL useSourceRect = NSIsEmptyRect(source) ? NO : YES;
            NSSize cachedSize = useSourceRect ? source.size : uncachedSize;
            NSSize logicalCacheSize = cachedSize;
            CGFloat cacheScaleX = 1, cacheScaleY = 1;
            NSArray *drawingCacheKey = nil;
            NSUInteger drawingCacheGeneration = 0;
            BOOL usesDrawingHandler =
                    [uncached isKindOfClass: [NSCustomImageRep class]] &&
                    [(NSCustomImageRep *)uncached drawingHandler] != nil;
            if (usesDrawingHandler) {
                CGAffineTransform destination =
                        CGContextGetUserSpaceToDeviceSpaceTransform(NSCurrentGraphicsPort());
                CGFloat width = ceil(ABS(rect.size.width) *
                        hypot(destination.a, destination.b));
                CGFloat height = ceil(ABS(rect.size.height) *
                        hypot(destination.c, destination.d));
                // Invalid geometry must not fall through to an unrelated
                // logical-size window allocation or invoke the handler.
                if (!isfinite(logicalCacheSize.width) ||
                    !isfinite(logicalCacheSize.height) ||
                    logicalCacheSize.width <= 0 || logicalCacheSize.height <= 0 ||
                    !isfinite(width) || !isfinite(height) || width < 1 || height < 1 ||
                    width > INT32_MAX || height > INT32_MAX)
                    return;
                // NSBitmapImageRep's row stride and allocation product use int.
                // Supply an explicit stride and reject unrepresentable products
                // before entering its initializer (including transient rasters).
                if (width > INT32_MAX / 4 || height > INT32_MAX / (width * 4))
                    return;
                {
                    // Retention policy must not reduce rendering resolution.
                    // Oversized rasters are transient, not logical-size fallbacks.
                    cachedSize = NSMakeSize(width, height);
                    cacheScaleX = width / logicalCacheSize.width;
                    cacheScaleY = height / logicalCacheSize.height;
                    if (width * height <= 16 * 1024 * 1024 / 4 &&
                        NS_EXTRA(NSImage, self)->_cacheMode != NSImageCacheNever &&
                        [NSGraphicsContext currentContext] != nil) {
                        drawingCacheKey = @[
                            uncached, [NSGraphicsContext currentContext],
                            [NSValue valueWithRect: source], [NSValue valueWithRect: rect],
                            [NSValue valueWithSize: [self size]],
                            [NSValue valueWithSize: uncachedSize],
                            @(destination.a), @(destination.b), @(destination.c),
                            @(destination.d), @(destination.tx), @(destination.ty),
                            @(NS_EXTRA(NSImage, self)->_isFlipped), NS_EXTRA(NSImage, self)->_backgroundColor ?: (id)[NSNull null],
                            [NSAppearance currentAppearance] ?: (id)[NSNull null]
                        ];
                        cachedRep = [[self _drawingHandlerCache]
                                representationForKey: drawingCacheKey];
                        drawingCacheGeneration = [[self _drawingHandlerCache] generation];
                    }
                }
            }

            if (cachedRep == nil) {
                // Create a cached image rep to hold our image
                NSImageRep *cached;
                if (usesDrawingHandler) {
                    // A window-backed cache inherits the screen's backing scale,
                    // even when the destination is an unrelated bitmap. Allocate
                    // exactly the destination device footprint instead.
                    cached = [[[NSBitmapImageRep alloc]
                            initWithBitmapDataPlanes: NULL
                            pixelsWide: (int)cachedSize.width
                            pixelsHigh: (int)cachedSize.height
                            bitsPerSample: 8 samplesPerPixel: 4
                            hasAlpha: YES isPlanar: NO
                            colorSpaceName: NSDeviceRGBColorSpace
                            bitmapFormat: 0
                            bytesPerRow: (int)cachedSize.width * 4
                            bitsPerPixel: 32] autorelease];
                } else {
                    cached =
                        [[[NSCachedImageRep alloc] initWithSize: cachedSize
                                                          depth: 0
                                                       separate: YES
                                                          alpha: YES]
                                autorelease]; // remember that pool we created earlier
                }

                if (cached == nil)
                    return;

                // a non-nil object passed here means we need to manually add the rep
                [self lockFocusOnRepresentation: cached];

                BOOL rendered = NO;
                @try {
                    context = NSCurrentGraphicsPort();
                    if (usesDrawingHandler && NS_EXTRA(NSImage, self)->_isFlipped) {
                        // lockFocus installed an image-sized flip before the cache's
                        // density/crop transform. Undo it before setting up that transform;
                        // the flipped-image adjustment below is in source coordinates.
                        CGContextTranslateCTM(context, 0, [self size].height);
                        CGContextScaleCTM(context, 1, -1);
                    }
                    CGContextScaleCTM(context, cacheScaleX, cacheScaleY);
                    if (useSourceRect) {
                        // move to the origin of the source rect - remember we've locked
                        // focus so we've got a fresh CTM to work with
                        CGContextTranslateCTM(context, -source.origin.x, -source.origin.y);
                    }
                    if (NS_EXTRA(NSImage, self)->_isFlipped) {
                        // Flip the CTM so the image is drawn the right way up in the cache
                        CGContextTranslateCTM(context, 0, uncachedSize.height);
                        CGContextScaleCTM(context, 1, -1);
                    }
                    // Draw into the new cache rep
                    rendered = [self drawRepresentation: uncached
                                      inRect: NSMakeRect(0, 0, uncachedSize.width,
                                                         uncachedSize.height)];

                } @finally {
                    [self unlockFocus];
                }
                if (!rendered)
                    return;

                // And keep it if it makes sense
                if (usesDrawingHandler) {
                    // Account for actual backing density and row padding, not
                    // the requested logical size or an assumed four-byte pixel.
                    NSUInteger rowBytes = CGBitmapContextGetBytesPerRow(context);
                    NSUInteger rows = CGBitmapContextGetHeight(context);
                    // A handler may invalidate its image while drawing. Do not
                    // publish a result computed before that invalidation.
                    if (rowBytes != 0 && rows != 0 && rows <= NSUIntegerMax / rowBytes &&
                        rendered && drawingCacheKey != nil &&
                        drawingCacheGeneration == [[self _drawingHandlerCache] generation])
                        [[self _drawingHandlerCache] setRepresentation: cached
                                forKey: drawingCacheKey
                                byteCost: rowBytes * rows];
                } else if (canCache) {
                    [self addRepresentation: cached];
                }

                cachedRep = cached;
            }
        }

        // A full bitmap drawn scaled this frame is very likely to be drawn at the
        // same scale on the next one (a scrolling icon grid), so re-interpolating
        // it every frame is wasted work.
        if (canCache && [cachedRep isKindOfClass: [NSBitmapImageRep class]] &&
            !([any isKindOfClass: [NSCustomImageRep class]] &&
              [(NSCustomImageRep *)any drawingHandler] != nil)) {
            NSBitmapImageRep *scaled = [self _scaledRepresentationOf: cachedRep
                                                            destRect: rect];

            if (scaled != nil)
                cachedRep = scaled;
        }

        // OK now we've got a rep we can draw

        context = NSCurrentGraphicsPort();

        CGContextSaveGState(context);

        if (CGContextSupportsGlobalAlpha(context) == NO) {
            // That should really be done by setting the context alpha - and the
            // compositing done in the context implementation
            if (fraction != 1.0) {
                // fraction is accomplished with a 1x1 alpha mask
                // FIXME: could use a float format image to completely preserve
                // fraction
                uint8_t bytes[1] = {MIN(MAX(0, fraction * 255), 255)};
                CGDataProviderRef provider =
                        CGDataProviderCreateWithData(NULL, bytes, 1, NULL);
                CGImageRef mask =
                        CGImageMaskCreate(1, 1, 8, 8, 1, provider, NULL, NO);

                CGContextClipToMask(context, rect, mask);
                CGImageRelease(mask);
                CGDataProviderRelease(provider);
            }
        } else {
            CGContextSetAlpha(context, fraction);
        }
        [[NSGraphicsContext currentContext] setCompositingOperation: operation];

        [self drawRepresentation: cachedRep inRect: rect];

        CGContextRestoreGState(context);

    } @finally {
        [pool release];
    }
}

- (void) drawInRect: (NSRect) rect
           fromRect: (NSRect) source
          operation: (NSCompositingOperation) operation
           fraction: (CGFloat) fraction
     respectFlipped: (BOOL) respectFlipped
                 hints: (NSDictionary<NSString *, id> *) hints
{
    NSImage *image = self;
    NSNumber *scale = [hints objectForKey: NSImageHintSymbolScale];
    if (NS_EXTRA(NSImage, self)->_symbolConfiguration != nil && [scale respondsToSelector: @selector(integerValue)]) {
        NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration
                configurationWithScale: (NSImageSymbolScale) [scale integerValue]];
        image = [self imageWithSymbolConfiguration: configuration];
    }
    [image drawInRect: rect
            fromRect: source
           operation: operation
            fraction: fraction];
}

- (NSString *) description {
    NSSize size = [self size];

    return [NSString
            stringWithFormat:
                    @"<%@[%p] name: %@ size: { %f, %f } representations: %@>",
                    [self class], self, _name, size.width, size.height,
                    NS_EXTRA(NSImage, self)->_representations];
}

- (NSString *) accessibilityDescription {
    return NS_EXTRA(NSImage, self)->_accessibilityDescription;
}

- (void) setAccessibilityDescription: (NSString *) description {
    description = [description copy];
    [NS_EXTRA(NSImage, self)->_accessibilityDescription release];
    NS_EXTRA(NSImage, self)->_accessibilityDescription = description;
}

// Darling does not ship SF Symbols artwork (it is Apple's proprietary asset
// catalog), so every system symbol is drawn as the same generic template glyph:
// a rounded square outline sized like a symbol at the configured point size.
// Apple returns nil for names it doesn't know; here only nil or empty names do,
// because there is no symbol list to check against and apps usually expect an
// image for the names they ship with.
+ (NSImage *) _symbolPlaceholderWithDescription: (NSString *) description
                                  configuration:
                                          (NSImageSymbolConfiguration *)
                                                  configuration
{
    static BOOL logged = NO;
    if (!logged) {
        logged = YES;
        NSLog(@"NSImage: SF Symbols are not available, system symbol images "
              @"are drawn as placeholders");
    }

    if (configuration == nil)
        configuration = [NSImageSymbolConfiguration
                configurationWithScale: NSImageSymbolScaleMedium];

    CGFloat side = [configuration _placeholderSide];
    NSSize size = NSMakeSize(side, side);
    NSCustomImageRep *rep = [[NSCustomImageRep alloc]
            initWithDrawSelector: @selector(_drawSymbolPlaceholder:)
                        delegate: [NSImageSymbolConfiguration class]];
    [rep setSize: size];

    NSImage *image = [[[self alloc] initWithSize: size] autorelease];
    [image addRepresentation: rep];
    [rep release];
    [image setTemplate: YES];
    [image setAccessibilityDescription: description];
    NS_EXTRA(NSImage, image)->_symbolConfiguration = [configuration retain];
    return image;
}

+ (instancetype) imageWithSystemSymbolName: (NSString *) name
                  accessibilityDescription: (NSString *) description
{
    if ([name length] == 0)
        return nil;
    return [self _symbolPlaceholderWithDescription: description
                                     configuration: nil];
}

+ (instancetype) imageWithSystemSymbolName: (NSString *) name
                             variableValue: (double) value
                  accessibilityDescription: (NSString *) description
{
    return [self imageWithSystemSymbolName: name
                  accessibilityDescription: description];
}

+ (instancetype) _imageWithSystemSymbolName: (NSString *) name {
    return [self imageWithSystemSymbolName: name accessibilityDescription: nil];
}

- (NSImage *) imageWithSymbolConfiguration:
        (NSImageSymbolConfiguration *) configuration
{
    if (NS_EXTRA(NSImage, self)->_symbolConfiguration == nil)
        return [[self copy] autorelease];

    NSImageSymbolConfiguration *merged = [NS_EXTRA(NSImage, self)->_symbolConfiguration
            configurationByApplyingConfiguration: configuration];
    return [[self class]
            _symbolPlaceholderWithDescription: NS_EXTRA(NSImage, self)->_accessibilityDescription
                                configuration: merged];
}

- (NSImageSymbolConfiguration *) symbolConfiguration {
    return NS_EXTRA(NSImage, self)->_symbolConfiguration;
}

- (NSEdgeInsets) capInsets {
    return NS_EXTRA(NSImage, self)->_capInsets;
}

- (void) setCapInsets: (NSEdgeInsets) capInsets {
    NS_EXTRA(NSImage, self)->_capInsets = capInsets;
}

- (NSImageResizingMode) resizingMode {
    return NS_EXTRA(NSImage, self)->_resizingMode;
}

- (void) setResizingMode: (NSImageResizingMode) resizingMode {
    NS_EXTRA(NSImage, self)->_resizingMode = resizingMode;
}

@end

@implementation NSImageSymbolConfiguration

- (void) dealloc {
    [_paletteColors release];
    [_hierarchicalColor release];
    [super dealloc];
}

+ (instancetype) configurationWithHierarchicalColor: (NSColor *) color {
    NSImageSymbolConfiguration *result = [[[self alloc] init] autorelease];
    // Like the palette, kept but not drawn: the placeholder has one layer.
    result->_hierarchicalColor = [color retain];
    return result;
}

+ (instancetype) configurationPreferringMulticolor {
    NSImageSymbolConfiguration *result = [[[self alloc] init] autorelease];
    result->_prefersMulticolor = YES;
    return result;
}

+ (instancetype) configurationWithPaletteColors: (NSArray<NSColor *> *) colors {
    NSImageSymbolConfiguration *result = [[[self alloc] init] autorelease];
    // Keep immutable configuration state even when the caller passes a mutable
    // array. The generic template placeholder has no palette layers to color.
    result->_paletteColors = [colors copy];
    return result;
}

+ (instancetype) configurationWithPointSize: (CGFloat) pointSize
                                     weight: (NSFontWeight) weight
                                      scale: (NSImageSymbolScale) scale
{
    NSImageSymbolConfiguration *result = [[[self alloc] init] autorelease];
    result->_pointSize = pointSize;
    result->_weight = weight;
    result->_scale = scale;
    return result;
}

+ (instancetype) configurationWithPointSize: (CGFloat) pointSize
                                     weight: (NSFontWeight) weight
{
    return [self configurationWithPointSize: pointSize
                                     weight: weight
                                      scale: 0];
}

+ (instancetype) configurationWithScale: (NSImageSymbolScale) scale {
    return [self configurationWithPointSize: 0 weight: 0 scale: scale];
}

- (NSImageSymbolConfiguration *) configurationByApplyingConfiguration:
        (NSImageSymbolConfiguration *) configuration
{
    // A copy is the receiver itself, so the result is a new object:
    // configurations are immutable.
    NSImageSymbolConfiguration *result =
            [[[[self class] alloc] init] autorelease];
    NSArray<NSColor *> *paletteColors = _paletteColors;
    NSColor *hierarchicalColor = _hierarchicalColor;

    result->_pointSize = _pointSize;
    result->_weight = _weight;
    result->_scale = _scale;
    result->_prefersMulticolor = _prefersMulticolor;

    if (configuration != nil) {
        if (configuration->_pointSize > 0) {
            result->_pointSize = configuration->_pointSize;
            result->_weight = configuration->_weight;
        }
        if (configuration->_scale != 0)
            result->_scale = configuration->_scale;
        if (configuration->_paletteColors != nil)
            paletteColors = configuration->_paletteColors;
        if (configuration->_hierarchicalColor != nil)
            hierarchicalColor = configuration->_hierarchicalColor;
        if (configuration->_prefersMulticolor)
            result->_prefersMulticolor = YES;
    }

    result->_paletteColors = [paletteColors copy];
    result->_hierarchicalColor = [hierarchicalColor retain];
    return result;
}

- copyWithZone: (NSZone *) zone {
    return [self retain];
}

- (BOOL) isEqual: (id) other {
    if (other == self)
        return YES;
    if (![other isKindOfClass: [NSImageSymbolConfiguration class]])
        return NO;
    NSImageSymbolConfiguration *o = other;
    return o->_pointSize == _pointSize && o->_weight == _weight &&
           o->_scale == _scale &&
           o->_prefersMulticolor == _prefersMulticolor &&
           (o->_paletteColors == _paletteColors ||
            [o->_paletteColors isEqual: _paletteColors]) &&
           (o->_hierarchicalColor == _hierarchicalColor ||
            [o->_hierarchicalColor isEqual: _hierarchicalColor]);
}

- (NSUInteger) hash {
    return (NSUInteger) (_pointSize * 31) ^ (NSUInteger) _scale ^
           [_paletteColors hash];
}

// Side of the square placeholder: the point size (default: the system font
// size) plus a little padding, adjusted for the symbol scale.
- (CGFloat) _placeholderSide {
    CGFloat pointSize = _pointSize > 0 ? _pointSize : 13.0;
    CGFloat factor = 1.0;
    if (_scale == NSImageSymbolScaleSmall)
        factor = 0.8;
    else if (_scale == NSImageSymbolScaleLarge)
        factor = 1.3;
    return ceil(pointSize * factor + 3.0);
}

+ (void) _drawSymbolPlaceholder: (NSCustomImageRep *) rep {
    NSSize size = [rep size];
    CGFloat line = MAX(1.0, floor(size.width / 12.0));
    NSRect box = NSInsetRect(NSMakeRect(0, 0, size.width, size.height),
                             line * 1.5, line * 1.5);
    CGFloat radius = box.size.width / 5.0;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect: box
                                                         xRadius: radius
                                                         yRadius: radius];
    [path setLineWidth: line];
    [[NSColor blackColor] setStroke];
    [path stroke];
}

@end

@implementation NSBundle (NSImage)

- (NSString *) pathForImageResource: (NSString *) name {
    NSString *extension = [name pathExtension];
    if (extension && extension.length) {
        NSString *baseName = [name stringByDeletingPathExtension];
        return [self pathForResource: baseName ofType: extension];
    }
    NSArray *types = [NSImage imageFileTypes];
    int i, count = [types count];

    for (i = 0; i < count; i++) {
        NSString *type = [types objectAtIndex: i];
        NSString *path = [self pathForResource: name ofType: type];

        if (path != nil)
            return path;
    }

    return [self pathForResource: [name stringByDeletingPathExtension]
                          ofType: [name pathExtension]];
}

- (NSImage *) imageForResource: (NSString *) name {
    NSString *path = [self pathForImageResource: name];
    if (path == nil)
        return nil;
    return [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
}

@end

