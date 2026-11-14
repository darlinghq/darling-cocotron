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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSFontDescriptor.h>
#import <AppKit/NSGraphics.h>

@class NSImageRep;
@class NSImageSymbolConfiguration;
@class NSGraphicsContext;

typedef NSString *NSImageHintKey NS_TYPED_ENUM NS_SWIFT_NAME(NSImageRep.HintKey);

typedef NS_ENUM(NSUInteger, NSImageCacheMode) {
    NSImageCacheDefault,
    NSImageCacheAlways,
    NSImageCacheBySize,
    NSImageCacheNever,
};

typedef NS_ENUM(NSInteger, NSImageResizingMode) {
    NSImageResizingModeStretch = 0,
    NSImageResizingModeTile = 1,
};

typedef NS_ENUM(NSUInteger, NSImageLoadStatus) {
    NSImageLoadStatusCompleted,
    NSImageLoadStatusCancelled,
    NSImageLoadStatusInvalidData,
    NSImageLoadStatusUnexpectedEOF,
    NSImageLoadStatusReadError,
};

// Legacy ObjC ABI (i386): instance size must stay 0x1c, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSImage : NSObject <NSCopying, NSCoding> {
    NSString *_name;
    NSSize _size;
    NS_LEGACY_IVAR_PAD(_NSImageReserved1, 8)
    NS_EXTRA_IVARS_BEGIN(NSImage)
        NSRect _alignmentRect;
        BOOL _hasCustomAlignmentRect;
        NSEdgeInsets _capInsets;
        NSImageResizingMode _resizingMode;
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
        NSString *_accessibilityDescription;
        NSImageSymbolConfiguration *_symbolConfiguration;
        NSMutableArray *_scaledRepCache;
        id _drawingHandlerRepCache;
    NS_EXTRA_IVARS_END(NSImage)
}

+ (NSArray *) imageFileTypes;
+ (NSArray *) imageUnfilteredFileTypes;
+ (NSArray *) imageTypes;
+ (NSArray *) imageUnfilteredTypes;
+ (NSArray *) imagePasteboardTypes;
+ (NSArray *) imageUnfilteredPasteboardTypes;

+ (BOOL) canInitWithPasteboard: (NSPasteboard *) pasteboard;

+ (nullable instancetype) imageNamed: (NSString *) name;

- initWithSize: (NSSize) size;
+ (instancetype) imageWithSize: (NSSize) size
                       flipped: (BOOL) flipped
                drawingHandler: (BOOL (^)(NSRect destinationRect)) handler;
- initWithData: (NSData *) data;
- initWithContentsOfFile: (NSString *) path;
- initWithContentsOfURL: (NSURL *) url;
- initWithCGImage: (CGImageRef) cgImage size: (NSSize) size;
- (CGImageRef) CGImageForProposedRect: (NSRect *) proposedDestRect
                              context: (NSGraphicsContext *) context
                                hints: (NSDictionary *) hints;

- initWithPasteboard: (NSPasteboard *) pasteboard;
- initByReferencingFile: (NSString *) path;
- initByReferencingURL: (NSURL *) url;

- (NSString *) name;
@property NSSize size;
@property NSRect alignmentRect;
@property NSEdgeInsets capInsets;
@property NSImageResizingMode resizingMode;
@property(nonatomic, retain) NSColor *backgroundColor;
@property (getter=isFlipped) BOOL flipped;
@property (setter=setTemplate:) BOOL isTemplate;
@property(nonatomic) BOOL scalesWhenResized;
@property(nonatomic) BOOL matchesOnMultipleResolution;
@property(nonatomic) BOOL usesEPSOnResolutionMismatch;
@property(nonatomic) BOOL prefersColorMatch;
@property(nonatomic) NSImageCacheMode cacheMode;
@property(nonatomic, getter=isCachedSeparately) BOOL cachedSeparately;
@property(nonatomic) BOOL cacheDepthMatchesImageDepth;
@property(nonatomic, getter=isDataRetained) BOOL dataRetained;
- delegate;

- (BOOL) setName: (NSString *) value;
- (void) setDelegate: delegate;

@property(nonatomic, getter=isValid, readonly) BOOL valid;

@property(nonatomic, readonly) NSArray *representations;
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
- (void) drawInRect: (NSRect) rect;
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

@property (copy, nullable) NSString *accessibilityDescription;

// SF Symbols. Darling has no symbol artwork: these return a generic template
// placeholder glyph for any non-empty name (nil for a nil or empty name).
+ (instancetype) imageWithSystemSymbolName: (NSString *) name
                  accessibilityDescription: (NSString *) description;
