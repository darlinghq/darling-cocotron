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

#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphics.h>

@class NSImageRep;

typedef enum {
    NSImageCacheDefault,
    NSImageCacheAlways,
    NSImageCacheBySize,
    NSImageCacheNever,
} NSImageCacheMode;

@interface NSImage : NSObject <NSCopying, NSCoding> {
    NSString *_name;
    NSSize _size;
    NSColor *_backgroundColor;
    NSMutableArray *_representations;
    id _delegate;
    BOOL _isFlipped;
    BOOL _isTemplate;
    BOOL _scalesWhenResized;
    BOOL _matchesOnMultipleResolution;
    BOOL _usesEPSOnResolutionMismatch;
    BOOL _prefersColorMatch;
    BOOL _isCachedSeparately;
    BOOL _cacheDepthMatchesImageDepth;
    BOOL _isDataRetained;
    BOOL _cacheIsValid;
    NSImageCacheMode _cacheMode;
}

+ (NSArray *) imageFileTypes;
+ (NSArray *) imageUnfilteredFileTypes;
+ (NSArray *) imagePasteboardTypes;
+ (NSArray *) imageUnfilteredPasteboardTypes;

+ (BOOL) canInitWithPasteboard: (NSPasteboard *) pasteboard;

+ imageNamed: (NSString *) name;

- initWithSize: (NSSize) size;
- initWithData: (NSData *) data;
- initWithContentsOfFile: (NSString *) path;
- initWithContentsOfURL: (NSURL *) url;
- initWithCGImage: (CGImageRef) cgImage size: (NSSize) size;

- initWithPasteboard: (NSPasteboard *) pasteboard;
- initByReferencingFile: (NSString *) path;
- initByReferencingURL: (NSURL *) url;

- (NSString *) name;
- (NSSize) size;
- (NSColor *) backgroundColor;
- (BOOL) isFlipped;
- (BOOL) isTemplate;
- (BOOL) scalesWhenResized;
- (BOOL) matchesOnMultipleResolution;
- (BOOL) usesEPSOnResolutionMismatch;
- (BOOL) prefersColorMatch;
- (NSImageCacheMode) cacheMode;
- (BOOL) isCachedSeparately;
- (BOOL) cacheDepthMatchesImageDepth;
- (BOOL) isDataRetained;
- delegate;

- (BOOL) setName: (NSString *) value;
- (void) setSize: (NSSize) value;
- (void) setBackgroundColor: (NSColor *) value;
- (void) setFlipped: (BOOL) value;
- (void) setTemplate: (BOOL) value;
- (void) setScalesWhenResized: (BOOL) value;
- (void) setMatchesOnMultipleResolution: (BOOL) value;
- (void) setUsesEPSOnResolutionMismatch: (BOOL) value;
- (void) setPrefersColorMatch: (BOOL) value;
- (void) setCacheMode: (NSImageCacheMode) value;
- (void) setCachedSeparately: (BOOL) value;
- (void) setCacheDepthMatchesImageDepth: (BOOL) value;
- (void) setDataRetained: (BOOL) value;
- (void) setDelegate: delegate;

- (BOOL) isValid;

- (NSArray *) representations;
- (void) addRepresentation: (NSImageRep *) representation;
- (void) addRepresentations: (NSArray *) array;
- (void) removeRepresentation: (NSImageRep *) representation;
- (NSImageRep *) bestRepresentationForDevice: (NSDictionary *) device;

- (void) recache;
- (void) cancelIncrementalLoad;

- (NSData *) TIFFRepresentation;
- (NSData *) TIFFRepresentationUsingCompression: (NSTIFFCompression) compression
                                         factor: (float) factor;

- (void) lockFocus;
- (void) lockFocusOnRepresentation: (NSImageRep *) representation;
- (void) unlockFocus;

- (BOOL) drawRepresentation: (NSImageRep *) representation
                     inRect: (NSRect) rect;

- (void) compositeToPoint: (NSPoint) point
                 fromRect: (NSRect) rect
                operation: (NSCompositingOperation) operation;
- (void) compositeToPoint: (NSPoint) point
                 fromRect: (NSRect) rect
                operation: (NSCompositingOperation) operation
                 fraction: (CGFloat) fraction;

- (void) compositeToPoint: (NSPoint) point
                operation: (NSCompositingOperation) operation;
- (void) compositeToPoint: (NSPoint) point
                operation: (NSCompositingOperation) operation
                 fraction: (CGFloat) fraction;

- (void) dissolveToPoint: (NSPoint) point fraction: (CGFloat) fraction;
- (void) dissolveToPoint: (NSPoint) point
                fromRect: (NSRect) rect
                fraction: (CGFloat) fraction;

- (void) drawAtPoint: (NSPoint) point
            fromRect: (NSRect) source
           operation: (NSCompositingOperation) operation
            fraction: (CGFloat) fraction;
- (void) drawInRect: (NSRect) rect
           fromRect: (NSRect) source
          operation: (NSCompositingOperation) operation
           fraction: (CGFloat) fraction;
- (void) drawInRect: (NSRect) rect
              fromRect: (NSRect) source
             operation: (NSCompositingOperation) operation
              fraction: (CGFloat) fraction
        respectFlipped: (BOOL) respectFlipped
                 hints: (NSDictionary<NSString *, id> *) hints;

@end

@interface NSBundle (NSImage)
- (NSString *) pathForImageResource: (NSString *) name;
@end

