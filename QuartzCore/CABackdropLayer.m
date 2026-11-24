/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Developers

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
*/

#import <QuartzCore/CALayer.h>

/* CABackdropLayer is a CALayer subclass that WebKit declares in its QuartzCore SPI header
 * (Source/WebCore/PAL/pal/spi/cocoa/QuartzCoreSPI.h). Darling draws the content behind the layer
 * unchanged, so the class adds no behavior to CALayer's. */
@interface CABackdropLayer : CALayer
@end

@implementation CABackdropLayer
@end
