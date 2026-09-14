#import <Foundation/NSDictionary.h>
#import <QuartzCore/CAAnimation.h>
#import <QuartzCore/CALayer.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CATransaction.h>

NSString *const kCAFilterLinear = @"linear";
NSString *const kCAFilterNearest = @"nearest";
NSString *const kCAFilterTrilinear = @"trilinear";

NSString *const kCAGravityResizeAspect = @"resizeAspect";
NSString *const kCAGravityResizeAspectFill = @"resizeAspectFill";

NSString *const kCAGravityCenter = @"center";
NSString *const kCAGravityTop = @"top";
NSString *const kCAGravityBottom = @"bottom";
NSString *const kCAGravityLeft = @"left";
NSString *const kCAGravityRight = @"right";
NSString *const kCAGravityTopLeft = @"topLeft";
NSString *const kCAGravityTopRight = @"topRight";
NSString *const kCAGravityBottomLeft = @"bottomLeft";
NSString *const kCAGravityBottomRight = @"bottomRight";
NSString *const kCAGravityResize = @"resize";

NSString *const kCAOnOrderIn = @"onOrderIn";
NSString *const kCAOnOrderOut = @"onOrderOut";
NSString *const kCATransition = @"transition";

NSString *const kCAContentsFormatRGBA8Uint = @"RGBA8";
NSString *const kCAContentsFormatRGBA16Float = @"RGBAh";
NSString *const kCAContentsFormatGray8Uint = @"Gray8";

@implementation CALayer

+ layer {
    return [[[self alloc] init] autorelease];
}

- (CALayerContext *) _context {
    return _context;
}

- (void) _setContext: (CALayerContext *) context {
    if (_context != context) {
        [_context deleteTextureId: _textureId];
        [_textureId release];
        _textureId = nil;
    }

    _context = context;
    [_sublayers makeObjectsPerformSelector: @selector(_setContext:)
                                withObject: context];
}

- (CALayer *) superlayer {
    return _superlayer;
}

- (NSArray *) sublayers {
    return _sublayers;
}

- (void) setSublayers: (NSArray *) sublayers {
    sublayers = [sublayers copy];
    [_sublayers release];
    _sublayers = sublayers;
    [_sublayers makeObjectsPerformSelector: @selector(_setSuperLayer:)
                                withObject: self];
    [_sublayers makeObjectsPerformSelector: @selector(_setContext:)
                                withObject: _context];
}

- (id<CALayerDelegate>) delegate {
    return _delegate;
}

- (void) setDelegate: (id<CALayerDelegate>)value {
    _delegate = value;
}

- (CGPoint) anchorPoint {
    return _anchorPoint;
}

- (void) setAnchorPoint: (CGPoint) value {
    _anchorPoint = value;
}

- (CGPoint) position {
    return _position;
}

- (void) setPosition: (CGPoint) value {
    CAAnimation *animation = [self animationForKey: @"position"];

    if (animation == nil && ![CATransaction disableActions]) {
        id action = [self actionForKey: @"position"];

        if (action != nil)
            [self addAnimation: action forKey: @"position"];
    }

    _position = value;
}

- (CGRect) bounds {
    return _bounds;
}

- (void) setBounds: (CGRect) value {
    CAAnimation *animation = [self animationForKey: @"bounds"];

    if (animation == nil && ![CATransaction disableActions]) {
        id action = [self actionForKey: @"bounds"];

        if (action != nil)
            [self addAnimation: action forKey: @"bounds"];
    }

    BOOL sizeChanged = !CGSizeEqualToSize(_bounds.size, value.size);
    _bounds = value;
    if (sizeChanged && _needsDisplayOnBoundsChange)
        [self setNeedsDisplay];
}

- (CGRect) frame {
    CGRect result;

    result.size = _bounds.size;
    result.origin.x = _position.x - result.size.width * _anchorPoint.x;
    result.origin.y = _position.y - result.size.height * _anchorPoint.y;

    return result;
}

- (void) setFrame: (CGRect) value {

    CGPoint position;

    position.x = value.origin.x + value.size.width * _anchorPoint.x;
    position.y = value.origin.y + value.size.height * _anchorPoint.y;

    [self setPosition: position];

    CGRect bounds = _bounds;

    bounds.size = value.size;

    [self setBounds: bounds];
}

