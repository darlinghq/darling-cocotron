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
#import <AppKit/NSBitmapImageRep-Private.h>
#import <AppKit/NSCachedImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindow-Private.h>
#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/CIContext.h>
#import "NSGraphics-Private.h"

@class NSColor;

@implementation NSGraphicsContext

- (NSInteger) contextID {
    return CGSMainConnectionID();
}

+ (void) initialize {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    BOOL enabled = [defaults boolForKey: @"NSQuartzDebugEnabled"];

    if (enabled) {
        NSLog(@"enabling Quartz Debugging emulation");
    }

    [NSGraphicsContext setQuartzDebuggingEnabled: enabled];

    [pool drain];
}

- initWithWindow: (NSWindow *) window {
    NS_EXTRA(NSGraphicsContext, self)->_graphicsPort = CGContextRetain([window cgContext]);
    NS_EXTRA(NSGraphicsContext, self)->_focusStack = [NSMutableArray new];
    NS_EXTRA(NSGraphicsContext, self)->_isDrawingToScreen = YES;
    NS_EXTRA(NSGraphicsContext, self)->_isFlipped = NO;
    NS_EXTRA(NSGraphicsContext, self)->_deviceDescription = [[window deviceDescription] copy];
    NS_EXTRA(NSGraphicsContext, self)->_shouldAntialias = YES;
    NS_EXTRA(NSGraphicsContext, self)->_renderingIntent = NSColorRenderingIntentDefault;
    NS_EXTRA(NSGraphicsContext, self)->_compOperation = NSCompositeSourceOver;
    return self;
}

- initWithGraphicsPort: (CGContextRef) context flipped: (BOOL) flipped {
    NS_EXTRA(NSGraphicsContext, self)->_graphicsPort = CGContextRetain(context);
    NS_EXTRA(NSGraphicsContext, self)->_focusStack = [NSMutableArray new];
    NS_EXTRA(NSGraphicsContext, self)->_isDrawingToScreen = CGContextIsBitmapContext(context);
    NS_EXTRA(NSGraphicsContext, self)->_isFlipped = flipped;
    NS_EXTRA(NSGraphicsContext, self)->_deviceDescription =
            [[NSDictionary dictionaryWithObject: [NSNumber numberWithBool: NO]
                                         forKey: NSDeviceIsScreen] copy];
    NS_EXTRA(NSGraphicsContext, self)->_shouldAntialias = YES;
    NS_EXTRA(NSGraphicsContext, self)->_renderingIntent = NSColorRenderingIntentDefault;
    NS_EXTRA(NSGraphicsContext, self)->_compOperation = NSCompositeSourceOver;
    return self;
}

- initWithBitmapImageRep: (NSBitmapImageRep *) imageRep {
    CGColorSpaceRef colorSpace = [imageRep CGColorSpace];

    if (colorSpace == nil) {
        [self dealloc];
        return nil;
    }

    NS_EXTRA(NSGraphicsContext, self)->_graphicsPort = CGBitmapContextCreate(
            [imageRep bitmapData], [imageRep pixelsWide], [imageRep pixelsHigh],
            [imageRep bitsPerSample], [imageRep bytesPerRow], colorSpace,
            [imageRep CGBitmapInfo]);

    if (NS_EXTRA(NSGraphicsContext, self)->_graphicsPort == nil) {
        [self dealloc];
        return nil;
    }

    NS_EXTRA(NSGraphicsContext, self)->_focusStack = [NSMutableArray new];
    NS_EXTRA(NSGraphicsContext, self)->_isDrawingToScreen = YES;
    NS_EXTRA(NSGraphicsContext, self)->_isFlipped = NO;
    NS_EXTRA(NSGraphicsContext, self)->_deviceDescription =
            [[NSDictionary dictionaryWithObject: [NSNumber numberWithBool: YES]
                                         forKey: NSDeviceIsScreen] copy];
    return self;
}

- (void) dealloc {
    if (NS_EXTRA(NSGraphicsContext, self)->_graphicsPort != NULL)
        CGContextRelease(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort);
    [NS_EXTRA(NSGraphicsContext, self)->_ciContext release];
    [NS_EXTRA(NSGraphicsContext, self)->_focusStack release];
    [NS_EXTRA(NSGraphicsContext, self)->_focusRingStack release];
    [NS_EXTRA(NSGraphicsContext, self)->_deviceDescription release];
    NS_EXTRA_FREE(NSGraphicsContext, self);
    [super dealloc];
}

+ (NSGraphicsContext *) graphicsContextWithWindow: (NSWindow *) window {
    return [[[self alloc] initWithWindow: window] autorelease];
}

+ (NSGraphicsContext *) graphicsContextWithGraphicsPort: (CGContextRef) context
                                                flipped: (BOOL) flipped
{
    return [[[self alloc] initWithGraphicsPort: context
                                       flipped: flipped] autorelease];
}

+ (NSGraphicsContext *) graphicsContextWithBitmapImageRep:
        (NSBitmapImageRep *) imageRep
{
    return [[[self alloc] initWithBitmapImageRep: imageRep] autorelease];
}

