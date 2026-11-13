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
        @"NSImageNameTouchBarAddDetailTemplate";
NSImageName const NSImageNameTouchBarAddTemplate =
        @"NSImageNameTouchBarAddTemplate";
NSImageName const NSImageNameTouchBarAlarmTemplate =
        @"NSImageNameTouchBarAlarmTemplate";
NSImageName const NSImageNameTouchBarAudioInputMuteTemplate =
        @"NSImageNameTouchBarAudioInputMuteTemplate";
NSImageName const NSImageNameTouchBarAudioInputTemplate =
        @"NSImageNameTouchBarAudioInputTemplate";
NSImageName const NSImageNameTouchBarAudioOutputMuteTemplate =
        @"NSImageNameTouchBarAudioOutputMuteTemplate";
NSImageName const NSImageNameTouchBarAudioOutputVolumeHighTemplate =
        @"NSImageNameTouchBarAudioOutputVolumeHighTemplate";
NSImageName const NSImageNameTouchBarAudioOutputVolumeLowTemplate =
        @"NSImageNameTouchBarAudioOutputVolumeLowTemplate";
NSImageName const NSImageNameTouchBarAudioOutputVolumeMediumTemplate =
        @"NSImageNameTouchBarAudioOutputVolumeMediumTemplate";
NSImageName const NSImageNameTouchBarAudioOutputVolumeOffTemplate =
        @"NSImageNameTouchBarAudioOutputVolumeOffTemplate";
NSImageName const NSImageNameTouchBarBookmarksTemplate =
        @"NSImageNameTouchBarBookmarksTemplate";
NSImageName const NSImageNameTouchBarColorPickerFill =
        @"NSImageNameTouchBarColorPickerFill";
NSImageName const NSImageNameTouchBarColorPickerFont =
        @"NSImageNameTouchBarColorPickerFont";
NSImageName const NSImageNameTouchBarColorPickerStroke =
        @"NSImageNameTouchBarColorPickerStroke";
NSImageName const NSImageNameTouchBarCommunicationAudioTemplate =
        @"NSImageNameTouchBarCommunicationAudioTemplate";
NSImageName const NSImageNameTouchBarCommunicationVideoTemplate =
        @"NSImageNameTouchBarCommunicationVideoTemplate";
NSImageName const NSImageNameTouchBarComposeTemplate =
        @"NSImageNameTouchBarComposeTemplate";
NSImageName const NSImageNameTouchBarDownloadTemplate =
        @"NSImageNameTouchBarDownloadTemplate";
NSImageName const NSImageNameTouchBarEnterFullScreenTemplate =
        @"NSImageNameTouchBarEnterFullScreenTemplate";
NSImageName const NSImageNameTouchBarExitFullScreenTemplate =
        @"NSImageNameTouchBarExitFullScreenTemplate";
NSImageName const NSImageNameTouchBarFastForwardTemplate =
        @"NSImageNameTouchBarFastForwardTemplate";
NSImageName const NSImageNameTouchBarFolderCopyToTemplate =
        @"NSImageNameTouchBarFolderCopyToTemplate";
NSImageName const NSImageNameTouchBarFolderMoveToTemplate =
        @"NSImageNameTouchBarFolderMoveToTemplate";
NSImageName const NSImageNameTouchBarFolderTemplate =
        @"NSImageNameTouchBarFolderTemplate";
NSImageName const NSImageNameTouchBarGetInfoTemplate =
        @"NSImageNameTouchBarGetInfoTemplate";
NSImageName const NSImageNameTouchBarGoBackTemplate =
        @"NSImageNameTouchBarGoBackTemplate";
NSImageName const NSImageNameTouchBarGoDownTemplate =
        @"NSImageNameTouchBarGoDownTemplate";
NSImageName const NSImageNameTouchBarGoForwardTemplate =
        @"NSImageNameTouchBarGoForwardTemplate";
NSImageName const NSImageNameTouchBarGoUpTemplate =
        @"NSImageNameTouchBarGoUpTemplate";
NSImageName const NSImageNameTouchBarHistoryTemplate =
        @"NSImageNameTouchBarHistoryTemplate";
NSImageName const NSImageNameTouchBarIconViewTemplate =
        @"NSImageNameTouchBarIconViewTemplate";
NSImageName const NSImageNameTouchBarListViewTemplate =
        @"NSImageNameTouchBarListViewTemplate";
NSImageName const NSImageNameTouchBarMailTemplate =
        @"NSImageNameTouchBarMailTemplate";