- (CGFloat) opacity {
    return _opacity;
}

- (void) setOpacity: (CGFloat) value {
    CAAnimation *animation = [self animationForKey: @"opacity"];

    if (animation == nil && ![CATransaction disableActions]) {
        id action = [self actionForKey: @"opacity"];

        if (action != nil)
            [self addAnimation: action forKey: @"opacity"];
    }

    _opacity = value;
}

- (BOOL) opaque {
    return _opaque;
}

- (void) setOpaque: (BOOL) value {
    _opaque = value;
}

- (id) contents {
    return _contents;
}

- (void) setContents: (id) value {
    value = [value retain];
    [_contents release];
    _contents = value;
}

- (CATransform3D) transform {
    return _transform;
}

- (void) setTransform: (CATransform3D) value {
    _transform = value;
}

- (CATransform3D) sublayerTransform {
    return _sublayerTransform;
}

- (void) setSublayerTransform: (CATransform3D) value {
    _sublayerTransform = value;
}

- (NSString *) minificationFilter {
    return _minificationFilter;
}

- (void) setMinificationFilter: (NSString *) value {
    value = [value copy];
    [_minificationFilter release];
    _minificationFilter = value;
}

- (NSString *) magnificationFilter {
    return _magnificationFilter;
}

- (void) setMagnificationFilter: (NSString *) value {
    value = [value copy];
    [_magnificationFilter release];
    _magnificationFilter = value;
}

- init {
    _superlayer = nil;
    _sublayers = [NSArray new];
    _delegate = nil;
    _anchorPoint = CGPointMake(0.5, 0.5);
    _position = CGPointZero;
    _bounds = CGRectZero;
    _opacity = 1.0;
    _opaque = YES;
    _contents = nil;
    _transform = CATransform3DIdentity;
    _sublayerTransform = CATransform3DIdentity;
    _minificationFilter = kCAFilterLinear;
    _magnificationFilter = kCAFilterLinear;
    _animations = [[NSMutableDictionary alloc] init];
    return self;
}

- (void) dealloc {
    [_sublayers release];
    [_animations release];
    [_minificationFilter release];
    [_magnificationFilter release];
    if (_backgroundColor)
        CGColorRelease(_backgroundColor);
    if (_borderColor)
        CGColorRelease(_borderColor);
    [_textureContents release];
    [super dealloc];
}

static void replaceColor(CGColorRef *slot, CGColorRef value) {
    if (*slot == value)
        return;
    if (value)
        CGColorRetain(value);
    if (*slot)
        CGColorRelease(*slot);
    *slot = value;
}

- (CGColorRef) backgroundColor {
    return _backgroundColor;
}

// Appearance changes need a new frame even when no view is redisplayed: the
// context's timer renders and presents one, then stops again once idle.
- (void) setBackgroundColor: (CGColorRef) value {
    replaceColor(&_backgroundColor, value);
    [_context startTimerIfNeeded];
}

- (CGColorRef) borderColor {
    return _borderColor;
}

- (void) setBorderColor: (CGColorRef) value {
    replaceColor(&_borderColor, value);
    [_context startTimerIfNeeded];
}

- (CGFloat) borderWidth {
    return _borderWidth;
}

- (void) setBorderWidth: (CGFloat) value {
    _borderWidth = value;
    [_context startTimerIfNeeded];
}

- (CGFloat) cornerRadius {
    return _cornerRadius;
}

- (void) setCornerRadius: (CGFloat) value {
    _cornerRadius = value;
    [_context startTimerIfNeeded];
}

- (BOOL) masksToBounds {
    return _masksToBounds;
}

- (void) setMasksToBounds: (BOOL) value {
    _masksToBounds = value;
    [_context startTimerIfNeeded];
}

- (BOOL) isHidden {
    return _hidden;
}

- (void) setHidden: (BOOL) value {
    _hidden = value;
    [_context startTimerIfNeeded];
}

- (void) _setSuperLayer: (CALayer *) parent {
    _superlayer = parent;
}

- (void) _removeSublayer: (CALayer *) child {
    NSMutableArray *layers = [_sublayers mutableCopy];
    [layers removeObjectIdenticalTo: child];
    [self setSublayers: layers];
    [layers release];
}

