#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <QuartzCore/CAAnimation.h>
#import <QuartzCore/CAConstraintLayoutManager.h>
#import <QuartzCore/CALayer.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CATransaction.h>
#import <Onyx2D/O2Image.h>
#import "CAKeyedCoding.h"
#import "CALayerInternal.h"

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
CALayerCornerCurve const kCACornerCurveCircular = @"circular";
CALayerCornerCurve const kCACornerCurveContinuous = @"continuous";

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
    [_mask _setContext: context];
}

- (id) _contentsForRendering: (CGRect *) rect {
    return [self contents];
}

- (CALayer *) superlayer {
    return _superlayer;
}

- (NSArray *) sublayers {
    return _sublayers;
}

- (void) setSublayers: (NSArray *) sublayers {
    sublayers = [sublayers copy];

    // A layer has a single superlayer, so the new sublayers leave the layers
    // they are in now.
    for (CALayer *layer in sublayers) {
        if (layer->_superlayer != nil && layer->_superlayer != self)
            [layer removeFromSuperlayer];
    }

    // Sublayers that are not kept stop pointing at this layer and its context
    // before the array that may own them goes away.
    for (CALayer *layer in _sublayers) {
        if ([sublayers indexOfObjectIdenticalTo: layer] == NSNotFound) {
            layer->_superlayer = nil;
            [layer _setContext: nil];
        }
    }

    [_sublayers release];
    _sublayers = sublayers;
    [_sublayers makeObjectsPerformSelector: @selector(_setSuperLayer:)
                                withObject: self];
    [_sublayers makeObjectsPerformSelector: @selector(_setContext:)
                                withObject: _context];
    [self setNeedsLayout];
}

- (id<CALayerDelegate>) delegate {
    return _delegate;
}

- (void) setDelegate: (id<CALayerDelegate>)value {
    _delegate = value;
}

- (NSString *) name {
    return _name;
}

- (void) setName: (NSString *) value {
    value = [value copy];
    [_name release];
    _name = value;
}

- (id<CALayoutManager>) layoutManager {
    return _layoutManager;
}

- (void) setLayoutManager: (id<CALayoutManager>) value {
    [value retain];
    [_layoutManager release];
    _layoutManager = value;
    [self setNeedsLayout];
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
        id<CAAction> action = [self actionForKey: @"position"];

        [action runActionForKey: @"position" object: self arguments: nil];
    }

    _position = value;
}

- (CGRect) bounds {
    return _bounds;
}

- (void) setBounds: (CGRect) value {
    CAAnimation *animation = [self animationForKey: @"bounds"];

    if (animation == nil && ![CATransaction disableActions]) {
        id<CAAction> action = [self actionForKey: @"bounds"];

        [action runActionForKey: @"bounds" object: self arguments: nil];
    }

    BOOL sizeChanged = !CGSizeEqualToSize(_bounds.size, value.size);
    _bounds = value;
    if (sizeChanged)
        [self setNeedsLayout];
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
        id<CAAction> action = [self actionForKey: @"opacity"];

        [action runActionForKey: @"opacity" object: self arguments: nil];
    }

    _opacity = value;
}

- (BOOL) isOpaque {
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
    [_context startTimerIfNeeded];
}

- (CGFloat) contentsScale {
    return _contentsScale;
}

- (void) setContentsScale: (CGFloat) value {
    _contentsScale = value;
}

- (CGRect) contentsCenter {
    return _contentsCenter;
}

- (void) setContentsCenter: (CGRect) value {
    _contentsCenter = value;
}

- (CALayerContentsFormat) contentsFormat {
    return _contentsFormat;
}

- (void) setContentsFormat: (CALayerContentsFormat) value {
    value = [value copy];
    [_contentsFormat release];
    _contentsFormat = value;
}

- (CALayerContentsGravity) contentsGravity {
    return _contentsGravity;
}

- (void) setContentsGravity: (CALayerContentsGravity) value {
    value = [value copy];
    [_contentsGravity release];
    _contentsGravity = value;
    [_context startTimerIfNeeded];
}

- (BOOL) allowsEdgeAntialiasing {
    return _allowsEdgeAntialiasing;
}

- (void) setAllowsEdgeAntialiasing: (BOOL) value {
    _allowsEdgeAntialiasing = value;
}

