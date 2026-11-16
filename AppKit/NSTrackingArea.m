/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
                 2009-2010 Markus Hitter <mah@jump-ing.de>

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

/*
 * This class is also used for ToolTips, legacy TrackingRects and legacy
 * CursorRects. All these do some special assumptions in NSView.m and
 * NSWindow.m and are not for user consumtion.
 *
 * On how to set up these special cases, see NSView.m.
 */

#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSView.h>

@implementation NSTrackingArea

- (id) initWithRect: (NSRect) rect
            options: (NSTrackingAreaOptions) options
              owner: (id) owner
           userInfo: (NSDictionary *) userInfo
{
    return [self _initWithRect: rect
                       options: options
                         owner: owner
                      userData: userInfo
                retainUserData: YES
                     isToolTip: NO
                      isLegacy: NO];
}

- (id) _initWithRect: (NSRect) rect
               options: (NSTrackingAreaOptions) options
                 owner: (id) owner
              userData: (void *) userData
        retainUserData: (BOOL) retainUserData
             isToolTip: (BOOL) isToolTip
              isLegacy: (BOOL) legacy
{
    self = [super init];
    if (self != nil) {
        NS_EXTRA(NSTrackingArea, self)->_rect = rect;
        NS_EXTRA(NSTrackingArea, self)->_options = options;
        NS_EXTRA(NSTrackingArea, self)->_owner = [owner retain];
        NS_EXTRA(NSTrackingArea, self)->_userData = userData;
        NS_EXTRA(NSTrackingArea, self)->_retainUserData = retainUserData;
        if (NS_EXTRA(NSTrackingArea, self)->_retainUserData)
            NS_EXTRA(NSTrackingArea, self)->_userData = [(id) userData retain];

        if (NS_EXTRA(NSTrackingArea, self)->_options & NSTrackingAssumeInside)
            NS_EXTRA(NSTrackingArea, self)->_mouseInside = YES;
        else
            NS_EXTRA(NSTrackingArea, self)->_mouseInside = NO;
        NS_EXTRA(NSTrackingArea, self)->_view = nil;
        NS_EXTRA(NSTrackingArea, self)->_rectInWindow = NSZeroRect;
        NS_EXTRA(NSTrackingArea, self)->_isToolTip = isToolTip;
        NS_EXTRA(NSTrackingArea, self)->_legacy = legacy;
    }
    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSTrackingArea, self)->_owner release];
    if (NS_EXTRA(NSTrackingArea, self)->_retainUserData)
        [(id) NS_EXTRA(NSTrackingArea, self)->_userData release];
    NS_EXTRA_FREE(NSTrackingArea, self);
    [super dealloc];
}

- (NSRect) rect {
    return NS_EXTRA(NSTrackingArea, self)->_rect;
}

- (NSTrackingAreaOptions) options {
    return NS_EXTRA(NSTrackingArea, self)->_options;
}

- (id) owner {
    return NS_EXTRA(NSTrackingArea, self)->_owner;
}

- (NSDictionary *) userInfo {
    return (id) NS_EXTRA(NSTrackingArea, self)->_userData;
}

- (NSRect) _rectInWindow {
    return NS_EXTRA(NSTrackingArea, self)->_rectInWindow;
}

- (void) _setRectInWindow: (NSRect) rectInWindow {
    NS_EXTRA(NSTrackingArea, self)->_rectInWindow = rectInWindow;
}

- (void) _setRect: (NSRect) rect {
    NS_EXTRA(NSTrackingArea, self)->_rect = rect;
}

- (NSView *) _view {
    return NS_EXTRA(NSTrackingArea, self)->_view;
}

- (void) _setView: (NSView *) newView {
    // Don't retain or we could create a retain loop between the view array of
    // tracking areas and this tracking area
    NS_EXTRA(NSTrackingArea, self)->_view = newView;
}

- (BOOL) _isToolTip {
    return NS_EXTRA(NSTrackingArea, self)->_isToolTip;
}

- (BOOL) _isLegacy {
    return NS_EXTRA(NSTrackingArea, self)->_legacy;
}

- (BOOL) _mouseInside {
    return NS_EXTRA(NSTrackingArea, self)->_mouseInside;
}

- (void) _setMouseInside: (BOOL) inside {
    NS_EXTRA(NSTrackingArea, self)->_mouseInside = inside;
}

- (NSString *) description {
    return [NSString
            stringWithFormat:
                    @"<%@[%p] rect:%@ options:%d owner:%@ userInfo:%p view:%@ "
                    @"rectInWindow:%@ mouseInside:%@ isToolTip:%@>",
                    [self class], self, NSStringFromRect(NS_EXTRA(NSTrackingArea, self)->_rect), NS_EXTRA(NSTrackingArea, self)->_options,
                    [NS_EXTRA(NSTrackingArea, self)->_owner class], NS_EXTRA(NSTrackingArea, self)->_userData, [NS_EXTRA(NSTrackingArea, self)->_view class],
                    NSStringFromRect(NS_EXTRA(NSTrackingArea, self)->_rectInWindow),
                    NS_EXTRA(NSTrackingArea, self)->_mouseInside ? @"YES" : @"NO", NS_EXTRA(NSTrackingArea, self)->_isToolTip ? @"YES" : @"NO"];
}

@end
