/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Team

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
*/

#import <QuartzCore/CAEAGLLayer.h>

#define EX(self) NS_EXTRA(CAEAGLLayer, self)

@implementation CAEAGLLayer

// Shared by -init and -initWithLayer:, which does not call -init. Unlike
// CALayer, a CAEAGLLayer starts opaque: the public QuartzCore header says so,
// and macOS 26.7.3 gives YES from -init, +layer and -initWithLayer: (also
// for a non-opaque source layer). Test: tests/quartzcore-caeagllayer.m
- (void) _setEAGLDefaults {
    [self setOpaque: YES];
}

- init {
    self = [super init];
    if (self != nil)
        [self _setEAGLDefaults];
    return self;
}

- initWithLayer: (id) layer {
    self = [super initWithLayer: layer];
    if (self != nil)
        [self _setEAGLDefaults];
    return self;
}

- (void) dealloc {
    [EX(self)->_drawableProperties release];
    NS_EXTRA_FREE(CAEAGLLayer, self);
    [super dealloc];
}

- (NSDictionary *) drawableProperties {
    return [[EX(self)->_drawableProperties retain] autorelease];
}

- (void) setDrawableProperties: (NSDictionary *) properties {
    properties = [properties copy];
    [EX(self)->_drawableProperties release];
    EX(self)->_drawableProperties = properties;
}

- (BOOL) presentsWithTransaction {
    return EX(self)->_presentsWithTransaction;
}

- (void) setPresentsWithTransaction: (BOOL) value {
    EX(self)->_presentsWithTransaction = value;
}

@end