- (CAEdgeAntialiasingMask) edgeAntialiasingMask {
    return _edgeAntialiasingMask;
}

- (void) setEdgeAntialiasingMask: (CAEdgeAntialiasingMask) value {
    _edgeAntialiasingMask = value;
}

- (CATransform3D) transform {
    return _transform;
}

- (void) setTransform: (CATransform3D) value {
    _transform = value;
    [_context startTimerIfNeeded];
}

- (CGAffineTransform) affineTransform {
    return CGAffineTransformMake(_transform.m11, _transform.m12,
                                 _transform.m21, _transform.m22,
                                 _transform.m41, _transform.m42);
}

- (void) setAffineTransform: (CGAffineTransform) value {
    [self setTransform: CATransform3DMakeAffineTransform(value)];
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

// Shared by -init and -initWithLayer:. The latter must not call -init, or a
// subclass's override of -init would run again on the copy.
- (void) _setDefaults {
    _superlayer = nil;
    _sublayers = [NSArray new];
    _delegate = nil;
    _anchorPoint = CGPointMake(0.5, 0.5);
    _position = CGPointZero;
    _bounds = CGRectZero;
    _opacity = 1.0;
    _opaque = YES;
    _contents = nil;
    _contentsScale = 1.0;
    // The whole contents image stretches, i.e. no fixed border.
    _contentsCenter = CGRectMake(0, 0, 1, 1);
    _contentsRect = CGRectMake(0, 0, 1, 1);
    _doubleSided = YES;
    _rasterizationScale = 1.0;
    _contentsFormat = [kCAContentsFormatRGBA8Uint copy];
    _contentsGravity = [kCAGravityResize copy];
    _cornerCurve = [kCACornerCurveCircular copy];
    _allowsGroupOpacity = YES;
    _shadowColor = CGColorCreateGenericRGB(0, 0, 0, 1);
    _shadowOpacity = 0;
    _shadowRadius = 3;
    _shadowOffset = CGSizeMake(0, -3);
    _allowsEdgeAntialiasing = NO;
    _edgeAntialiasingMask = kCALayerLeftEdge | kCALayerRightEdge | kCALayerBottomEdge | kCALayerTopEdge;
    _transform = CATransform3DIdentity;
    _sublayerTransform = CATransform3DIdentity;
    _minificationFilter = kCAFilterLinear;
    _magnificationFilter = kCAFilterLinear;
    _animations = [[NSMutableDictionary alloc] init];
}

- init {
    [self _setDefaults];
    return self;
}

// A copy of a layer starts with the default state; the properties of the layer
// it is made from are not carried over, and the argument is not examined.
// Subclasses copy their own state in their overrides. The defaults are set
// without calling -init, so that a subclass's -init does not run again.
// QUIRK: macOS leaves the new layer in its default state, accepts any object
// (or nil) as the argument and does not raise. Not documented (the
// presentation layer copy is filled in by the system, not by this method).
// Evidence: black-box observation on macOS 26.7.3 (tier 2),
// vd-upstream mac-probes/v314-initwithlayer.m.
// Test: tests/quartzcore-layer-init-with-layer.swift
- initWithLayer: (id) layer {
    self = [super init];
    if (self != nil)
        [self _setDefaults];
    return self;
}

+ (BOOL) supportsSecureCoding {
    return YES;
}

static BOOL isOpaqueBlack(CGColorRef color) {
    if (color == NULL || CGColorGetNumberOfComponents(color) != 4)
        return NO;
    const CGFloat *c = CGColorGetComponents(color);
    return c[0] == 0 && c[1] == 0 && c[2] == 0 && c[3] == 1;
}

// A layer archive holds the layer's own state: the delegate, the superlayer,
// animations and the render context are left out; the parent restores the
// superlayer when it decodes its sublayers. Properties at their default value
// are not written (macOS writes some that were set explicitly to a default
// value; that is not tracked here), except the four that always are.
// Subclasses add their keys by overriding -_encodeAttributes:.
- (void) encodeWithCoder: (NSCoder *) coder {
    CAArchiveWriter *writer = [CAArchiveWriter writerWithCoder: coder];
    [self _encodeAttributes: writer];
    [writer finish];
}

- (void) _encodeAttributes: (CAArchiveWriter *) w {
    [w encodeBool: _allowsEdgeAntialiasing forKey: @"allowsEdgeAntialiasing"];
    [w encodeBool: _allowsGroupOpacity forKey: @"allowsGroupOpacity"];
    [w encodeObject: _contentsFormat forKey: @"contentsFormat"];
    [w encodeObject: _cornerCurve forKey: @"cornerCurve"];

    if ([_sublayers count] > 0)
        [w encodeArray: _sublayers forKey: @"sublayers"];
    if (_mask != nil)
        [w encodeObject: _mask forKey: @"mask"];
    if (_name != nil)
        [w encodeObject: _name forKey: @"name"];
    if (_anchorPoint.x != 0.5 || _anchorPoint.y != 0.5)
        [w encodePoint: _anchorPoint forKey: @"anchorPoint"];
    if (_anchorPointZ != 0)
        [w encodeDouble: _anchorPointZ forKey: @"anchorPointZ"];
    if (_position.x != 0 || _position.y != 0)
        [w encodePoint: _position forKey: @"position"];
    if (_zPosition != 0)
        [w encodeDouble: _zPosition forKey: @"zPosition"];
    if (!CGRectEqualToRect(_bounds, CGRectZero))
        [w encodeRect: _bounds forKey: @"bounds"];
    if (_opacity != 1)
        [w encodeFloat: _opacity forKey: @"opacity"];
    if (_opaque)
        [w encodeBool: YES forKey: @"opaque"];
    if (_contents != nil)
        [w encodeContents: _contents forKey: @"contents"];
    if (_contentsScale != 1)
        [w encodeDouble: _contentsScale forKey: @"contentsScale"];
    if (!CGRectEqualToRect(_contentsCenter, CGRectMake(0, 0, 1, 1)))
        [w encodeRect: _contentsCenter forKey: @"contentsCenter"];
    if (!CGRectEqualToRect(_contentsRect, CGRectMake(0, 0, 1, 1)))
        [w encodeRect: _contentsRect forKey: @"contentsRect"];
    if (![_contentsGravity isEqualToString: kCAGravityResize])
        [w encodeObject: _contentsGravity forKey: @"contentsGravity"];
    if (_shadowPath != NULL)
        [w encodePath: _shadowPath forKey: @"shadowPath"];
    if (_edgeAntialiasingMask != (kCALayerLeftEdge | kCALayerRightEdge | kCALayerBottomEdge | kCALayerTopEdge))
        [w encodeInt: _edgeAntialiasingMask forKey: @"edgeAntialiasingMask"];
    if (_autoresizingMask != 0)
        [w encodeInt: _autoresizingMask forKey: @"autoresizingMask"];
    if (!CATransform3DIsIdentity(_transform))
        [w encodeTransform: _transform forKey: @"transform"];
    if (!CATransform3DIsIdentity(_sublayerTransform))
        [w encodeTransform: _sublayerTransform forKey: @"sublayerTransform"];
    if (![_minificationFilter isEqualToString: kCAFilterLinear])
        [w encodeObject: _minificationFilter forKey: @"minificationFilter"];
    if (![_magnificationFilter isEqualToString: kCAFilterLinear])
        [w encodeObject: _magnificationFilter forKey: @"magnificationFilter"];
    if (_minificationFilterBias != 0)
        [w encodeFloat: _minificationFilterBias forKey: @"minificationFilterBias"];
    if (_backgroundColor != NULL)
        [w encodeColor: _backgroundColor forKey: @"backgroundColor"];
    if (_borderColor != NULL && !isOpaqueBlack(_borderColor))
        [w encodeColor: _borderColor forKey: @"borderColor"];
    if (_borderWidth != 0)
        [w encodeDouble: _borderWidth forKey: @"borderWidth"];
    if (_cornerRadius != 0)
        [w encodeDouble: _cornerRadius forKey: @"cornerRadius"];
    if (_masksToBounds)
        [w encodeBool: YES forKey: @"masksToBounds"];
    if (_filters != nil)
        [w encodeArray: _filters forKey: @"filters"];
    if (_backgroundFilters != nil)
        [w encodeArray: _backgroundFilters forKey: @"backgroundFilters"];
    if (_compositingFilter != nil)
        [w encodeObject: _compositingFilter forKey: @"compositingFilter"];
    if (_shadowColor != NULL && !isOpaqueBlack(_shadowColor))
        [w encodeColor: _shadowColor forKey: @"shadowColor"];
    if (_shadowOpacity != 0)
        [w encodeFloat: _shadowOpacity forKey: @"shadowOpacity"];
    if (_shadowRadius != 3)
        [w encodeDouble: _shadowRadius forKey: @"shadowRadius"];
    if (_shadowOffset.width != 0 || _shadowOffset.height != -3)
        [w encodeSize: _shadowOffset forKey: @"shadowOffset"];
    if (_hidden)
        [w encodeBool: YES forKey: @"hidden"];
    if (_geometryFlipped)
        [w encodeBool: YES forKey: @"geometryFlipped"];
    if (!_doubleSided)
        [w encodeBool: NO forKey: @"doubleSided"];
    if (_shouldRasterize)
        [w encodeBool: YES forKey: @"shouldRasterize"];
    if (_rasterizationScale != 1)
        [w encodeDouble: _rasterizationScale forKey: @"rasterizationScale"];
    if (_drawsAsynchronously)
        [w encodeBool: YES forKey: @"drawsAsynchronously"];
    if (_needsDisplayOnBoundsChange)
        [w encodeBool: YES forKey: @"needsDisplayOnBoundsChange"];
    if (_constraints != nil)
        [w encodeArray: _constraints forKey: @"constraints"];
    if (_layoutManager != nil)
        [w encodeObject: _layoutManager forKey: @"layoutManager"];
    if (_actions != nil)
        [w encodeObject: _actions forKey: @"actions"];
    if (_style != nil)
        [w encodeObject: _style forKey: @"style"];
}

- initWithCoder: (NSCoder *) coder {
    CAArchiveReader *reader = [CAArchiveReader readerWithCoder: coder];
    self = [super init];
    if (self == nil)
        return nil;
    [self _setDefaults];
    [self _decodeAttributes: reader];
    return self;
}

// Keys that are absent keep their defaults. Scalars are assigned directly, since
// some setters start implicit animations or notify the context.
- (void) _decodeAttributes: (CAArchiveReader *) r {
    BOOL flag;
    int integer;
    float single;
    double real;
    CGPoint point;
    CGSize size;
    CGRect rect;
    CATransform3D transform;

    if ([r decodeBool: &flag forKey: @"allowsEdgeAntialiasing"])
        _allowsEdgeAntialiasing = flag;
    if ([r decodeBool: &flag forKey: @"allowsGroupOpacity"])
        _allowsGroupOpacity = flag;
    NSString *string = [r decodeStringForKey: @"contentsFormat"];
    if (string != nil)
        [self setContentsFormat: string];
    string = [r decodeStringForKey: @"cornerCurve"];
    if (string != nil)
        [self setCornerCurve: string];
    string = [r decodeStringForKey: @"contentsGravity"];
    if (string != nil)
        [self setContentsGravity: string];
    string = [r decodeStringForKey: @"minificationFilter"];
    if (string != nil)
        [self setMinificationFilter: string];
    string = [r decodeStringForKey: @"magnificationFilter"];
    if (string != nil)
        [self setMagnificationFilter: string];
    string = [r decodeStringForKey: @"name"];
    if (string != nil)
        [self setName: string];
    id compositingFilter = [r decodeObjectOfClasses: [NSSet setWithObjects: [NSString class], nil]
                                             forKey: @"compositingFilter"];
    if (compositingFilter != nil)
        [self setCompositingFilter: compositingFilter];

    if ([r decodePoint: &point forKey: @"anchorPoint"])
        _anchorPoint = point;
    if ([r decodePoint: &point forKey: @"position"])
        _position = point;
    if ([r decodeDouble: &real forKey: @"anchorPointZ"])
        _anchorPointZ = real;
    if ([r decodeDouble: &real forKey: @"zPosition"])
        _zPosition = real;
    if ([r decodeRect: &rect forKey: @"bounds"])
        _bounds = rect;
    if ([r decodeFloat: &single forKey: @"opacity"])
        _opacity = single;
    if ([r decodeBool: &flag forKey: @"opaque"])
        _opaque = flag;
    if ([r decodeDouble: &real forKey: @"contentsScale"])
        _contentsScale = real;
    if ([r decodeRect: &rect forKey: @"contentsCenter"])
        _contentsCenter = rect;
    if ([r decodeRect: &rect forKey: @"contentsRect"])
        _contentsRect = rect;
    if ([r decodeInt: &integer forKey: @"edgeAntialiasingMask"])
        _edgeAntialiasingMask = integer;
    if ([r decodeInt: &integer forKey: @"autoresizingMask"])
        _autoresizingMask = integer;
    if ([r decodeTransform: &transform forKey: @"transform"])
        _transform = transform;
    if ([r decodeTransform: &transform forKey: @"sublayerTransform"])
        _sublayerTransform = transform;
    if ([r decodeFloat: &single forKey: @"minificationFilterBias"])
        _minificationFilterBias = single;
    if ([r decodeDouble: &real forKey: @"borderWidth"])
        _borderWidth = real;
    if ([r decodeDouble: &real forKey: @"cornerRadius"])
        _cornerRadius = real;
    if ([r decodeBool: &flag forKey: @"masksToBounds"])
        _masksToBounds = flag;
    if ([r decodeFloat: &single forKey: @"shadowOpacity"])
        _shadowOpacity = single;
    if ([r decodeDouble: &real forKey: @"shadowRadius"])
        _shadowRadius = real;
    if ([r decodeSize: &size forKey: @"shadowOffset"])
        _shadowOffset = size;
    if ([r decodeBool: &flag forKey: @"hidden"])
        _hidden = flag;
    if ([r decodeBool: &flag forKey: @"geometryFlipped"])
        _geometryFlipped = flag;
    if ([r decodeBool: &flag forKey: @"doubleSided"])
        _doubleSided = flag;
    if ([r decodeBool: &flag forKey: @"shouldRasterize"])
        _shouldRasterize = flag;
    if ([r decodeDouble: &real forKey: @"rasterizationScale"])
        _rasterizationScale = real;
    if ([r decodeBool: &flag forKey: @"drawsAsynchronously"])
        _drawsAsynchronously = flag;
    if ([r decodeBool: &flag forKey: @"needsDisplayOnBoundsChange"])
        _needsDisplayOnBoundsChange = flag;

    // The copies below have no context yet, so the setters only retain or copy.
    CGColorRef color = [r copyColorForKey: @"backgroundColor"];
    if (color != NULL) {
        [self setBackgroundColor: color];
        CGColorRelease(color);
    }
    color = [r copyColorForKey: @"borderColor"];
    if (color != NULL) {
        [self setBorderColor: color];
        CGColorRelease(color);
    }
    color = [r copyColorForKey: @"shadowColor"];
    if (color != NULL) {
        [self setShadowColor: color];
        CGColorRelease(color);
    }
    CGPathRef path = [r copyPathForKey: @"shadowPath"];
    if (path != NULL) {
        [self setShadowPath: path];
        CGPathRelease(path);
    }
    id contents = [r copyContentsForKey: @"contents"];
    if (contents != nil) {
        [self setContents: contents];
        [contents release];
    }

    NSArray *array = [r decodeArrayForKey: @"filters"];
    if (array != nil)
        [self setFilters: array];
    array = [r decodeArrayForKey: @"backgroundFilters"];
    if (array != nil)
        [self setBackgroundFilters: array];
    array = [r decodeArrayForKey: @"constraints"];
    if (array != nil)
        [self setConstraints: array];
    // Any class may be a layout manager, so the archive names it; it must
    // conform to CALayoutManager and be a coding class of ours or the application's.
    id layoutManager = [r decodeObjectOfClasses: [NSSet setWithObjects: [CAConstraintLayoutManager class], nil]
                                         forKey: @"layoutManager"];
    if (layoutManager != nil)
        [self setLayoutManager: layoutManager];
    NSDictionary *dictionary = [r decodeObjectOfClasses: [NSSet setWithObjects: [NSDictionary class], [NSString class],
                                                                                [NSNumber class], [NSNull class], nil]
                                                 forKey: @"actions"];
    if ([dictionary isKindOfClass: [NSDictionary class]])
        [self setActions: dictionary];
    dictionary = [r decodeObjectOfClasses: [NSSet setWithObjects: [NSDictionary class], [NSString class],
                                                                  [NSNumber class], [NSNull class], nil]
                                   forKey: @"style"];
    if ([dictionary isKindOfClass: [NSDictionary class]])
        [self setStyle: dictionary];

    CALayer *mask = [r decodeObjectOfClasses: [NSSet setWithObject: [CALayer class]] forKey: @"mask"];
    if (mask != nil)
        [self setMask: mask];
    array = [r decodeArrayForKey: @"sublayers"];
    if (array != nil)
        [self setSublayers: array];
}

- (void) dealloc {
    for (CALayer *layer in _sublayers)
        layer->_superlayer = nil;
    [_sublayers release];
    [_name release];
    [_layoutManager release];
    [_constraints release];
    [_animations release];
    [_minificationFilter release];
    [_magnificationFilter release];
    [_contentsFormat release];
    [_contentsGravity release];
    [_cornerCurve release];
    if (_shadowPath)
        CGPathRelease(_shadowPath);
    [_mask release];
    [_filters release];
    [_compositingFilter release];
    [_backgroundFilters release];
    [_actions release];
    [_style release];
    if (_shadowColor)
        CGColorRelease(_shadowColor);
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

- (CALayerCornerCurve) cornerCurve {
    return _cornerCurve;
}

- (void) setCornerCurve: (CALayerCornerCurve) value {
    value = [value copy];
    [_cornerCurve release];
    _cornerCurve = value;
    [_context startTimerIfNeeded];
}

- (BOOL) masksToBounds {
    return _masksToBounds;
}

- (void) setMasksToBounds: (BOOL) value {
    _masksToBounds = value;
    [_context startTimerIfNeeded];
}

- (CALayer *) mask {
    return _mask;
}

- (void) setMask: (CALayer *) value {
    if (value == _mask)
        return;
    if (value == self)
        [NSException raise: NSInvalidArgumentException
                    format: @"A layer cannot mask itself"];
    [value retain];
    [_mask _setContext: nil];
    [_mask release];
    _mask = value;
    [_mask _setContext: _context];
    [_context startTimerIfNeeded];
}

- (NSArray *) filters {
    return _filters;
}

- (void) setFilters: (NSArray *) value {
    value = [value copy];
    [_filters release];
    _filters = value;
    [_context startTimerIfNeeded];
}

- (id) compositingFilter {
    return _compositingFilter;
}

- (void) setCompositingFilter: (id) value {
    [value retain];
    [_compositingFilter release];
    _compositingFilter = value;
    [_context startTimerIfNeeded];
}

- (CGColorRef) shadowColor {
    return _shadowColor;
}

- (void) setShadowColor: (CGColorRef) value {
    replaceColor(&_shadowColor, value);
    [_context startTimerIfNeeded];
}

- (float) shadowOpacity {
    return _shadowOpacity;
}

- (void) setShadowOpacity: (float) value {
    _shadowOpacity = value;
    [_context startTimerIfNeeded];
}

- (CGFloat) shadowRadius {
    return _shadowRadius;
}

- (void) setShadowRadius: (CGFloat) value {
    _shadowRadius = value;
    [_context startTimerIfNeeded];
}

- (CGSize) shadowOffset {
    return _shadowOffset;
}

- (void) setShadowOffset: (CGSize) value {
    _shadowOffset = value;
    [_context startTimerIfNeeded];
}

- (CGPathRef) shadowPath {
    return _shadowPath;
}

- (void) setShadowPath: (CGPathRef) value {
    if (_shadowPath == value)
        return;
    CGPathRef copy = value ? CGPathCreateCopy(value) : NULL;
    if (_shadowPath)
        CGPathRelease(_shadowPath);
    _shadowPath = copy;
    [_context startTimerIfNeeded];
}

- (BOOL) allowsGroupOpacity {
    return _allowsGroupOpacity;
}

- (void) setAllowsGroupOpacity: (BOOL) value {
    _allowsGroupOpacity = value;
    [_context startTimerIfNeeded];
}

- (BOOL) isHidden {
    return _hidden;
}

- (void) setHidden: (BOOL) value {
    _hidden = value;
    [_context startTimerIfNeeded];
}

- (CAAutoresizingMask) autoresizingMask {
    return _autoresizingMask;
}

- (void) setAutoresizingMask: (CAAutoresizingMask) value {
    _autoresizingMask = value;
}

- (CGFloat) zPosition {
    return _zPosition;
}

- (void) setZPosition: (CGFloat) value {
    _zPosition = value;
    [_context startTimerIfNeeded];
}

- (CGFloat) anchorPointZ {
    return _anchorPointZ;
}

- (void) setAnchorPointZ: (CGFloat) value {
    _anchorPointZ = value;
    [_context startTimerIfNeeded];
}

- (CGRect) contentsRect {
    return _contentsRect;
}

- (void) setContentsRect: (CGRect) value {
    _contentsRect = value;
    [_context startTimerIfNeeded];
}

- (float) minificationFilterBias {
    return _minificationFilterBias;
}

- (void) setMinificationFilterBias: (float) value {
    _minificationFilterBias = value;
}

- (NSArray *) backgroundFilters {
    return _backgroundFilters;
}

- (void) setBackgroundFilters: (NSArray *) value {
    value = [value copy];
    [_backgroundFilters release];
    _backgroundFilters = value;
}

- (BOOL) isDoubleSided {
    return _doubleSided;
}

- (void) setDoubleSided: (BOOL) value {
    _doubleSided = value;
}

- (BOOL) shouldRasterize {
    return _shouldRasterize;
}

- (void) setShouldRasterize: (BOOL) value {
    _shouldRasterize = value;
}

- (CGFloat) rasterizationScale {
    return _rasterizationScale;
}

- (void) setRasterizationScale: (CGFloat) value {
    _rasterizationScale = value;
}

- (BOOL) drawsAsynchronously {
    return _drawsAsynchronously;
}

- (void) setDrawsAsynchronously: (BOOL) value {
    _drawsAsynchronously = value;
}

- (NSDictionary *) actions {
    return _actions;
}

- (void) setActions: (NSDictionary *) value {
    value = [value copy];
    [_actions release];
    _actions = value;
}

- (NSDictionary *) style {
    return _style;
}

- (void) setStyle: (NSDictionary *) value {
    value = [value copy];
    [_style release];
    _style = value;
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
    [self insertSublayer: layer atIndex: (unsigned int)[_sublayers count]];
}

- (void) insertSublayer: (CALayer *) layer atIndex: (unsigned int) index {
    if (layer == nil) {
        [NSException raise: NSInvalidArgumentException
                    format: @"Cannot insert a nil sublayer"];
    }
    if (index > [_sublayers count]) {
        [NSException raise: NSRangeException
                    format: @"Sublayer index %u exceeds count %lu", index,
                            (unsigned long)[_sublayers count]];
    }
    for (CALayer *ancestor = self; ancestor != nil; ancestor = [ancestor superlayer]) {
        if (ancestor == layer) {
            [NSException raise: NSInvalidArgumentException
                        format: @"Cannot insert a layer into itself or its descendant"];
        }
    }

    // Keep the child alive if its old parent is its only owner. Removing it
    // first also prevents duplicate entries when this is an in-parent move.
    [layer retain];
    if ([layer superlayer] != nil)
        [layer removeFromSuperlayer];

    NSMutableArray *layers = [_sublayers mutableCopy];
    if (index > [layers count])
        index = (unsigned int)[layers count];
    [layers insertObject: layer atIndex: index];
    [self setSublayers: layers];
    [layers release];
    [layer release];
    [_context startTimerIfNeeded];
}

- (void) insertSublayer: (CALayer *) layer below: (CALayer *) sibling {
    [self _insertSublayer: layer nextTo: sibling above: NO];
}

- (void) insertSublayer: (CALayer *) layer above: (CALayer *) sibling {
    [self _insertSublayer: layer nextTo: sibling above: YES];
}

- (void) _insertSublayer: (CALayer *) layer
                  nextTo: (CALayer *) sibling
                   above: (BOOL) above
{
    if (layer == sibling)
        return;

    // Take the layer out first, so that the sibling's index is the one it
    // has once the layer is no longer in the array.
    [layer retain];
    if (layer != nil && [layer superlayer] == self)
        [layer removeFromSuperlayer];

    NSUInteger index = [_sublayers indexOfObjectIdenticalTo: sibling];
    if (index == NSNotFound) {
        [layer autorelease];
        [NSException raise: NSInvalidArgumentException
                    format: @"The sibling layer is not a sublayer of this layer"];
    }

    [self insertSublayer: layer atIndex: (unsigned int) (above ? index + 1 : index)];
    [layer release];
}

- (void) replaceSublayer: (CALayer *) layer with: (CALayer *) other {
    if (layer == other)
        return;
    if ([_sublayers indexOfObjectIdenticalTo: layer] == NSNotFound)
        return;
    if (other == nil) {
        [layer removeFromSuperlayer];
        return;
    }

    [other retain];
    if ([other superlayer] != nil)
        [other removeFromSuperlayer];

    NSMutableArray *layers = [_sublayers mutableCopy];
    [layers replaceObjectAtIndex: [layers indexOfObjectIdenticalTo: layer]
                      withObject: other];
    // Clears the replaced layer's superlayer and context.
    [self setSublayers: layers];
    [layers release];
    [other release];
    [_context startTimerIfNeeded];
}

// Draws the layer's content with -drawInContext: (or the delegate's
// -drawLayer:inContext:) into a bitmap the size of the bounds and makes that the
// layer's contents, which the renderer uploads as a texture. A delegate that
// implements -displayLayer: sets the contents itself instead.
- (void) display {
    if (![self _drawsOwnContent] &&
        [_delegate respondsToSelector: @selector(displayLayer:)]) {
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
    // Layer coordinates: the bounds origin is the bitmap's bottom-left corner,
    // or its top-left corner when the layer's content is flipped.
    if ([self contentsAreFlipped]) {
        CGContextTranslateCTM(context, 0, height);
        CGContextScaleCTM(context, 1, -1);
    }
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

- (void) layoutSublayers {
    if ([_delegate respondsToSelector: @selector(layoutSublayersOfLayer:)])
        [_delegate layoutSublayersOfLayer: self];
    else if ([_layoutManager respondsToSelector: @selector(layoutSublayersOfLayer:)])
        [_layoutManager layoutSublayersOfLayer: self];
}

- (void) layoutIfNeeded {
    if (_needsLayout) {
        _needsLayout = NO;
        [self layoutSublayers];
    }
    NSArray *children = [_sublayers copy];
    for (CALayer *child in children)
        [child layoutIfNeeded];
    [children release];
}

- (void) setNeedsLayout {
    _needsLayout = YES;
    [_context startTimerIfNeeded];
}

- (BOOL) needsLayout {
    return _needsLayout;
}

- (BOOL) isGeometryFlipped {
    return _geometryFlipped;
}

- (void) setGeometryFlipped: (BOOL) value {
    _geometryFlipped = value;
    [_context startTimerIfNeeded];
}

- (BOOL) contentsAreFlipped {
    BOOL flipped = NO;

    for (CALayer *layer = self; layer != nil; layer = layer->_superlayer)
        flipped ^= layer->_geometryFlipped;
    return flipped;
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

static id<CAAction> actionInStyle(NSDictionary *style, NSString *key) {
    for (; style != nil; style = [style objectForKey: @"style"]) {
        if (![style isKindOfClass: [NSDictionary class]])
            return nil;
        id actions = [style objectForKey: @"actions"];
        id action = [actions isKindOfClass: [NSDictionary class]]
                        ? [actions objectForKey: key] : nil;
        if (action != nil)
            return action;
    }
    return nil;
}

+ (id<CAAction>) defaultActionForKey: (NSString *) key {
    return nil;
}

- (id<CAAction>) actionForKey: (NSString *) key {
    id<CAAction> action = nil;

    if ([_delegate respondsToSelector: @selector(actionForLayer:forKey:)])
        action = [_delegate actionForLayer: self forKey: key];
    if (action == nil)
        action = [_actions objectForKey: key];
    if (action == nil)
        action = actionInStyle(_style, key);
    if (action == nil)
        action = [[self class] defaultActionForKey: key];
    if (action != nil)
        return [(id) action isKindOfClass: [NSNull class]] ? nil : action;

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

- (uint32_t) _textureSeed {
    return _textureSeed;
}

- (void) _setTextureSeed: (uint32_t) value {
    _textureSeed = value;
}

- (BOOL) _drawsOwnContent {
    return NO;
}

- (BOOL) _drawLayerContents: (CGRect) bounds opacity: (CGFloat) opacity {
    return NO;
}

@end

@implementation NSNull (CAActionAdditions)

- (void) runActionForKey: (NSString *) event
                  object: (id) anObject
               arguments: (NSDictionary *) dict
{
}

@end