+ (NSGraphicsContext *) graphicsContextWithCGContext: (CGContextRef) context
                                             flipped: (BOOL) flipped
{
    return [[[self alloc] initWithGraphicsPort: context
                                       flipped: flipped] autorelease];
}

static NSMutableArray *_contextStack() {
    NSMutableDictionary *shared = [NSCurrentThread() sharedDictionary];
    NSMutableArray *stack = [shared objectForKey: @"NSGraphicsContext.stack"];

    if (stack == nil) {
        stack = [NSMutableArray array];
        [shared setObject: stack forKey: @"NSGraphicsContext.stack"];
    }

    return stack;
}

static NSGraphicsContext *_currentContext() {
    NSMutableDictionary *shared = [NSCurrentThread() sharedDictionary];
    id result = [shared objectForKey: @"NSGraphicsContext"];

    if (result == [NSNull null])
        return nil;

    return result;
}

CGContextRef NSCurrentGraphicsPort() {
    if (_currentContext() == nil)
        return NULL;

    return NS_EXTRA(NSGraphicsContext, _currentContext())->_graphicsPort;
}

NSMutableArray *NSCurrentFocusStack() {
    if (_currentContext() == nil)
        return nil;

    return NS_EXTRA(NSGraphicsContext, _currentContext())->_focusStack;
}

+ (NSGraphicsContext *) currentContext {
    NSGraphicsContext *current = _currentContext();

    return current;
}

+ (void) setCurrentContext: (NSGraphicsContext *) context {
    NSMutableDictionary *shared = [NSCurrentThread() sharedDictionary];

    if (context == nil)
        [shared setObject: [NSNull null] forKey: @"NSGraphicsContext"];
    else
        [shared setObject: context forKey: @"NSGraphicsContext"];
}

+ (void) saveGraphicsState {
    NSGraphicsContext *current = _currentContext();

    if (current != nil) {
        [_contextStack() addObject: current];
        [current saveGraphicsState];
    }
}

+ (void) restoreGraphicsState {
    NSGraphicsContext *current = [_contextStack() lastObject];

    if (current != nil) {
        [self setCurrentContext: current];
        [_contextStack() removeLastObject];
        [current restoreGraphicsState];
    }
}

+ (BOOL) currentContextDrawingToScreen {
    return [[NSGraphicsContext currentContext] isDrawingToScreen];
}

- (void *) graphicsPort {
    return NS_EXTRA(NSGraphicsContext, self)->_graphicsPort;
}

- (CGContextRef) CGContext {
    return [self graphicsPort];
}

- (NSMutableArray *) focusStack {
    return NS_EXTRA(NSGraphicsContext, self)->_focusStack;
}

- (BOOL) isDrawingToScreen {
    return NS_EXTRA(NSGraphicsContext, self)->_isDrawingToScreen;
}

- (BOOL) isFlipped {
    NSView *focusView = [NS_EXTRA(NSGraphicsContext, self)->_focusStack lastObject];

    if (focusView != nil)
        return [focusView isFlipped];

    return NS_EXTRA(NSGraphicsContext, self)->_isFlipped;
}

- (void) setShouldAntialias: (BOOL) flag {
    CGContextSetShouldAntialias(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, flag);
    NS_EXTRA(NSGraphicsContext, self)->_shouldAntialias = flag;
}

- (void) setImageInterpolation: (NSImageInterpolation) value {
    CGContextSetInterpolationQuality(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, value);
}

- (void) setColorRenderingIntent: (NSColorRenderingIntent) value {
    CGContextSetRenderingIntent(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, value);
    NS_EXTRA(NSGraphicsContext, self)->_renderingIntent = value;
}

- (void) setCompositingOperation: (NSCompositingOperation) value {
    switch ((int)value) {
    case NSCompositingOperationClear:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeClear); break;
    case NSCompositingOperationCopy:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeCopy); break;
    case NSCompositingOperationSourceOver:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeNormal); break;
    case NSCompositingOperationSourceIn:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeSourceIn); break;
    case NSCompositingOperationSourceOut:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeSourceOut); break;
    case NSCompositingOperationSourceAtop:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeSourceAtop); break;
    case NSCompositingOperationDestinationOver:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeDestinationOver); break;
    case NSCompositingOperationDestinationIn:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeDestinationIn); break;
    case NSCompositingOperationDestinationOut:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeDestinationOut); break;
    case NSCompositingOperationDestinationAtop:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeDestinationAtop); break;
    case NSCompositingOperationXOR:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeXOR); break;
    case NSCompositingOperationPlusDarker:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModePlusDarker); break;
    case NSCompositingOperationHighlight:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeNormal); break;
    case NSCompositingOperationPlusLighter:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModePlusLighter); break;
    case NSCompositingOperationMultiply:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeMultiply); break;
    case NSCompositingOperationScreen:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeScreen); break;
    case NSCompositingOperationOverlay:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeOverlay); break;
    case NSCompositingOperationDarken:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeDarken); break;
    case NSCompositingOperationLighten:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeLighten); break;
    case NSCompositingOperationColorDodge:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeColorDodge); break;
    case NSCompositingOperationColorBurn:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeColorBurn); break;
    case NSCompositingOperationSoftLight:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeSoftLight); break;
    case NSCompositingOperationHardLight:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeHardLight); break;
    case NSCompositingOperationDifference:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeDifference); break;
    case NSCompositingOperationExclusion:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeExclusion); break;
    case NSCompositingOperationHue:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeHue); break;
    case NSCompositingOperationSaturation:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeSaturation); break;
    case NSCompositingOperationColor:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeColor); break;
    case NSCompositingOperationLuminosity:
        CGContextSetBlendMode(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, kCGBlendModeLuminosity); break;
    default:
        return;
    }
    NS_EXTRA(NSGraphicsContext, self)->_compOperation = value;
}

