/* Copyright (c) 2026 Darling Developers

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

#import <AppKit/NSGlassEffectView.h>
#import <AppKit/NSColor.h>

@implementation NSGlassEffectView

@synthesize contentView = _glassContentView;
@synthesize cornerRadius = _cornerRadius;
@synthesize style = _style;

- (instancetype) initWithFrame: (NSRect) frame
{
    self = [super initWithFrame: frame];
    if (self == nil)
        return nil;

    _style = NSGlassEffectViewStyleRegular;
    _cornerRadius = 8.0;
    return self;
}

- (void) setContentView: (NSView *) view
{
    if (_glassContentView == view)
        return;

    [_glassContentView removeFromSuperview];
    [_glassContentView release];
    _glassContentView = [view retain];
    if (_glassContentView != nil)
        [self addSubview: _glassContentView];
}

- (NSColor *) tintColor
{
    return _tintColor;
}

- (void) setTintColor: (NSColor *) color
{
    color = [color copy];
    [_tintColor release];
    _tintColor = color;
}

- (void) dealloc
{
    [_glassContentView removeFromSuperview];
    [_glassContentView release];
    [_tintColor release];
    [super dealloc];
}

@end

@implementation NSGlassEffectContainerView

@synthesize contentView = _containerContentView;
@synthesize spacing = _spacing;

- (void) setContentView: (NSView *) view
{
    if (_containerContentView == view)
        return;

    [_containerContentView removeFromSuperview];
    [_containerContentView release];
    _containerContentView = [view retain];
    if (_containerContentView != nil)
        [self addSubview: _containerContentView];
}

- (void) dealloc
{
    [_containerContentView removeFromSuperview];
    [_containerContentView release];
    [super dealloc];
}

@end
