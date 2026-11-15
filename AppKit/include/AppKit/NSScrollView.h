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
#import <AppKit/AppKitExport.h>
#import <AppKit/NSView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSScroller.h>
#import <Foundation/NSString.h>

@class NSClipView, NSScroller, NSColor, NSRulerView;

APPKIT_EXPORT NSString *const NSScrollViewDidEndLiveScrollNotification;
APPKIT_EXPORT NSString *const NSScrollViewWillStartLiveScrollNotification;
APPKIT_EXPORT NSString *const NSScrollViewDidLiveScrollNotification;

typedef NS_ENUM(NSInteger, NSScrollElasticity) {
    NSScrollElasticityAutomatic = 0,
    NSScrollElasticityNone = 1,
    NSScrollElasticityAllowed = 2,
};

typedef NS_ENUM(NSInteger, NSScrollViewFindBarPosition) {
    NSScrollViewFindBarPositionAboveHorizontalRuler = 0,
    NSScrollViewFindBarPositionAboveContent = 1,
    NSScrollViewFindBarPositionBelowContent = 2,
};

// Legacy ObjC ABI (i386): instance size must stay 0x78, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSScrollView : NSView {
    NSScroller *_verticalScroller;
    NSScroller *_horizontalScroller;
    NSClipView *_clipView;
    NSClipView *_headerClipView;
    NSView *_cornerView;
    NS_LEGACY_IVAR_PAD(_NSScrollViewReserved1, 16)
    NS_EXTRA_IVARS_BEGIN(NSScrollView)
        NSRulerView *_horizontalRuler;
        NSRulerView *_verticalRuler;
        NSColor *_backgroundColor;
        CGFloat _verticalLineScroll;
        CGFloat _verticalPageScroll;
        CGFloat _horizontalLineScroll;
        CGFloat _horizontalPageScroll;
        int _borderType;
        BOOL _drawsBackground;
        BOOL _hasVerticalScroller;
        BOOL _hasHorizontalScroller;
        BOOL _hasHorizontalRuler;
        BOOL _hasVerticalRuler;
        BOOL _rulersVisible;
        BOOL _scrollsDynamically;
        BOOL _autohidesScrollers;
        NSCursor *_documentCursor;
        BOOL _allowsMagnification;
        CGFloat _magnification;
        CGFloat _minMagnification;
        CGFloat _maxMagnification;
        NSScrollerKnobStyle _scrollerKnobStyle;
        NSScrollElasticity _horizontalScrollElasticity;
        NSScrollElasticity _verticalScrollElasticity;
        NSScrollerStyle _scrollerStyle;
    NS_EXTRA_IVARS_END(NSScrollView)
}

@property NSScrollerKnobStyle scrollerKnobStyle;
@property NSScrollerStyle scrollerStyle;
@property NSScrollElasticity horizontalScrollElasticity;
@property NSScrollElasticity verticalScrollElasticity;
@property BOOL automaticallyAdjustsContentInsets;
@property NSEdgeInsets contentInsets;

+ (NSSize) frameSizeForContentSize: (NSSize) contentSize
             hasHorizontalScroller: (BOOL) hasHorizontalScroller
               hasVerticalScroller: (BOOL) hasVerticalScroller
                        borderType: (NSBorderType) borderType;
+ (NSSize)frameSizeForContentSize: (NSSize)cSize 
          horizontalScrollerClass: (Class)horizontalScrollerClass 
            verticalScrollerClass: (Class)verticalScrollerClass 
                       borderType: (NSBorderType)type 
                      controlSize: (NSControlSize)controlSize 
                    scrollerStyle: (NSScrollerStyle)scrollerStyle;
+ (NSSize) contentSizeForFrameSize: (NSSize) fSize
             hasHorizontalScroller: (BOOL) hasHorizontalScroller
               hasVerticalScroller: (BOOL) hasVerticalScroller
                        borderType: (NSBorderType) borderType;
+ (NSSize)contentSizeForFrameSize: (NSSize)fSize 
          horizontalScrollerClass: (Class)horizontalScrollerClass 
            verticalScrollerClass: (Class)verticalScrollerClass 
                       borderType: (NSBorderType)type 
                      controlSize: (NSControlSize)controlSize 
                    scrollerStyle: (NSScrollerStyle)scrollerStyle;

+ (void) setRulerViewClass: (Class) aClass;
+ (Class) rulerViewClass;

- (NSSize) contentSize;

- documentView;
@property(nonatomic, retain) NSClipView *contentView;
- (NSRect) documentVisibleRect;

@property(nonatomic) BOOL drawsBackground;
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic) NSBorderType borderType;
@property(nonatomic, retain) NSScroller *verticalScroller;
@property(nonatomic, retain) NSScroller *horizontalScroller;
@property(nonatomic, retain) NSRulerView *verticalRulerView;
@property(nonatomic, retain) NSRulerView *horizontalRulerView;
@property(nonatomic) BOOL hasVerticalScroller;
@property(nonatomic) BOOL hasHorizontalScroller;
@property(nonatomic) BOOL hasVerticalRuler;
@property(nonatomic) BOOL hasHorizontalRuler;
@property(nonatomic) BOOL rulersVisible;
@property(nonatomic) CGFloat verticalLineScroll;
@property(nonatomic) CGFloat horizontalLineScroll;
@property(nonatomic) CGFloat verticalPageScroll;
@property(nonatomic) CGFloat horizontalPageScroll;
@property(nonatomic) CGFloat lineScroll;
@property(nonatomic) CGFloat pageScroll;
@property(nonatomic) BOOL scrollsDynamically;
@property(nonatomic) BOOL autohidesScrollers;

- (NSScrollElasticity) horizontalScrollElasticity;
- (NSScrollElasticity) verticalScrollElasticity;
- (void) setHorizontalScrollElasticity: (NSScrollElasticity) elasticity;
- (void) setVerticalScrollElasticity: (NSScrollElasticity) elasticity;

@property(nonatomic, retain) NSCursor *documentCursor;
@property(nonatomic) CGFloat magnification;
@property(nonatomic) CGFloat minMagnification;
@property(nonatomic) CGFloat maxMagnification;
@property(nonatomic) BOOL allowsMagnification;

- (void) setDocumentView: (NSView *) view;
- (NSScrollerKnobStyle) scrollerKnobStyle;
- (void) setScrollerKnobStyle: (NSScrollerKnobStyle) knobStyle;
- (NSScrollerStyle) scrollerStyle;
- (void) setScrollerStyle: (NSScrollerStyle) scrollerStyle;

- (void) tile;
- (void) reflectScrolledClipView: (NSClipView *) clipView;

@end

APPKIT_EXPORT NSNotificationName const NSScrollViewWillStartLiveMagnifyNotification;
APPKIT_EXPORT NSNotificationName const NSScrollViewDidEndLiveMagnifyNotification;