NSImageName const NSImageNameTouchBarNewFolderTemplate =
        @"NSImageNameTouchBarNewFolderTemplate";
NSImageName const NSImageNameTouchBarNewMessageTemplate =
        @"NSImageNameTouchBarNewMessageTemplate";
NSImageName const NSImageNameTouchBarOpenInBrowserTemplate =
        @"NSImageNameTouchBarOpenInBrowserTemplate";
NSImageName const NSImageNameTouchBarPlayheadTemplate =
        @"NSImageNameTouchBarPlayheadTemplate";
NSImageName const NSImageNameTouchBarPlayPauseTemplate =
        @"NSImageNameTouchBarPlayPauseTemplate";
NSImageName const NSImageNameTouchBarQuickLookTemplate =
        @"NSImageNameTouchBarQuickLookTemplate";
NSImageName const NSImageNameTouchBarRecordStartTemplate =
        @"NSImageNameTouchBarRecordStartTemplate";
NSImageName const NSImageNameTouchBarRefreshTemplate =
        @"NSImageNameTouchBarRefreshTemplate";
NSImageName const NSImageNameTouchBarRemoveTemplate =
        @"NSImageNameTouchBarRemoveTemplate";
NSImageName const NSImageNameTouchBarRewindTemplate =
        @"NSImageNameTouchBarRewindTemplate";
NSImageName const NSImageNameTouchBarRotateLeftTemplate =
        @"NSImageNameTouchBarRotateLeftTemplate";
NSImageName const NSImageNameTouchBarRotateRightTemplate =
        @"NSImageNameTouchBarRotateRightTemplate";
NSImageName const NSImageNameTouchBarSearchTemplate =
        @"NSImageNameTouchBarSearchTemplate";
NSImageName const NSImageNameTouchBarShareTemplate =
        @"NSImageNameTouchBarShareTemplate";
NSImageName const NSImageNameTouchBarSidebarTemplate =
        @"NSImageNameTouchBarSidebarTemplate";
NSImageName const NSImageNameTouchBarSkipAhead15SecondsTemplate =
        @"NSImageNameTouchBarSkipAhead15SecondsTemplate";
NSImageName const NSImageNameTouchBarSkipAhead30SecondsTemplate =
        @"NSImageNameTouchBarSkipAhead30SecondsTemplate";
NSImageName const NSImageNameTouchBarSkipAheadTemplate =
        @"NSImageNameTouchBarSkipAheadTemplate";
NSImageName const NSImageNameTouchBarSkipBack15SecondsTemplate =
        @"NSImageNameTouchBarSkipBack15SecondsTemplate";
NSImageName const NSImageNameTouchBarSkipBack30SecondsTemplate =
        @"NSImageNameTouchBarSkipBack30SecondsTemplate";
NSImageName const NSImageNameTouchBarSkipBackTemplate =
        @"NSImageNameTouchBarSkipBackTemplate";
NSImageName const NSImageNameTouchBarSkipToEndTemplate =
        @"NSImageNameTouchBarSkipToEndTemplate";
NSImageName const NSImageNameTouchBarSkipToStartTemplate =
        @"NSImageNameTouchBarSkipToStartTemplate";
NSImageName const NSImageNameTouchBarSlideshowTemplate =
        @"NSImageNameTouchBarSlideshowTemplate";
NSImageName const NSImageNameTouchBarTagIconTemplate =
        @"NSImageNameTouchBarTagIconTemplate";
NSImageName const NSImageNameTouchBarTextBoldTemplate =
        @"NSImageNameTouchBarTextBoldTemplate";
NSImageName const NSImageNameTouchBarTextBoxTemplate =
        @"NSImageNameTouchBarTextBoxTemplate";
NSImageName const NSImageNameTouchBarTextCenterAlignTemplate =
        @"NSImageNameTouchBarTextCenterAlignTemplate";
NSImageName const NSImageNameTouchBarTextItalicTemplate =
        @"NSImageNameTouchBarTextItalicTemplate";
NSImageName const NSImageNameTouchBarTextJustifiedAlignTemplate =
        @"NSImageNameTouchBarTextJustifiedAlignTemplate";
NSImageName const NSImageNameTouchBarTextLeftAlignTemplate =
        @"NSImageNameTouchBarTextLeftAlignTemplate";
NSImageName const NSImageNameTouchBarTextListTemplate =
        @"NSImageNameTouchBarTextListTemplate";
NSImageName const NSImageNameTouchBarTextRightAlignTemplate =
        @"NSImageNameTouchBarTextRightAlignTemplate";
