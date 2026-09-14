/* Copyright (c) 2006-2007 Dr. Rolf Jansen

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
#import "NSCustomView.h"
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSString.h>

@implementation NSCustomView

- (id) initWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        NSString *className = [(NSKeyedUnarchiver *) coder
                decodeObjectForKey: @"NSClassName"];
        Class class = NSClassFromString(className);
        if (class == nil) {
            NSLog(@"NSCustomView unknown class %@", className);
            return self;
        } else {
            NSRect frame = NSZeroRect;
            if ([coder containsValueForKey: @"NSFrame"])
                frame = [coder decodeRectForKey: @"NSFrame"];
            else if ([coder containsValueForKey: @"NSFrameSize"])
                frame.size = [coder decodeSizeForKey: @"NSFrameSize"];

            NSView *newView = nil;
            if ([class isSubclassOfClass: [NSView class]])
                newView = [[class alloc] initWithFrame: frame];
            // Decoding nil would drop the whole subviews array this view is in.
            if (newView == nil) {
                NSLog(@"NSCustomView: %@ is not a view class or its "
                      @"initWithFrame: returned nil; using a plain NSView",
                      className);
                newView = [[NSView alloc] initWithFrame: frame];
            }
            if ([coder containsValueForKey: @"NSvFlags"]) {
                unsigned vFlags = [coder decodeIntForKey: @"NSvFlags"];

                newView->_autoresizingMask = vFlags & 0x3F;
                newView->_autoresizesSubviews = (vFlags & 0x100) ? YES : NO;
                newView->_isHidden = (vFlags & 0x80000000) ? YES : NO;
            }
            // Despite the fact it appears _autoresizesSubviews is encoded in
            // the flags, it should always be on
            newView->_autoresizesSubviews = YES;

            if ([coder containsValueForKey: @"NSTag"])
                newView->_tag = [coder decodeIntForKey: @"NSTag"];
            NSArray *subviews = [coder decodeObjectForKey: @"NSSubviews"];

            // For some unknown reason custom view subviews are presented in
            // reverse order in the nib - so we need to add them in reverse -
            // this matches Cocoa behaviour
            NSEnumerator *reverseEnum = [subviews reverseObjectEnumerator];
            NSView *subview = nil;
            while ((subview = [reverseEnum nextObject])) {
                [newView->_subviews addObject: subview];
            }

            [newView->_subviews
                    makeObjectsPerformSelector: @selector(_setSuperview:)
                                    withObject: newView];
            [_subviews removeAllObjects];

            [newView setWantsLayer: [coder decodeBoolForKey:
                                                    @"NSViewIsLayerTreeHost"]];
            [newView setLayerContentsRedrawPolicy:
                             [coder decodeIntegerForKey: @"NSViewLayerContentsR"
                                                         @"edrawPolicy"]];
            [self release];
            return (NSCustomView*)newView;
        }
    } else {
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] does not handle %@", [self class],
                            sel_getName(_cmd), [coder class]];
        return self;
    }
}

@end