@protocol NSImageDelegate <NSObject>

// TODO

@end

typedef NSString *NSImageName;
typedef NSString *NSImageHintKey;

APPKIT_EXPORT NSImageName const NSImageNameActionTemplate;
APPKIT_EXPORT NSImageName const NSImageNameAddTemplate;
APPKIT_EXPORT NSImageName const NSImageNameAdvanced;
APPKIT_EXPORT NSImageName const NSImageNameApplicationIcon;
APPKIT_EXPORT NSImageName const NSImageNameBluetoothTemplate;
APPKIT_EXPORT NSImageName const NSImageNameBonjour;
APPKIT_EXPORT NSImageName const NSImageNameBookmarksTemplate;
APPKIT_EXPORT NSImageName const NSImageNameCaution;
APPKIT_EXPORT NSImageName const NSImageNameColorPanel;
APPKIT_EXPORT NSImageName const NSImageNameColumnViewTemplate;
APPKIT_EXPORT NSImageName const NSImageNameComputer;
APPKIT_EXPORT NSImageName const NSImageNameDotMac;
APPKIT_EXPORT NSImageName const NSImageNameEnterFullScreenTemplate;
APPKIT_EXPORT NSImageName const NSImageNameEveryone;
APPKIT_EXPORT NSImageName const NSImageNameExitFullScreenTemplate;
APPKIT_EXPORT NSImageName const NSImageNameFlowViewTemplate;
APPKIT_EXPORT NSImageName const NSImageNameFolder;
APPKIT_EXPORT NSImageName const NSImageNameFolderBurnable;
APPKIT_EXPORT NSImageName const NSImageNameFolderSmart;
APPKIT_EXPORT NSImageName const NSImageNameFollowLinkFreestandingTemplate;
APPKIT_EXPORT NSImageName const NSImageNameFontPanel;
APPKIT_EXPORT NSImageName const NSImageNameGoLeftTemplate;
APPKIT_EXPORT NSImageName const NSImageNameGoRightTemplate;
APPKIT_EXPORT NSImageName const NSImageNameHomeTemplate;
APPKIT_EXPORT NSImageName const NSImageNameIChatTheaterTemplate;
APPKIT_EXPORT NSImageName const NSImageNameIconViewTemplate;
APPKIT_EXPORT NSImageName const NSImageNameInfo;
APPKIT_EXPORT NSImageName const NSImageNameInvalidDataFreestandingTemplate;
APPKIT_EXPORT NSImageName const NSImageNameLeftFacingTriangleTemplate;
APPKIT_EXPORT NSImageName const NSImageNameListViewTemplate;
APPKIT_EXPORT NSImageName const NSImageNameLockLockedTemplate;
APPKIT_EXPORT NSImageName const NSImageNameLockUnlockedTemplate;
APPKIT_EXPORT NSImageName const NSImageNameMenuMixedStateTemplate;
APPKIT_EXPORT NSImageName const NSImageNameMenuOnStateTemplate;
APPKIT_EXPORT NSImageName const NSImageNameMobileMe;
APPKIT_EXPORT NSImageName const NSImageNameMultipleDocuments;
APPKIT_EXPORT NSImageName const NSImageNameNetwork;
APPKIT_EXPORT NSImageName const NSImageNamePathTemplate;
APPKIT_EXPORT NSImageName const NSImageNamePreferencesGeneral;
APPKIT_EXPORT NSImageName const NSImageNameQuickLookTemplate;
APPKIT_EXPORT NSImageName const NSImageNameRefreshFreestandingTemplate;
APPKIT_EXPORT NSImageName const NSImageNameRefreshTemplate;
APPKIT_EXPORT NSImageName const NSImageNameRemoveTemplate;
APPKIT_EXPORT NSImageName const NSImageNameRevealFreestandingTemplate;
APPKIT_EXPORT NSImageName const NSImageNameRightFacingTriangleTemplate;
APPKIT_EXPORT NSImageName const NSImageNameShareTemplate;
APPKIT_EXPORT NSImageName const NSImageNameSlideshowTemplate;
APPKIT_EXPORT NSImageName const NSImageNameSmartBadgeTemplate;
APPKIT_EXPORT NSImageName const NSImageNameStatusAvailable;
APPKIT_EXPORT NSImageName const NSImageNameStatusNone;
APPKIT_EXPORT NSImageName const NSImageNameStatusPartiallyAvailable;
APPKIT_EXPORT NSImageName const NSImageNameStatusUnavailable;
APPKIT_EXPORT NSImageName const NSImageNameStopProgressFreestandingTemplate;
APPKIT_EXPORT NSImageName const NSImageNameStopProgressTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTrashEmpty;
APPKIT_EXPORT NSImageName const NSImageNameTrashFull;
APPKIT_EXPORT NSImageName const NSImageNameUser;
APPKIT_EXPORT NSImageName const NSImageNameUserAccounts;
APPKIT_EXPORT NSImageName const NSImageNameUserGroup;
APPKIT_EXPORT NSImageName const NSImageNameUserGuest;

APPKIT_EXPORT NSImageName const NSImageNameGoBackTemplate;
APPKIT_EXPORT NSImageName const NSImageNameGoForwardTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarDeleteTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarPauseTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarPlayTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarRecordStopTemplate;

APPKIT_EXPORT NSImageHintKey const NSImageHintInterpolation;
APPKIT_EXPORT NSImageHintKey const NSImageHintCTM;
