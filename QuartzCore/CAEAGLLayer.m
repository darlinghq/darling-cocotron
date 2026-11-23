/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Team

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
*/

#import <QuartzCore/CAEAGLLayer.h>

@implementation CAEAGLLayer

- (void) dealloc {
    [_drawableProperties release];
    [super dealloc];
}

- (NSDictionary *) drawableProperties {
    return [[_drawableProperties retain] autorelease];
}

- (void) setDrawableProperties: (NSDictionary *) properties {
    properties = [properties copy];
    [_drawableProperties release];
    _drawableProperties = properties;
}

- (BOOL) presentsWithTransaction {
    return _presentsWithTransaction;
}

- (void) setPresentsWithTransaction: (BOOL) value {
    _presentsWithTransaction = value;
}

@end