- (void) setPatternPhase: (NSPoint) phase {
    CGContextSetPatternPhase(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort, CGSizeMake(phase.x, phase.y));
    NS_EXTRA(NSGraphicsContext, self)->_patternPhase = phase;
}

- (BOOL) shouldAntialias {
    return NS_EXTRA(NSGraphicsContext, self)->_shouldAntialias;
}

- (NSImageInterpolation) imageInterpolation {
    return CGContextGetInterpolationQuality(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort);
}

- (NSColorRenderingIntent) colorRenderingIntent {
    return NS_EXTRA(NSGraphicsContext, self)->_renderingIntent;
}

- (NSCompositingOperation) compositingOperation {
    return NS_EXTRA(NSGraphicsContext, self)->_compOperation;
}

- (NSPoint) patternPhase {
    return NS_EXTRA(NSGraphicsContext, self)->_patternPhase;
}

- (CIContext *) CIContext {
    if (NS_EXTRA(NSGraphicsContext, self)->_ciContext == nil)
        NS_EXTRA(NSGraphicsContext, self)->_ciContext = [[CIContext contextWithCGContext: NS_EXTRA(NSGraphicsContext, self)->_graphicsPort
                                              options: nil] retain];

    return NS_EXTRA(NSGraphicsContext, self)->_ciContext;
}

- (void) saveGraphicsState {
    CGContextSaveGState(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort);
    // the focus ring style is part of the graphics state
    if (NS_EXTRA(NSGraphicsContext, self)->_focusRingStack == nil)
        NS_EXTRA(NSGraphicsContext, self)->_focusRingStack = [[NSMutableArray alloc] init];
    NSInteger packed = NS_EXTRA(NSGraphicsContext, self)->_focusRingPlacement * 2 +
                       (NS_EXTRA(NSGraphicsContext, self)->_focusRingOuterOnly ? 1 : 0);
    [NS_EXTRA(NSGraphicsContext, self)->_focusRingStack addObject: [NSNumber numberWithInteger: packed]];
}

- (void) restoreGraphicsState {
    CGContextRestoreGState(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort);
    NSMutableArray *stack = NS_EXTRA(NSGraphicsContext, self)->_focusRingStack;

    if ([stack count] > 0) {
        NSInteger packed = [[stack lastObject] integerValue];

        NS_EXTRA(NSGraphicsContext, self)->_focusRingPlacement = packed / 2;
        NS_EXTRA(NSGraphicsContext, self)->_focusRingOuterOnly = (packed & 1) ? YES : NO;
        [stack removeLastObject];
    }
}

- (NSInteger) _focusRingPlacement {
    return NS_EXTRA(NSGraphicsContext, self)->_focusRingPlacement;
}

- (BOOL) _focusRingOuterOnly {
    return NS_EXTRA(NSGraphicsContext, self)->_focusRingOuterOnly;
}

- (void) _setFocusRingPlacement: (NSInteger) placement outerOnly: (BOOL) outerOnly {
    NS_EXTRA(NSGraphicsContext, self)->_focusRingPlacement = placement;
    NS_EXTRA(NSGraphicsContext, self)->_focusRingOuterOnly = outerOnly;
}

- (void) flushGraphics {
    CGContextFlush(NS_EXTRA(NSGraphicsContext, self)->_graphicsPort);
}

- (NSDictionary *) deviceDescription {
    return NS_EXTRA(NSGraphicsContext, self)->_deviceDescription;
}

@end

static BOOL sQuartzDebuggingEnabled = NO;
static BOOL sQuartzDebugging = NO;

@implementation NSGraphicsContext (QuartzDebugging)

+ (void) setQuartzDebuggingEnabled: (BOOL) enabled {
    sQuartzDebuggingEnabled = enabled;
}

+ (BOOL) quartzDebuggingIsEnabled {
    return sQuartzDebuggingEnabled;
}

+ (BOOL) inQuartzDebugMode {
    return sQuartzDebuggingEnabled && sQuartzDebugging;
}

+ (void) setQuartzDebugMode: (BOOL) mode {
    sQuartzDebugging = mode;
}

@end