NSImageName const NSImageNameTouchBarTextStrikethroughTemplate =
        @"NSImageNameTouchBarTextStrikethroughTemplate";
NSImageName const NSImageNameTouchBarTextUnderlineTemplate =
        @"NSImageNameTouchBarTextUnderlineTemplate";
NSImageName const NSImageNameTouchBarUserAddTemplate =
        @"NSImageNameTouchBarUserAddTemplate";
NSImageName const NSImageNameTouchBarUserGroupTemplate =
        @"NSImageNameTouchBarUserGroupTemplate";
NSImageName const NSImageNameTouchBarUserTemplate =
        @"NSImageNameTouchBarUserTemplate";
NSImageName const NSImageNameTouchBarVolumeDownTemplate =
        @"NSImageNameTouchBarVolumeDownTemplate";
NSImageName const NSImageNameTouchBarVolumeUpTemplate =
        @"NSImageNameTouchBarVolumeUpTemplate";

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

@implementation NSImage

+ (NSArray *) imageFileTypes {
    return [self imageUnfilteredFileTypes];
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
        _representations = [NSMutableArray new];

        [_representations addObject: rep];
    } else {
        NSInteger version = [coder versionForClassName: @"NSImage"];

        _representations = [NSMutableArray new];

        if (version >= 17) {
            // Layouts as recorded from Mac archives: the name, a byte per flag (12 bytes up to
            // version 44, 13 at 45, 14 at 46, 15 at 47 and 14 from 48 on), an explicit size when
            // flag byte 2 is set, a short, then for each of that many representations a byte and
            // the representation, then the background colour and the delegate.
            _name = [[coder decodeObject] retain];

            int count = version <= 44 ? 12 : version == 45 ? 13 : version == 46 ? 14 : version == 47 ? 15 : 14;
            char flags[16] = { 0 };
            // Only the first four bytes are read when the fourth selects the shorter layout.
            for (int i = 0; i < 4; i++) {
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
            _scalesWhenResized = flags[4] != 0;
            _isDataRetained = flags[5] != 0;
            _isCachedSeparately = flags[6] != 0;
            _usesEPSOnResolutionMismatch = flags[7] != 0;
            _prefersColorMatch = flags[8] != 0;
            _matchesOnMultipleResolution = flags[9] != 0;
            _isFlipped = count > 12 && flags[12] != 0;

            short repCount;
            [coder decodeValueOfObjCType: @encode(short) at: &repCount];
            for (int i = 0; i < repCount; i++) {
                char unknownByte;
                [coder decodeValueOfObjCType: @encode(char) at: &unknownByte];
                id rep = [coder decodeObject];
                if ([rep isKindOfClass: [NSImageRep class]]) {
                    [_representations addObject: rep];
                }
            }

            _backgroundColor = [[coder decodeObject] retain];
            _delegate = [coder decodeObject];
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
                    [_representations addObject: rep];
                }
            } else if (version >= 3) {
                id first = [coder decodeObject];
                id second = [coder decodeObject];
                if ([first isKindOfClass: [NSImageRep class]]) {
                    [_representations addObject: first];
                }
                if ([second isKindOfClass: [NSImageRep class]]) {
                    [_representations addObject: second];
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
    _representations = [NSMutableArray new];
    return self;
}

- init {
    return [self initWithSize: NSMakeSize(0, 0)];
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
    _representations = [NSMutableArray new];

    [_representations addObjectsFromArray: reps];

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
    _representations = [NSMutableArray new];

    [_representations addObjectsFromArray: reps];

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
        [_representations addObject: rep];
    }
    return self;
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

- initByReferencingFile: (NSString *) path {
    return [self initWithContentsOfFile: path];
}

- initByReferencingURL: (NSURL *) url {
    // Better than nothing
    return [self initWithContentsOfURL: url];
}

- (void) dealloc {
    [_name release];
    [_backgroundColor release];
    [_representations release];
    [_accessibilityDescription release];
    [_symbolConfiguration release];
    [_scaledRepCache release];
    [_drawingHandlerRepCache release];
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSImage *result = NSCopyObject(self, 0, zone);

    result->_name = [_name copy];
    result->_backgroundColor = [_backgroundColor copy];
    result->_representations = [_representations mutableCopy];
    result->_accessibilityDescription = [_accessibilityDescription copy];
    result->_symbolConfiguration = [_symbolConfiguration retain];
    result->_scaledRepCache = nil;
    result->_drawingHandlerRepCache = nil;

    return result;
}

- (NSString *) name {
    return _name;
}

- (NSSize) size {
    if (_size.width == 0.0 && _size.height == 0.0) {
        int i, count = [_representations count];
        NSSize largestSize = NSMakeSize(0, 0);

        for (i = 0; i < count; i++) {
            NSImageRep *check = [_representations objectAtIndex: i];
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
    if (_hasCustomAlignmentRect)
        return _alignmentRect;

    NSSize size = [self size];
    return NSMakeRect(0, 0, size.width, size.height);
}

- (void) setAlignmentRect: (NSRect) rect {
    _alignmentRect = rect;
    _hasCustomAlignmentRect = YES;
}

- (NSColor *) backgroundColor {
    return _backgroundColor;
}

- (BOOL) isFlipped {
    return _isFlipped;
}

- (BOOL) isTemplate {
    return _isTemplate;
}

- (BOOL) scalesWhenResized {
    return _scalesWhenResized;
}

- (BOOL) matchesOnMultipleResolution {
    return _matchesOnMultipleResolution;
}

- (BOOL) usesEPSOnResolutionMismatch {
    return _usesEPSOnResolutionMismatch;
}

- (BOOL) prefersColorMatch {
    return _prefersColorMatch;
}

- (NSImageCacheMode) cacheMode {
    return _cacheMode;
}

- (BOOL) isCachedSeparately {
    return _isCachedSeparately;
}

- (BOOL) cacheDepthMatchesImageDepth {
    return _cacheDepthMatchesImageDepth;
}

- (BOOL) isDataRetained {
    return _isDataRetained;
}

- delegate {
    return _delegate;
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
    [_drawingHandlerRepCache removeAllObjects];
    value = [value copy];
    [_backgroundColor release];
    _backgroundColor = value;
}

- (void) setFlipped: (BOOL) value {
    [_drawingHandlerRepCache removeAllObjects];
    _isFlipped = value;
}

- (void) setTemplate: (BOOL) value {
    _isTemplate = value;
}

- (void) setScalesWhenResized: (BOOL) value {
    _scalesWhenResized = value;
}

- (void) setMatchesOnMultipleResolution: (BOOL) value {
    _matchesOnMultipleResolution = value;
}

- (void) setUsesEPSOnResolutionMismatch: (BOOL) value {
    _usesEPSOnResolutionMismatch = value;
}

- (void) setPrefersColorMatch: (BOOL) value {
    _prefersColorMatch = value;
}

- (void) setCacheMode: (NSImageCacheMode) value {
    [_drawingHandlerRepCache removeAllObjects];
    _cacheMode = value;
}

- (void) setCachedSeparately: (BOOL) value {
    _isCachedSeparately = value;
}

- (void) setCacheDepthMatchesImageDepth: (BOOL) value {
    _cacheDepthMatchesImageDepth = value;
}

- (void) setDataRetained: (BOOL) value {
    _isDataRetained = value;
}

- (void) setDelegate: delegate {
    _delegate = delegate;
}

- (BOOL) isValid {
    NSUnimplementedMethod();
    return 0;
}

- (NSArray *) representations {
    return _representations;
}

- (void) addRepresentation: (NSImageRep *) representation {
    if (representation != nil) {
        [_representations addObject: representation];
        [_drawingHandlerRepCache removeAllObjects];
        [_scaledRepCache removeAllObjects];
    }
}

- (void) addRepresentations: (NSArray *) array {
    int i, count = [array count];

    for (i = 0; i < count; i++)
        [self addRepresentation: [array objectAtIndex: i]];
}

- (void) removeRepresentation: (NSImageRep *) representation {
    [_drawingHandlerRepCache removeAllObjects];
    [_representations removeObjectIdenticalTo: representation];
    [_scaledRepCache removeAllObjects];
}

- (NSCachedImageRep *) _cachedImageRepCreateIfNeeded {
    int count = [_representations count];

    while (--count >= 0) {
        NSCachedImageRep *check = [_representations objectAtIndex: count];

        if ([check isKindOfClass: [NSCachedImageRep class]]) {

            if (_cacheIsValid)
                return check;

            [_representations removeObjectAtIndex: count];
        }
    }

    NSCachedImageRep *cached =
            [[NSCachedImageRep alloc] initWithSize: [self size]
                                             depth: 0
                                          separate: _isCachedSeparately
                                             alpha: YES];
    [self addRepresentation: cached];
    [cached release];
    return cached;
}

- (NSImageRep *) _bestUncachedRepresentationForDevice: (NSDictionary *) device {
    int i, count = [_representations count];

    for (i = 0; i < count; i++) {
        NSImageRep *check = [_representations objectAtIndex: i];

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
    int i, count = [_representations count];
    NSImageRep *best = nil;

    size.width = ABS(size.width);
    size.height = ABS(size.height);

    for (i = 0; i < count; i++) {
        NSImageRep *check = [_representations objectAtIndex: i];

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
        NSImageRep *check = [_representations objectAtIndex: i];

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
        int i, count = [_representations count];

        for (i = 0; i < count; i++) {
            NSImageRep *check = [_representations objectAtIndex: i];

            if (![check isKindOfClass: [NSCachedImageRep class]])
                return check;
        }
    }

    if ([device objectForKey: NSDeviceIsScreen] != nil) {
        NSImageRep *uncached =
                [self _bestUncachedRepresentationForDevice: device];
        NSImageCacheMode caching = _cacheMode;

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

        if (!_cacheIsValid) {
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
            _cacheIsValid = rendered;
        }

        return _cacheIsValid ? cached : uncached;
    }

    return [_representations lastObject];
}

- (void) recache {
    [_drawingHandlerRepCache removeAllObjects];
    // This doesn't actually remove the cache, it just marks it as invalid
    // This is important because you can change the size of a drawn image
    // and it doesn't destroy the cache. It is recached next time it is drawn.
    _cacheIsValid = NO;

    // The pre-scaled representations are derived from the reps and from
    // -size, so they do not survive this. -setSize: goes through here too.
    [_scaledRepCache removeAllObjects];
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

    for (NSImageRep *check in _representations) {
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
        _cacheIsValid = YES;
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
    if (_cacheMode == NSImageCacheNever)
        return nil;

    // A print or PDF destination wants the source representation at its own
    // resolution, not one resampled down to the page's device transform.
    if (![[NSGraphicsContext currentContext] isDrawingToScreen])
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

    for (NSArray *entry in _scaledRepCache) {
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
        [_scaledRepCache removeObjectIdenticalTo: hit];
        [_scaledRepCache addObject: hit];
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

    if (_scaledRepCache == nil)
        _scaledRepCache = [[NSMutableArray alloc] init];

    // Evict least recently used entries until the new one fits both bounds.
    while ([_scaledRepCache count] > 0 &&
           ([_scaledRepCache count] >= scaledRepCacheCapacity ||
            scaledRepCacheBytes(_scaledRepCache) + scaledRepBytes(scaled) >
                    scaledRepCacheByteBudget))
        [_scaledRepCache removeObjectAtIndex: 0];

    [_scaledRepCache
            addObject: [NSArray arrayWithObjects: sourceRep, scaled, nil]];
    return scaled;
}

- (NSImageDrawingCache *) _drawingHandlerCache {
    if (_drawingHandlerRepCache == nil)
        _drawingHandlerRepCache = [NSImageDrawingCache new];
    return _drawingHandlerRepCache;
}

- (void) drawInRect: (NSRect) rect
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
        BOOL canCache = drawFullImage && !_isFlipped;

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
                        _cacheMode != NSImageCacheNever &&
                        [NSGraphicsContext currentContext] != nil) {
                        drawingCacheKey = @[
                            uncached, [NSGraphicsContext currentContext],
                            [NSValue valueWithRect: source], [NSValue valueWithRect: rect],
                            [NSValue valueWithSize: [self size]],
                            [NSValue valueWithSize: uncachedSize],
                            @(destination.a), @(destination.b), @(destination.c),
                            @(destination.d), @(destination.tx), @(destination.ty),
                            @(_isFlipped), _backgroundColor ?: (id)[NSNull null],
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
                    if (usesDrawingHandler && _isFlipped) {
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
                    if (_isFlipped) {
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
    if (_symbolConfiguration != nil && [scale respondsToSelector: @selector(integerValue)]) {
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
                    _representations];
}

- (NSString *) accessibilityDescription {
    return _accessibilityDescription;
}

- (void) setAccessibilityDescription: (NSString *) description {
    description = [description copy];
    [_accessibilityDescription release];
    _accessibilityDescription = description;
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
    image->_symbolConfiguration = [configuration retain];
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
    if (_symbolConfiguration == nil)
        return [[self copy] autorelease];

    NSImageSymbolConfiguration *merged = [_symbolConfiguration
            configurationByApplyingConfiguration: configuration];
    return [[self class]
            _symbolPlaceholderWithDescription: _accessibilityDescription
                                configuration: merged];
}

- (NSImageSymbolConfiguration *) symbolConfiguration {
    return _symbolConfiguration;
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