- (void) addSublayer: (CALayer *) layer {
    [self setSublayers: [_sublayers arrayByAddingObject: layer]];
}

- (void) replaceSublayer: (CALayer *) layer with: (CALayer *) other {
    NSMutableArray *layers = [_sublayers mutableCopy];
    NSUInteger index = [_sublayers indexOfObjectIdenticalTo: layer];

    [layers replaceObjectAtIndex: index withObject: other];

    [self setSublayers: layers];
    [layers release];

    layer->_superlayer = nil;
}

// Draws the layer's content with -drawInContext: (or the delegate's
// -drawLayer:inContext:) into a bitmap the size of the bounds and makes that the
// layer's contents, which the renderer uploads as a texture. A delegate that
// implements -displayLayer: sets the contents itself instead.
- (void) display {
    if ([_delegate respondsToSelector: @selector(displayLayer:)]) {
        [_delegate displayLayer: self];
        return;
    }

    size_t width = (size_t) ceil(MAX(_bounds.size.width, 0));
    size_t height = (size_t) ceil(MAX(_bounds.size.height, 0));
    if (width == 0 || height == 0) {
        [self setContents: nil];
        return;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
            NULL, width, height, 8, 0, colorSpace,
            kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL)
        return;

    CGContextClearRect(context, CGRectMake(0, 0, width, height));
    // Layer coordinates: the bounds origin is the bitmap's bottom-left corner.
    CGContextTranslateCTM(context, -_bounds.origin.x, -_bounds.origin.y);
    [self drawInContext: context];

    CGImageRef image = CGBitmapContextCreateImage(context);
    [self setContents: (id) image];
    if (image != NULL)
        CGImageRelease(image);
    CGContextRelease(context);
}

- (void) displayIfNeeded {
    if (_needsDisplay) {
        _needsDisplay = NO;
        [self display];
    }
}

- (BOOL) needsDisplayOnBoundsChange {
    return _needsDisplayOnBoundsChange;
}

- (void) setNeedsDisplayOnBoundsChange: (BOOL) value {
    _needsDisplayOnBoundsChange = value;
}

- (void) drawInContext: (CGContextRef) context {
    if ([_delegate respondsToSelector: @selector(drawLayer:inContext:)])
        [_delegate drawLayer: self inContext: context];
}

- (BOOL) needsDisplay {
    return _needsDisplay;
}

- (void) removeFromSuperlayer {
    [_superlayer _removeSublayer: self];
    _superlayer = nil;
    [self _setContext: nil];
}

- (void) setNeedsDisplay {
    _needsDisplay = YES;
    // Get a frame rendered: the context's timer renders, presents, and stops
    // again once no animations are running.
    [_context startTimerIfNeeded];
}

- (void) setNeedsDisplayInRect: (CGRect) rect {
    [self setNeedsDisplay];
}

- (void) addAnimation: (CAAnimation *) animation forKey: (NSString *) key {
    if (_context == nil)
        return;

    [_animations setObject: animation forKey: key];
    [_context startTimerIfNeeded];
}

- (CAAnimation *) animationForKey: (NSString *) key {
    return [_animations objectForKey: key];
}

- (void) removeAllAnimations {
    [_animations removeAllObjects];
}

- (void) removeAnimationForKey: (NSString *) key {
    [_animations removeObjectForKey: key];
}

- (NSArray *) animationKeys {
    return [_animations allKeys];
}

- valueForKey: (NSString *) key {
    // FIXME: KVC appears broken for structs

    if ([key isEqualToString: @"bounds"])
        return [NSValue valueWithRect: _bounds];
    if ([key isEqualToString: @"frame"])
        return [NSValue valueWithRect: [self frame]];

    return [super valueForKey: key];
}

- (id<CAAction>) actionForKey: (NSString *) key {
    CABasicAnimation *basic = [CABasicAnimation animationWithKeyPath: key];

    [basic setFromValue: [self valueForKey: key]];

    return basic;
}

- (NSNumber *) _textureId {
    return _textureId;
}

- (void) _setTextureId: (NSNumber *) value {
    value = [value copy];
    [_textureId release];
    _textureId = value;
}

- (id) _textureContents {
    return _textureContents;
}

- (void) _setTextureContents: (id) value {
    value = [value retain];
    [_textureContents release];
    _textureContents = value;
}

@end
