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

#import <AppKit/NSView.h>

@class NSColor;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NSGlassEffectViewStyle) {
    NSGlassEffectViewStyleRegular = 0,
    NSGlassEffectViewStyleClear = 1,
};

// A view that embeds its content view in a glass effect. The glass is not rendered; the view
// holds its content like any other NSView and lays it out as its subview.

APPKIT_EXPORT
@interface NSGlassEffectView : NSView {
    NSView *_glassContentView;
    CGFloat _cornerRadius;
    NSColor *_tintColor;
    NSGlassEffectViewStyle _style;
}

@property(nullable, nonatomic, strong) __kindof NSView *contentView;
@property(nonatomic) CGFloat cornerRadius;
@property(nullable, nonatomic, copy) NSColor *tintColor;
@property(nonatomic) NSGlassEffectViewStyle style;

@end

// A view that groups glass effect views.

APPKIT_EXPORT
@interface NSGlassEffectContainerView : NSView {
    NSView *_containerContentView;
    CGFloat _spacing;
}

@property(nullable, nonatomic, strong) __kindof NSView *contentView;
@property(nonatomic) CGFloat spacing;

@end

NS_ASSUME_NONNULL_END
