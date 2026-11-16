/* Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>

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

// The parts of NSLayoutManager that deal with AppKit's ruler. The layout
// manager itself is in UIFoundation, which does not link against AppKit.

#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSRulerMarker.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextTab.h>
#import <AppKit/NSTextView.h>

#import "NSRulerMarker+NSTextExtensions.h"

@implementation NSLayoutManager (AppKit)

- (NSArray *) rulerMarkersForTextView: (NSTextView *) view
                       paragraphStyle: (NSParagraphStyle *) style
                                ruler: (NSRulerView *) ruler
{
    NSMutableArray *markers = [NSMutableArray array];

    CGFloat delta =
            view.textContainer.lineFragmentPadding + view.textContainerOrigin.x;

    // Add the margins markers
#if 0
    // Don't add these markers for now - their values are ignored by the layout manager
    NSRulerMarker *marker = nil;
    
    marker = [NSRulerMarker leftMarginMarkerWithRulerView:ruler location:style.headIndent + delta];
    [marker setRepresentedObject:@"NSHeadIndentRulerMarkerTag"];
    [markers addObject:marker];
    
    // Looks like tailIndent value is a bit more complex - see Cocoa specs
    marker = [NSRulerMarker rightMarginMarkerWithRulerView:ruler location:view.textContainer.containerSize.width - style.tailIndent - delta];
    [marker setRepresentedObject:@"NSTailIndentRulerMarkerTag"];
    [markers addObject:marker];
    
    marker = [NSRulerMarker firstIndentMarkerWithRulerView:ruler location:style.firstLineHeadIndent + delta];
    [marker setRepresentedObject:@"NSFirstLineHeadIndentRulerMarkerTag"];
    [markers addObject:marker];
#endif
    // Add the tab stops markers
    for (NSTextTab *textTab in style.tabStops) {
        NSRulerMarker *marker = nil;
        switch (textTab.tabStopType) {
        case NSLeftTabStopType:
            marker = [NSRulerMarker
                    leftTabMarkerWithRulerView: ruler
                                      location: textTab.location + delta];
            break;
        case NSRightTabStopType:
            marker = [NSRulerMarker
                    rightTabMarkerWithRulerView: ruler
                                       location: textTab.location + delta];
            break;
        case NSCenterTabStopType:
            marker = [NSRulerMarker
                    centerTabMarkerWithRulerView: ruler
                                        location: textTab.location + delta];
            break;
        case NSDecimalTabStopType:
            marker = [NSRulerMarker
                    decimalTabMarkerWithRulerView: ruler
                                         location: textTab.location + delta];
            break;
        default:
            break;
        }
        if (marker) {
            [marker setRepresentedObject: textTab];
            [marker setRemovable: YES];
            [markers addObject: marker];
        }
    }
    return markers;
}

- (NSView *) rulerAccessoryViewForTextView: (NSTextView *) view
                            paragraphStyle: (NSParagraphStyle *) style
                                     ruler: (NSRulerView *) ruler
                                   enabled: (BOOL) isEnabled
{
    return nil;
}

@end