+ (instancetype) imageWithSystemSymbolName: (NSString *) name
                             variableValue: (double) value
                  accessibilityDescription: (NSString *) description;
- (NSImage *) imageWithSymbolConfiguration:
        (NSImageSymbolConfiguration *) configuration;
@property(nonatomic, readonly) NSImageSymbolConfiguration *symbolConfiguration;
// Private AppKit spelling of imageWithSystemSymbolName:accessibilityDescription:.
+ (instancetype) _imageWithSystemSymbolName: (NSString *) name;

@end

typedef NS_ENUM(NSInteger, NSImageSymbolScale) {
    NSImageSymbolScaleSmall = 1,
    NSImageSymbolScaleMedium = 2,
    NSImageSymbolScaleLarge = 3,
};

@interface NSImageSymbolConfiguration : NSObject <NSCopying> {
    CGFloat _pointSize;
    NSFontWeight _weight;
    NSImageSymbolScale _scale;
    NSArray<NSColor *> *_paletteColors;
    NSColor *_hierarchicalColor;
    BOOL _prefersMulticolor;
}

+ (instancetype) configurationWithPointSize: (CGFloat) pointSize
                                     weight: (NSFontWeight) weight;
+ (instancetype) configurationWithPointSize: (CGFloat) pointSize
                                     weight: (NSFontWeight) weight
                                      scale: (NSImageSymbolScale) scale;
+ (instancetype) configurationWithScale: (NSImageSymbolScale) scale;
+ (instancetype) configurationWithPaletteColors: (NSArray<NSColor *> *) colors;
+ (instancetype) configurationWithHierarchicalColor: (NSColor *) color;
+ (instancetype) configurationPreferringMulticolor;
- (NSImageSymbolConfiguration *) configurationByApplyingConfiguration:
        (NSImageSymbolConfiguration *) configuration;

@end

@interface NSBundle (NSImage)
- (NSString *) pathForImageResource: (NSString *) name;
// A new image from pathForImageResource:, or nil.
- (NSImage *) imageForResource: (NSString *) name;
@end

@protocol NSImageDelegate <NSObject>

// TODO

@end

typedef NSString *NSImageName NS_SWIFT_BRIDGED_TYPEDEF;

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
APPKIT_EXPORT NSImageName const NSImageNameTouchBarAddTabTemplate;

APPKIT_EXPORT NSImageHintKey const NSImageHintInterpolation;
APPKIT_EXPORT NSImageHintKey const NSImageHintCTM NS_SWIFT_NAME(ctm);
APPKIT_EXPORT NSImageHintKey const NSImageHintSymbolScale;

APPKIT_EXPORT NSImageName const NSImageNameTouchBarAddDetailTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarAddTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarAlarmTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarAudioInputMuteTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarAudioInputTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarAudioOutputMuteTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarAudioOutputVolumeHighTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarAudioOutputVolumeLowTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarAudioOutputVolumeMediumTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarAudioOutputVolumeOffTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarBookmarksTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarColorPickerFill;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarColorPickerFont;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarColorPickerStroke;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarCommunicationAudioTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarCommunicationVideoTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarComposeTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarDownloadTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarEnterFullScreenTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarExitFullScreenTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarFastForwardTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarFolderCopyToTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarFolderMoveToTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarFolderTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarGetInfoTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarGoBackTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarGoDownTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarGoForwardTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarGoUpTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarHistoryTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarIconViewTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarListViewTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarMailTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarNewFolderTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarNewMessageTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarOpenInBrowserTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarPlayPauseTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarQuickLookTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarRecordStartTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarRefreshTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarRemoveTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarRewindTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarRotateLeftTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarRotateRightTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSearchTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarShareTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSidebarTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSkipAhead15SecondsTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSkipAhead30SecondsTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSkipAheadTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSkipBack15SecondsTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSkipBack30SecondsTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSkipBackTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSkipToEndTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSkipToStartTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarSlideshowTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTagIconTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTextBoldTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTextBoxTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTextCenterAlignTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTextItalicTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTextJustifiedAlignTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTextLeftAlignTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTextListTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTextRightAlignTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTextStrikethroughTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarTextUnderlineTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarUserAddTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarUserGroupTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarUserTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarVolumeDownTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarVolumeUpTemplate;
APPKIT_EXPORT NSImageName const NSImageNameTouchBarPlayheadTemplate;
