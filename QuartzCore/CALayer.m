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
NSString *const kCAContentsFormatAutomatic = @"Automatic";

NSString *const CADynamicRangeAutomatic = @"automatic";
NSString *const CADynamicRangeStandard = @"standard";
NSString *const CADynamicRangeConstrainedHigh = @"constrainedHigh";
NSString *const CADynamicRangeHigh = @"high";

NSString *const CAToneMapModeAutomatic = @"automatic";
NSString *const CAToneMapModeNever = @"never";
NSString *const CAToneMapModeIfSupported = @"ifSupported";

@implementation CALayer

+ layer {
    return [[[self alloc] init] autorelease];
}

- (CALayerContext *) _context {
    return NS_EXTRA(CALayer, self)->_context;
}

- (void) _setContext: (CALayerContext *) context {
    if (NS_EXTRA(CALayer, self)->_context != context) {
        [NS_EXTRA(CALayer, self)->_context deleteTextureId: NS_EXTRA(CALayer, self)->_textureId];
        [NS_EXTRA(CALayer, self)->_textureId release];
        NS_EXTRA(CALayer, self)->_textureId = nil;
    }

    NS_EXTRA(CALayer, self)->_context = context;
    [NS_EXTRA(CALayer, self)->_sublayers makeObjectsPerformSelector: @selector(_setContext:)
                                withObject: context];
    [NS_EXTRA(CALayer, self)->_mask _setContext: context];
}

- (id) _contentsForRendering: (CGRect *) rect {
    return [self contents];
}

- (CALayer *) superlayer {
    return NS_EXTRA(CALayer, self)->_superlayer;
}

- (NSArray *) sublayers {
    return NS_EXTRA(CALayer, self)->_sublayers;
}

- (void) setSublayers: (NSArray *) sublayers {
    sublayers = [sublayers copy];

    // A layer has a single superlayer, so the new sublayers leave the layers
    // they are in now.
    for (CALayer *layer in sublayers) {
        if (NS_EXTRA(CALayer, layer)->_superlayer != nil && NS_EXTRA(CALayer, layer)->_superlayer != self)
            [layer removeFromSuperlayer];
    }

    // Sublayers that are not kept stop pointing at this layer and its context
    // before the array that may own them goes away.
    for (CALayer *layer in NS_EXTRA(CALayer, self)->_sublayers) {
        if ([sublayers indexOfObjectIdenticalTo: layer] == NSNotFound) {
            NS_EXTRA(CALayer, layer)->_superlayer = nil;
            [layer _setContext: nil];
        }
    }

    [NS_EXTRA(CALayer, self)->_sublayers release];
    NS_EXTRA(CALayer, self)->_sublayers = sublayers;
    [NS_EXTRA(CALayer, self)->_sublayers makeObjectsPerformSelector: @selector(_setSuperLayer:)
                                withObject: self];
    [NS_EXTRA(CALayer, self)->_sublayers makeObjectsPerformSelector: @selector(_setContext:)
                                withObject: NS_EXTRA(CALayer, self)->_context];
    [self setNeedsLayout];
}

- (id<CALayerDelegate>) delegate {
    return NS_EXTRA(CALayer, self)->_delegate;
}

- (void) setDelegate: (id<CALayerDelegate>)value {
    NS_EXTRA(CALayer, self)->_delegate = value;
}

- (NSString *) name {
    return NS_EXTRA(CALayer, self)->_name;
}

- (void) setName: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_name release];
    NS_EXTRA(CALayer, self)->_name = value;
}

- (id<CALayoutManager>) layoutManager {
    return NS_EXTRA(CALayer, self)->_layoutManager;
}

- (void) setLayoutManager: (id<CALayoutManager>) value {
    [value retain];
    [NS_EXTRA(CALayer, self)->_layoutManager release];
    NS_EXTRA(CALayer, self)->_layoutManager = value;
    [self setNeedsLayout];
}

- (CGPoint) anchorPoint {
    return NS_EXTRA(CALayer, self)->_anchorPoint;
}

- (void) setAnchorPoint: (CGPoint) value {
    NS_EXTRA(CALayer, self)->_anchorPoint = value;
}

- (CGPoint) position {
    return NS_EXTRA(CALayer, self)->_position;
}

- (void) setPosition: (CGPoint) value {
    CAAnimation *animation = [self animationForKey: @"position"];

    if (animation == nil && ![CATransaction disableActions]) {
        id<CAAction> action = [self actionForKey: @"position"];

        [action runActionForKey: @"position" object: self arguments: nil];
    }

    NS_EXTRA(CALayer, self)->_position = value;
}

- (CGRect) bounds {
    return NS_EXTRA(CALayer, self)->_bounds;
}

- (void) setBounds: (CGRect) value {
    CAAnimation *animation = [self animationForKey: @"bounds"];

    if (animation == nil && ![CATransaction disableActions]) {
        id<CAAction> action = [self actionForKey: @"bounds"];

        [action runActionForKey: @"bounds" object: self arguments: nil];
    }

    BOOL sizeChanged = !CGSizeEqualToSize(NS_EXTRA(CALayer, self)->_bounds.size, value.size);
    NS_EXTRA(CALayer, self)->_bounds = value;
    if (sizeChanged)
        [self setNeedsLayout];
    if (sizeChanged && NS_EXTRA(CALayer, self)->_needsDisplayOnBoundsChange)
        [self setNeedsDisplay];
}

- (CGRect) frame {
    CGRect result;

    result.size = NS_EXTRA(CALayer, self)->_bounds.size;
    result.origin.x = NS_EXTRA(CALayer, self)->_position.x - result.size.width * NS_EXTRA(CALayer, self)->_anchorPoint.x;
    result.origin.y = NS_EXTRA(CALayer, self)->_position.y - result.size.height * NS_EXTRA(CALayer, self)->_anchorPoint.y;

    return result;
}

- (void) setFrame: (CGRect) value {

    CGPoint position;

    position.x = value.origin.x + value.size.width * NS_EXTRA(CALayer, self)->_anchorPoint.x;
    position.y = value.origin.y + value.size.height * NS_EXTRA(CALayer, self)->_anchorPoint.y;

    [self setPosition: position];

    CGRect bounds = NS_EXTRA(CALayer, self)->_bounds;

    bounds.size = value.size;

    [self setBounds: bounds];
}

- (CGFloat) opacity {
    return NS_EXTRA(CALayer, self)->_opacity;
}

- (void) setOpacity: (CGFloat) value {
    CAAnimation *animation = [self animationForKey: @"opacity"];

    if (animation == nil && ![CATransaction disableActions]) {
        id<CAAction> action = [self actionForKey: @"opacity"];

        [action runActionForKey: @"opacity" object: self arguments: nil];
    }

    NS_EXTRA(CALayer, self)->_opacity = value;
}

- (BOOL) isOpaque {
    return NS_EXTRA(CALayer, self)->_opaque;
}

- (void) setOpaque: (BOOL) value {
    NS_EXTRA(CALayer, self)->_opaque = value;
}

- (id) contents {
    return NS_EXTRA(CALayer, self)->_contents;
}

- (void) setContents: (id) value {
    value = [value retain];
    [NS_EXTRA(CALayer, self)->_contents release];
    NS_EXTRA(CALayer, self)->_contents = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGFloat) contentsScale {
    return NS_EXTRA(CALayer, self)->_contentsScale;
}

- (void) setContentsScale: (CGFloat) value {
    NS_EXTRA(CALayer, self)->_contentsScale = value;
}

- (CGRect) contentsCenter {
    return NS_EXTRA(CALayer, self)->_contentsCenter;
}

- (void) setContentsCenter: (CGRect) value {
    NS_EXTRA(CALayer, self)->_contentsCenter = value;
}

- (CALayerContentsFormat) contentsFormat {
    return NS_EXTRA(CALayer, self)->_contentsFormat;
}

- (void) setContentsFormat: (CALayerContentsFormat) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_contentsFormat release];
    NS_EXTRA(CALayer, self)->_contentsFormat = value;
}

- (CALayerContentsGravity) contentsGravity {
    return NS_EXTRA(CALayer, self)->_contentsGravity;
}

- (void) setContentsGravity: (CALayerContentsGravity) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_contentsGravity release];
    NS_EXTRA(CALayer, self)->_contentsGravity = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CADynamicRange) preferredDynamicRange {
    return NS_EXTRA(CALayer, self)->_preferredDynamicRange;
}

- (void) setPreferredDynamicRange: (CADynamicRange) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_preferredDynamicRange release];
    NS_EXTRA(CALayer, self)->_preferredDynamicRange = value;
}

- (CAToneMapMode) toneMapMode {
    return NS_EXTRA(CALayer, self)->_toneMapMode;
}

- (void) setToneMapMode: (CAToneMapMode) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_toneMapMode release];
    NS_EXTRA(CALayer, self)->_toneMapMode = value;
}

- (BOOL) allowsEdgeAntialiasing {
    return NS_EXTRA(CALayer, self)->_allowsEdgeAntialiasing;
}

- (void) setAllowsEdgeAntialiasing: (BOOL) value {
    NS_EXTRA(CALayer, self)->_allowsEdgeAntialiasing = value;
}

- (CAEdgeAntialiasingMask) edgeAntialiasingMask {
    return NS_EXTRA(CALayer, self)->_edgeAntialiasingMask;
}

- (void) setEdgeAntialiasingMask: (CAEdgeAntialiasingMask) value {
    NS_EXTRA(CALayer, self)->_edgeAntialiasingMask = value;
}

- (CATransform3D) transform {
    return NS_EXTRA(CALayer, self)->_transform;
}

- (void) setTransform: (CATransform3D) value {
    NS_EXTRA(CALayer, self)->_transform = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGAffineTransform) affineTransform {
    return CGAffineTransformMake(NS_EXTRA(CALayer, self)->_transform.m11, NS_EXTRA(CALayer, self)->_transform.m12,
                                 NS_EXTRA(CALayer, self)->_transform.m21, NS_EXTRA(CALayer, self)->_transform.m22,
                                 NS_EXTRA(CALayer, self)->_transform.m41, NS_EXTRA(CALayer, self)->_transform.m42);
}

- (void) setAffineTransform: (CGAffineTransform) value {
    [self setTransform: CATransform3DMakeAffineTransform(value)];
}

- (CATransform3D) sublayerTransform {
    return NS_EXTRA(CALayer, self)->_sublayerTransform;
}

- (void) setSublayerTransform: (CATransform3D) value {
    NS_EXTRA(CALayer, self)->_sublayerTransform = value;
}

- (NSString *) minificationFilter {
    return NS_EXTRA(CALayer, self)->_minificationFilter;
}

- (void) setMinificationFilter: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_minificationFilter release];
    NS_EXTRA(CALayer, self)->_minificationFilter = value;
}

- (NSString *) magnificationFilter {
    return NS_EXTRA(CALayer, self)->_magnificationFilter;
}

- (void) setMagnificationFilter: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_magnificationFilter release];
    NS_EXTRA(CALayer, self)->_magnificationFilter = value;
}

// Shared by -init and -initWithLayer:. The latter must not call -init, or a
// subclass's override of -init would run again on the copy.
- (void) _setDefaults {
    NS_EXTRA(CALayer, self)->_superlayer = nil;
    NS_EXTRA(CALayer, self)->_sublayers = [NSArray new];
    NS_EXTRA(CALayer, self)->_delegate = nil;
    NS_EXTRA(CALayer, self)->_anchorPoint = CGPointMake(0.5, 0.5);
    NS_EXTRA(CALayer, self)->_position = CGPointZero;
    NS_EXTRA(CALayer, self)->_bounds = CGRectZero;
    NS_EXTRA(CALayer, self)->_opacity = 1.0;
    NS_EXTRA(CALayer, self)->_opaque = NO;
    NS_EXTRA(CALayer, self)->_contents = nil;
    NS_EXTRA(CALayer, self)->_contentsScale = 1.0;
    // The whole contents image stretches, i.e. no fixed border.
    NS_EXTRA(CALayer, self)->_contentsCenter = CGRectMake(0, 0, 1, 1);
    NS_EXTRA(CALayer, self)->_contentsRect = CGRectMake(0, 0, 1, 1);
    NS_EXTRA(CALayer, self)->_doubleSided = YES;
    NS_EXTRA(CALayer, self)->_rasterizationScale = 1.0;
    NS_EXTRA(CALayer, self)->_contentsFormat = [kCAContentsFormatRGBA8Uint copy];
    NS_EXTRA(CALayer, self)->_contentsGravity = [kCAGravityResize copy];
    NS_EXTRA(CALayer, self)->_cornerCurve = [kCACornerCurveCircular copy];
    NS_EXTRA(CALayer, self)->_allowsGroupOpacity = YES;
    NS_EXTRA(CALayer, self)->_shadowColor = CGColorCreateGenericRGB(0, 0, 0, 1);
    NS_EXTRA(CALayer, self)->_shadowOpacity = 0;
    NS_EXTRA(CALayer, self)->_shadowRadius = 3;
    NS_EXTRA(CALayer, self)->_shadowOffset = CGSizeMake(0, -3);
    NS_EXTRA(CALayer, self)->_preferredDynamicRange = [CADynamicRangeStandard copy];
    NS_EXTRA(CALayer, self)->_toneMapMode = [CAToneMapModeAutomatic copy];
    NS_EXTRA(CALayer, self)->_allowsEdgeAntialiasing = NO;
    NS_EXTRA(CALayer, self)->_edgeAntialiasingMask = kCALayerLeftEdge | kCALayerRightEdge | kCALayerBottomEdge | kCALayerTopEdge;
    NS_EXTRA(CALayer, self)->_transform = CATransform3DIdentity;
    NS_EXTRA(CALayer, self)->_sublayerTransform = CATransform3DIdentity;
    NS_EXTRA(CALayer, self)->_minificationFilter = kCAFilterLinear;
    NS_EXTRA(CALayer, self)->_magnificationFilter = kCAFilterLinear;
    NS_EXTRA(CALayer, self)->_animations = [[NSMutableDictionary alloc] init];
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
    [w encodeBool: NS_EXTRA(CALayer, self)->_allowsEdgeAntialiasing forKey: @"allowsEdgeAntialiasing"];
    [w encodeBool: NS_EXTRA(CALayer, self)->_allowsGroupOpacity forKey: @"allowsGroupOpacity"];
    [w encodeObject: NS_EXTRA(CALayer, self)->_contentsFormat forKey: @"contentsFormat"];
    [w encodeObject: NS_EXTRA(CALayer, self)->_cornerCurve forKey: @"cornerCurve"];

    if ([NS_EXTRA(CALayer, self)->_sublayers count] > 0)
        [w encodeArray: NS_EXTRA(CALayer, self)->_sublayers forKey: @"sublayers"];
    if (NS_EXTRA(CALayer, self)->_mask != nil)
        [w encodeObject: NS_EXTRA(CALayer, self)->_mask forKey: @"mask"];
    if (NS_EXTRA(CALayer, self)->_name != nil)
        [w encodeObject: NS_EXTRA(CALayer, self)->_name forKey: @"name"];
    if (NS_EXTRA(CALayer, self)->_anchorPoint.x != 0.5 || NS_EXTRA(CALayer, self)->_anchorPoint.y != 0.5)
        [w encodePoint: NS_EXTRA(CALayer, self)->_anchorPoint forKey: @"anchorPoint"];
    if (NS_EXTRA(CALayer, self)->_anchorPointZ != 0)
        [w encodeDouble: NS_EXTRA(CALayer, self)->_anchorPointZ forKey: @"anchorPointZ"];
    if (NS_EXTRA(CALayer, self)->_position.x != 0 || NS_EXTRA(CALayer, self)->_position.y != 0)
        [w encodePoint: NS_EXTRA(CALayer, self)->_position forKey: @"position"];
    if (NS_EXTRA(CALayer, self)->_zPosition != 0)
        [w encodeDouble: NS_EXTRA(CALayer, self)->_zPosition forKey: @"zPosition"];
    if (!CGRectEqualToRect(NS_EXTRA(CALayer, self)->_bounds, CGRectZero))
        [w encodeRect: NS_EXTRA(CALayer, self)->_bounds forKey: @"bounds"];
    if (NS_EXTRA(CALayer, self)->_opacity != 1)
        [w encodeFloat: NS_EXTRA(CALayer, self)->_opacity forKey: @"opacity"];
    if (NS_EXTRA(CALayer, self)->_opaque)
        [w encodeBool: YES forKey: @"opaque"];
    if (NS_EXTRA(CALayer, self)->_contents != nil)
        [w encodeContents: NS_EXTRA(CALayer, self)->_contents forKey: @"contents"];
    if (NS_EXTRA(CALayer, self)->_contentsScale != 1)
        [w encodeDouble: NS_EXTRA(CALayer, self)->_contentsScale forKey: @"contentsScale"];
    if (!CGRectEqualToRect(NS_EXTRA(CALayer, self)->_contentsCenter, CGRectMake(0, 0, 1, 1)))
        [w encodeRect: NS_EXTRA(CALayer, self)->_contentsCenter forKey: @"contentsCenter"];
    if (!CGRectEqualToRect(NS_EXTRA(CALayer, self)->_contentsRect, CGRectMake(0, 0, 1, 1)))
        [w encodeRect: NS_EXTRA(CALayer, self)->_contentsRect forKey: @"contentsRect"];
    if (![NS_EXTRA(CALayer, self)->_contentsGravity isEqualToString: kCAGravityResize])
        [w encodeObject: NS_EXTRA(CALayer, self)->_contentsGravity forKey: @"contentsGravity"];
    if (NS_EXTRA(CALayer, self)->_shadowPath != NULL)
        [w encodePath: NS_EXTRA(CALayer, self)->_shadowPath forKey: @"shadowPath"];
    if (NS_EXTRA(CALayer, self)->_edgeAntialiasingMask != (kCALayerLeftEdge | kCALayerRightEdge | kCALayerBottomEdge | kCALayerTopEdge))
        [w encodeInt: NS_EXTRA(CALayer, self)->_edgeAntialiasingMask forKey: @"edgeAntialiasingMask"];
    if (NS_EXTRA(CALayer, self)->_autoresizingMask != 0)
        [w encodeInt: NS_EXTRA(CALayer, self)->_autoresizingMask forKey: @"autoresizingMask"];
    if (!CATransform3DIsIdentity(NS_EXTRA(CALayer, self)->_transform))
        [w encodeTransform: NS_EXTRA(CALayer, self)->_transform forKey: @"transform"];
    if (!CATransform3DIsIdentity(NS_EXTRA(CALayer, self)->_sublayerTransform))
        [w encodeTransform: NS_EXTRA(CALayer, self)->_sublayerTransform forKey: @"sublayerTransform"];
    if (![NS_EXTRA(CALayer, self)->_minificationFilter isEqualToString: kCAFilterLinear])
        [w encodeObject: NS_EXTRA(CALayer, self)->_minificationFilter forKey: @"minificationFilter"];
    if (![NS_EXTRA(CALayer, self)->_magnificationFilter isEqualToString: kCAFilterLinear])
        [w encodeObject: NS_EXTRA(CALayer, self)->_magnificationFilter forKey: @"magnificationFilter"];
    if (NS_EXTRA(CALayer, self)->_minificationFilterBias != 0)
        [w encodeFloat: NS_EXTRA(CALayer, self)->_minificationFilterBias forKey: @"minificationFilterBias"];
    if (NS_EXTRA(CALayer, self)->_backgroundColor != NULL)
        [w encodeColor: NS_EXTRA(CALayer, self)->_backgroundColor forKey: @"backgroundColor"];
    if (NS_EXTRA(CALayer, self)->_borderColor != NULL && !isOpaqueBlack(NS_EXTRA(CALayer, self)->_borderColor))
        [w encodeColor: NS_EXTRA(CALayer, self)->_borderColor forKey: @"borderColor"];
    if (NS_EXTRA(CALayer, self)->_borderWidth != 0)
        [w encodeDouble: NS_EXTRA(CALayer, self)->_borderWidth forKey: @"borderWidth"];
    if (NS_EXTRA(CALayer, self)->_cornerRadius != 0)
        [w encodeDouble: NS_EXTRA(CALayer, self)->_cornerRadius forKey: @"cornerRadius"];
    if (NS_EXTRA(CALayer, self)->_masksToBounds)
        [w encodeBool: YES forKey: @"masksToBounds"];
    if (NS_EXTRA(CALayer, self)->_filters != nil)
        [w encodeArray: NS_EXTRA(CALayer, self)->_filters forKey: @"filters"];
    if (NS_EXTRA(CALayer, self)->_backgroundFilters != nil)
        [w encodeArray: NS_EXTRA(CALayer, self)->_backgroundFilters forKey: @"backgroundFilters"];
    if (NS_EXTRA(CALayer, self)->_compositingFilter != nil)
        [w encodeObject: NS_EXTRA(CALayer, self)->_compositingFilter forKey: @"compositingFilter"];
    if (NS_EXTRA(CALayer, self)->_shadowColor != NULL && !isOpaqueBlack(NS_EXTRA(CALayer, self)->_shadowColor))
        [w encodeColor: NS_EXTRA(CALayer, self)->_shadowColor forKey: @"shadowColor"];
    if (NS_EXTRA(CALayer, self)->_shadowOpacity != 0)
        [w encodeFloat: NS_EXTRA(CALayer, self)->_shadowOpacity forKey: @"shadowOpacity"];
    if (NS_EXTRA(CALayer, self)->_shadowRadius != 3)
        [w encodeDouble: NS_EXTRA(CALayer, self)->_shadowRadius forKey: @"shadowRadius"];
    if (NS_EXTRA(CALayer, self)->_shadowOffset.width != 0 || NS_EXTRA(CALayer, self)->_shadowOffset.height != -3)
        [w encodeSize: NS_EXTRA(CALayer, self)->_shadowOffset forKey: @"shadowOffset"];
    if (NS_EXTRA(CALayer, self)->_hidden)
        [w encodeBool: YES forKey: @"hidden"];
    if (NS_EXTRA(CALayer, self)->_geometryFlipped)
        [w encodeBool: YES forKey: @"geometryFlipped"];
    if (!NS_EXTRA(CALayer, self)->_doubleSided)
        [w encodeBool: NO forKey: @"doubleSided"];
    if (NS_EXTRA(CALayer, self)->_shouldRasterize)
        [w encodeBool: YES forKey: @"shouldRasterize"];
    if (NS_EXTRA(CALayer, self)->_rasterizationScale != 1)
        [w encodeDouble: NS_EXTRA(CALayer, self)->_rasterizationScale forKey: @"rasterizationScale"];
    if (NS_EXTRA(CALayer, self)->_drawsAsynchronously)
        [w encodeBool: YES forKey: @"drawsAsynchronously"];
    if (NS_EXTRA(CALayer, self)->_needsDisplayOnBoundsChange)
        [w encodeBool: YES forKey: @"needsDisplayOnBoundsChange"];
    if (NS_EXTRA(CALayer, self)->_constraints != nil)
        [w encodeArray: NS_EXTRA(CALayer, self)->_constraints forKey: @"constraints"];
    if (NS_EXTRA(CALayer, self)->_layoutManager != nil)
        [w encodeObject: NS_EXTRA(CALayer, self)->_layoutManager forKey: @"layoutManager"];
    if (NS_EXTRA(CALayer, self)->_actions != nil)
        [w encodeObject: NS_EXTRA(CALayer, self)->_actions forKey: @"actions"];
    if (NS_EXTRA(CALayer, self)->_style != nil)
        [w encodeObject: NS_EXTRA(CALayer, self)->_style forKey: @"style"];
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
        NS_EXTRA(CALayer, self)->_allowsEdgeAntialiasing = flag;
    if ([r decodeBool: &flag forKey: @"allowsGroupOpacity"])
        NS_EXTRA(CALayer, self)->_allowsGroupOpacity = flag;
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
        NS_EXTRA(CALayer, self)->_anchorPoint = point;
    if ([r decodePoint: &point forKey: @"position"])
        NS_EXTRA(CALayer, self)->_position = point;
    if ([r decodeDouble: &real forKey: @"anchorPointZ"])
        NS_EXTRA(CALayer, self)->_anchorPointZ = real;
    if ([r decodeDouble: &real forKey: @"zPosition"])
        NS_EXTRA(CALayer, self)->_zPosition = real;
    if ([r decodeRect: &rect forKey: @"bounds"])
        NS_EXTRA(CALayer, self)->_bounds = rect;
    if ([r decodeFloat: &single forKey: @"opacity"])
        NS_EXTRA(CALayer, self)->_opacity = single;
    if ([r decodeBool: &flag forKey: @"opaque"])
        NS_EXTRA(CALayer, self)->_opaque = flag;
    if ([r decodeDouble: &real forKey: @"contentsScale"])
        NS_EXTRA(CALayer, self)->_contentsScale = real;
    if ([r decodeRect: &rect forKey: @"contentsCenter"])
        NS_EXTRA(CALayer, self)->_contentsCenter = rect;
    if ([r decodeRect: &rect forKey: @"contentsRect"])
        NS_EXTRA(CALayer, self)->_contentsRect = rect;
    if ([r decodeInt: &integer forKey: @"edgeAntialiasingMask"])
        NS_EXTRA(CALayer, self)->_edgeAntialiasingMask = integer;
    if ([r decodeInt: &integer forKey: @"autoresizingMask"])
        NS_EXTRA(CALayer, self)->_autoresizingMask = integer;
    if ([r decodeTransform: &transform forKey: @"transform"])
        NS_EXTRA(CALayer, self)->_transform = transform;
    if ([r decodeTransform: &transform forKey: @"sublayerTransform"])
        NS_EXTRA(CALayer, self)->_sublayerTransform = transform;
    if ([r decodeFloat: &single forKey: @"minificationFilterBias"])
        NS_EXTRA(CALayer, self)->_minificationFilterBias = single;
    if ([r decodeDouble: &real forKey: @"borderWidth"])
        NS_EXTRA(CALayer, self)->_borderWidth = real;
    if ([r decodeDouble: &real forKey: @"cornerRadius"])
        NS_EXTRA(CALayer, self)->_cornerRadius = real;
    if ([r decodeBool: &flag forKey: @"masksToBounds"])
        NS_EXTRA(CALayer, self)->_masksToBounds = flag;
    if ([r decodeFloat: &single forKey: @"shadowOpacity"])
        NS_EXTRA(CALayer, self)->_shadowOpacity = single;
    if ([r decodeDouble: &real forKey: @"shadowRadius"])
        NS_EXTRA(CALayer, self)->_shadowRadius = real;
    if ([r decodeSize: &size forKey: @"shadowOffset"])
        NS_EXTRA(CALayer, self)->_shadowOffset = size;
    if ([r decodeBool: &flag forKey: @"hidden"])
        NS_EXTRA(CALayer, self)->_hidden = flag;
    if ([r decodeBool: &flag forKey: @"geometryFlipped"])
        NS_EXTRA(CALayer, self)->_geometryFlipped = flag;
    if ([r decodeBool: &flag forKey: @"doubleSided"])
        NS_EXTRA(CALayer, self)->_doubleSided = flag;
    if ([r decodeBool: &flag forKey: @"shouldRasterize"])
        NS_EXTRA(CALayer, self)->_shouldRasterize = flag;
    if ([r decodeDouble: &real forKey: @"rasterizationScale"])
        NS_EXTRA(CALayer, self)->_rasterizationScale = real;
    if ([r decodeBool: &flag forKey: @"drawsAsynchronously"])
        NS_EXTRA(CALayer, self)->_drawsAsynchronously = flag;
    if ([r decodeBool: &flag forKey: @"needsDisplayOnBoundsChange"])
        NS_EXTRA(CALayer, self)->_needsDisplayOnBoundsChange = flag;

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
    for (CALayer *layer in NS_EXTRA(CALayer, self)->_sublayers)
        NS_EXTRA(CALayer, layer)->_superlayer = nil;
    [NS_EXTRA(CALayer, self)->_sublayers release];
    [NS_EXTRA(CALayer, self)->_name release];
    [NS_EXTRA(CALayer, self)->_layoutManager release];
    [NS_EXTRA(CALayer, self)->_constraints release];
    [NS_EXTRA(CALayer, self)->_animations release];
    [NS_EXTRA(CALayer, self)->_minificationFilter release];
    [NS_EXTRA(CALayer, self)->_magnificationFilter release];
    [NS_EXTRA(CALayer, self)->_contentsFormat release];
    [NS_EXTRA(CALayer, self)->_contentsGravity release];
    [NS_EXTRA(CALayer, self)->_cornerCurve release];
    if (NS_EXTRA(CALayer, self)->_shadowPath)
        CGPathRelease(NS_EXTRA(CALayer, self)->_shadowPath);
    [NS_EXTRA(CALayer, self)->_mask release];
    [NS_EXTRA(CALayer, self)->_filters release];
    [NS_EXTRA(CALayer, self)->_compositingFilter release];
    [NS_EXTRA(CALayer, self)->_backgroundFilters release];
    [NS_EXTRA(CALayer, self)->_actions release];
    [NS_EXTRA(CALayer, self)->_style release];
    if (NS_EXTRA(CALayer, self)->_shadowColor)
        CGColorRelease(NS_EXTRA(CALayer, self)->_shadowColor);
    [NS_EXTRA(CALayer, self)->_preferredDynamicRange release];
    [NS_EXTRA(CALayer, self)->_toneMapMode release];
    if (NS_EXTRA(CALayer, self)->_backgroundColor)
        CGColorRelease(NS_EXTRA(CALayer, self)->_backgroundColor);
    if (NS_EXTRA(CALayer, self)->_borderColor)
        CGColorRelease(NS_EXTRA(CALayer, self)->_borderColor);
    [NS_EXTRA(CALayer, self)->_textureContents release];
    NS_EXTRA_FREE(CALayer, self);
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
    return NS_EXTRA(CALayer, self)->_backgroundColor;
}

// Appearance changes need a new frame even when no view is redisplayed: the
// context's timer renders and presents one, then stops again once idle.
- (void) setBackgroundColor: (CGColorRef) value {
    replaceColor(&NS_EXTRA(CALayer, self)->_backgroundColor, value);
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGColorRef) borderColor {
    return NS_EXTRA(CALayer, self)->_borderColor;
}

- (void) setBorderColor: (CGColorRef) value {
    replaceColor(&NS_EXTRA(CALayer, self)->_borderColor, value);
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGFloat) borderWidth {
    return NS_EXTRA(CALayer, self)->_borderWidth;
}

- (void) setBorderWidth: (CGFloat) value {
    NS_EXTRA(CALayer, self)->_borderWidth = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGFloat) cornerRadius {
    return NS_EXTRA(CALayer, self)->_cornerRadius;
}

- (void) setCornerRadius: (CGFloat) value {
    NS_EXTRA(CALayer, self)->_cornerRadius = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CALayerCornerCurve) cornerCurve {
    return NS_EXTRA(CALayer, self)->_cornerCurve;
}

- (void) setCornerCurve: (CALayerCornerCurve) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_cornerCurve release];
    NS_EXTRA(CALayer, self)->_cornerCurve = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (BOOL) masksToBounds {
    return NS_EXTRA(CALayer, self)->_masksToBounds;
}

- (void) setMasksToBounds: (BOOL) value {
    NS_EXTRA(CALayer, self)->_masksToBounds = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CALayer *) mask {
    return NS_EXTRA(CALayer, self)->_mask;
}

- (void) setMask: (CALayer *) value {
    if (value == NS_EXTRA(CALayer, self)->_mask)
        return;
    if (value == self)
        [NSException raise: NSInvalidArgumentException
                    format: @"A layer cannot mask itself"];
    [value retain];
    [NS_EXTRA(CALayer, self)->_mask _setContext: nil];
    [NS_EXTRA(CALayer, self)->_mask release];
    NS_EXTRA(CALayer, self)->_mask = value;
    [NS_EXTRA(CALayer, self)->_mask _setContext: NS_EXTRA(CALayer, self)->_context];
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (NSArray *) filters {
    return NS_EXTRA(CALayer, self)->_filters;
}

- (void) setFilters: (NSArray *) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_filters release];
    NS_EXTRA(CALayer, self)->_filters = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (id) compositingFilter {
    return NS_EXTRA(CALayer, self)->_compositingFilter;
}

- (void) setCompositingFilter: (id) value {
    [value retain];
    [NS_EXTRA(CALayer, self)->_compositingFilter release];
    NS_EXTRA(CALayer, self)->_compositingFilter = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGColorRef) shadowColor {
    return NS_EXTRA(CALayer, self)->_shadowColor;
}

- (void) setShadowColor: (CGColorRef) value {
    replaceColor(&NS_EXTRA(CALayer, self)->_shadowColor, value);
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (float) shadowOpacity {
    return NS_EXTRA(CALayer, self)->_shadowOpacity;
}

- (void) setShadowOpacity: (float) value {
    NS_EXTRA(CALayer, self)->_shadowOpacity = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGFloat) shadowRadius {
    return NS_EXTRA(CALayer, self)->_shadowRadius;
}

- (void) setShadowRadius: (CGFloat) value {
    NS_EXTRA(CALayer, self)->_shadowRadius = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGSize) shadowOffset {
    return NS_EXTRA(CALayer, self)->_shadowOffset;
}

- (void) setShadowOffset: (CGSize) value {
    NS_EXTRA(CALayer, self)->_shadowOffset = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGPathRef) shadowPath {
    return NS_EXTRA(CALayer, self)->_shadowPath;
}

- (void) setShadowPath: (CGPathRef) value {
    if (NS_EXTRA(CALayer, self)->_shadowPath == value)
        return;
    CGPathRef copy = value ? CGPathCreateCopy(value) : NULL;
    if (NS_EXTRA(CALayer, self)->_shadowPath)
        CGPathRelease(NS_EXTRA(CALayer, self)->_shadowPath);
    NS_EXTRA(CALayer, self)->_shadowPath = copy;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (BOOL) allowsGroupOpacity {
    return NS_EXTRA(CALayer, self)->_allowsGroupOpacity;
}

- (void) setAllowsGroupOpacity: (BOOL) value {
    NS_EXTRA(CALayer, self)->_allowsGroupOpacity = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (BOOL) isHidden {
    return NS_EXTRA(CALayer, self)->_hidden;
}

- (void) setHidden: (BOOL) value {
    NS_EXTRA(CALayer, self)->_hidden = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CAAutoresizingMask) autoresizingMask {
    return NS_EXTRA(CALayer, self)->_autoresizingMask;
}

- (void) setAutoresizingMask: (CAAutoresizingMask) value {
    NS_EXTRA(CALayer, self)->_autoresizingMask = value;
}

- (CGFloat) zPosition {
    return NS_EXTRA(CALayer, self)->_zPosition;
}

- (void) setZPosition: (CGFloat) value {
    NS_EXTRA(CALayer, self)->_zPosition = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGFloat) anchorPointZ {
    return NS_EXTRA(CALayer, self)->_anchorPointZ;
}

- (void) setAnchorPointZ: (CGFloat) value {
    NS_EXTRA(CALayer, self)->_anchorPointZ = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGRect) contentsRect {
    return NS_EXTRA(CALayer, self)->_contentsRect;
}

- (void) setContentsRect: (CGRect) value {
    NS_EXTRA(CALayer, self)->_contentsRect = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (float) minificationFilterBias {
    return NS_EXTRA(CALayer, self)->_minificationFilterBias;
}

- (void) setMinificationFilterBias: (float) value {
    NS_EXTRA(CALayer, self)->_minificationFilterBias = value;
}

- (NSArray *) backgroundFilters {
    return NS_EXTRA(CALayer, self)->_backgroundFilters;
}

- (void) setBackgroundFilters: (NSArray *) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_backgroundFilters release];
    NS_EXTRA(CALayer, self)->_backgroundFilters = value;
}

- (BOOL) isDoubleSided {
    return NS_EXTRA(CALayer, self)->_doubleSided;
}

- (void) setDoubleSided: (BOOL) value {
    NS_EXTRA(CALayer, self)->_doubleSided = value;
}

- (BOOL) shouldRasterize {
    return NS_EXTRA(CALayer, self)->_shouldRasterize;
}

- (void) setShouldRasterize: (BOOL) value {
    NS_EXTRA(CALayer, self)->_shouldRasterize = value;
}

- (CGFloat) rasterizationScale {
    return NS_EXTRA(CALayer, self)->_rasterizationScale;
}

- (void) setRasterizationScale: (CGFloat) value {
    NS_EXTRA(CALayer, self)->_rasterizationScale = value;
}

- (BOOL) drawsAsynchronously {
    return NS_EXTRA(CALayer, self)->_drawsAsynchronously;
}

- (void) setDrawsAsynchronously: (BOOL) value {
    NS_EXTRA(CALayer, self)->_drawsAsynchronously = value;
}

- (NSDictionary *) actions {
    return NS_EXTRA(CALayer, self)->_actions;
}

- (void) setActions: (NSDictionary *) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_actions release];
    NS_EXTRA(CALayer, self)->_actions = value;
}

- (NSDictionary *) style {
    return NS_EXTRA(CALayer, self)->_style;
}

- (void) setStyle: (NSDictionary *) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_style release];
    NS_EXTRA(CALayer, self)->_style = value;
}

- (void) _setSuperLayer: (CALayer *) parent {
    NS_EXTRA(CALayer, self)->_superlayer = parent;
}

- (void) _removeSublayer: (CALayer *) child {
    NSMutableArray *layers = [NS_EXTRA(CALayer, self)->_sublayers mutableCopy];
    [layers removeObjectIdenticalTo: child];
    [self setSublayers: layers];
    [layers release];
}

- (void) addSublayer: (CALayer *) layer {
    [self insertSublayer: layer atIndex: (unsigned int)[NS_EXTRA(CALayer, self)->_sublayers count]];
}

- (void) insertSublayer: (CALayer *) layer atIndex: (unsigned int) index {
    if (layer == nil) {
        [NSException raise: NSInvalidArgumentException
                    format: @"Cannot insert a nil sublayer"];
    }
    if (index > [NS_EXTRA(CALayer, self)->_sublayers count]) {
        [NSException raise: NSRangeException
                    format: @"Sublayer index %u exceeds count %lu", index,
                            (unsigned long)[NS_EXTRA(CALayer, self)->_sublayers count]];
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

    NSMutableArray *layers = [NS_EXTRA(CALayer, self)->_sublayers mutableCopy];
    if (index > [layers count])
        index = (unsigned int)[layers count];
    [layers insertObject: layer atIndex: index];
    [self setSublayers: layers];
    [layers release];
    [layer release];
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
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

    NSUInteger index = [NS_EXTRA(CALayer, self)->_sublayers indexOfObjectIdenticalTo: sibling];
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
    if ([NS_EXTRA(CALayer, self)->_sublayers indexOfObjectIdenticalTo: layer] == NSNotFound)
        return;
    if (other == nil) {
        [layer removeFromSuperlayer];
        return;
    }

    [other retain];
    if ([other superlayer] != nil)
        [other removeFromSuperlayer];

    NSMutableArray *layers = [NS_EXTRA(CALayer, self)->_sublayers mutableCopy];
    [layers replaceObjectAtIndex: [layers indexOfObjectIdenticalTo: layer]
                      withObject: other];
    // Clears the replaced layer's superlayer and context.
    [self setSublayers: layers];
    [layers release];
    [other release];
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

// Draws the layer's content with -drawInContext: (or the delegate's
// -drawLayer:inContext:) into a bitmap the size of the bounds and makes that the
// layer's contents, which the renderer uploads as a texture. A delegate that
// implements -displayLayer: sets the contents itself instead.
- (void) display {
    if (![self _drawsOwnContent] &&
        [NS_EXTRA(CALayer, self)->_delegate respondsToSelector: @selector(displayLayer:)]) {
        [NS_EXTRA(CALayer, self)->_delegate displayLayer: self];
        return;
    }

    size_t width = (size_t) ceil(MAX(NS_EXTRA(CALayer, self)->_bounds.size.width, 0));
    size_t height = (size_t) ceil(MAX(NS_EXTRA(CALayer, self)->_bounds.size.height, 0));
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
    CGContextTranslateCTM(context, -NS_EXTRA(CALayer, self)->_bounds.origin.x, -NS_EXTRA(CALayer, self)->_bounds.origin.y);
    [self drawInContext: context];

    CGImageRef image = CGBitmapContextCreateImage(context);
    [self setContents: (id) image];
    if (image != NULL)
        CGImageRelease(image);
    CGContextRelease(context);
}

- (void) displayIfNeeded {
    if (NS_EXTRA(CALayer, self)->_needsDisplay) {
        NS_EXTRA(CALayer, self)->_needsDisplay = NO;
        [self display];
    }
}

- (void) layoutSublayers {
    if ([NS_EXTRA(CALayer, self)->_delegate respondsToSelector: @selector(layoutSublayersOfLayer:)])
        [NS_EXTRA(CALayer, self)->_delegate layoutSublayersOfLayer: self];
    else if ([NS_EXTRA(CALayer, self)->_layoutManager respondsToSelector: @selector(layoutSublayersOfLayer:)])
        [NS_EXTRA(CALayer, self)->_layoutManager layoutSublayersOfLayer: self];
}

- (void) layoutIfNeeded {
    if (NS_EXTRA(CALayer, self)->_needsLayout) {
        NS_EXTRA(CALayer, self)->_needsLayout = NO;
        [self layoutSublayers];
    }
    NSArray *children = [NS_EXTRA(CALayer, self)->_sublayers copy];
    for (CALayer *child in children)
        [child layoutIfNeeded];
    [children release];
}

- (void) setNeedsLayout {
    NS_EXTRA(CALayer, self)->_needsLayout = YES;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (BOOL) needsLayout {
    return NS_EXTRA(CALayer, self)->_needsLayout;
}

- (BOOL) isGeometryFlipped {
    return NS_EXTRA(CALayer, self)->_geometryFlipped;
}

- (void) setGeometryFlipped: (BOOL) value {
    NS_EXTRA(CALayer, self)->_geometryFlipped = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (BOOL) contentsAreFlipped {
    BOOL flipped = NO;

    for (CALayer *layer = self; layer != nil; layer = NS_EXTRA(CALayer, layer)->_superlayer)
        flipped ^= NS_EXTRA(CALayer, layer)->_geometryFlipped;
    return flipped;
}

- (BOOL) needsDisplayOnBoundsChange {
    return NS_EXTRA(CALayer, self)->_needsDisplayOnBoundsChange;
}

- (void) setNeedsDisplayOnBoundsChange: (BOOL) value {
    NS_EXTRA(CALayer, self)->_needsDisplayOnBoundsChange = value;
}

- (void) drawInContext: (CGContextRef) context {
    if ([NS_EXTRA(CALayer, self)->_delegate respondsToSelector: @selector(drawLayer:inContext:)])
        [NS_EXTRA(CALayer, self)->_delegate drawLayer: self inContext: context];
}

- (BOOL) needsDisplay {
    return NS_EXTRA(CALayer, self)->_needsDisplay;
}

- (void) removeFromSuperlayer {
    [NS_EXTRA(CALayer, self)->_superlayer _removeSublayer: self];
    NS_EXTRA(CALayer, self)->_superlayer = nil;
    [self _setContext: nil];
}

- (void) setNeedsDisplay {
    NS_EXTRA(CALayer, self)->_needsDisplay = YES;
    // Get a frame rendered: the context's timer renders, presents, and stops
    // again once no animations are running.
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (void) setNeedsDisplayInRect: (CGRect) rect {
    [self setNeedsDisplay];
}

- (void) addAnimation: (CAAnimation *) animation forKey: (NSString *) key {
    // The animation is recorded for any layer, also one that is not part of a
    // hosted layer tree; the context, if there is one, starts driving it.
    [NS_EXTRA(CALayer, self)->_animations setObject: animation forKey: key];
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CAAnimation *) animationForKey: (NSString *) key {
    return [NS_EXTRA(CALayer, self)->_animations objectForKey: key];
}

- (void) removeAllAnimations {
    [NS_EXTRA(CALayer, self)->_animations removeAllObjects];
}

- (void) removeAnimationForKey: (NSString *) key {
    [NS_EXTRA(CALayer, self)->_animations removeObjectForKey: key];
}

- (NSArray *) animationKeys {
    return [NS_EXTRA(CALayer, self)->_animations allKeys];
}

- valueForKey: (NSString *) key {
    // FIXME: KVC appears broken for structs

    if ([key isEqualToString: @"bounds"])
        return [NSValue valueWithRect: NS_EXTRA(CALayer, self)->_bounds];
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

    if ([NS_EXTRA(CALayer, self)->_delegate respondsToSelector: @selector(actionForLayer:forKey:)])
        action = [NS_EXTRA(CALayer, self)->_delegate actionForLayer: self forKey: key];
    if (action == nil)
        action = [NS_EXTRA(CALayer, self)->_actions objectForKey: key];
    if (action == nil)
        action = actionInStyle(NS_EXTRA(CALayer, self)->_style, key);
    if (action == nil)
        action = [[self class] defaultActionForKey: key];
    if (action != nil)
        return [(id) action isKindOfClass: [NSNull class]] ? nil : action;

    // QUIRK: the implicit action for a property change exists only while the
    // layer belongs to a layer tree hosted by a window (it has a layer
    // context). A layer outside such a tree returns nil, with or without an
    // explicitly begun transaction, so its property changes never animate.
    // The documentation does not say when implicit actions apply. Evidence:
    // black-box observation on macOS 26.7.3 (tier 2): a standalone layer, a
    // sublayer of a standalone root and an off-window view's backing layer
    // return nil from -actionForKey: and gain no animation keys, while a
    // sublayer in a window-hosted tree gets an implicit action. macOS 10.14.4
    // behaves the same.
    // Test: quartzcore-implicit-actions (standalone and window-hosted cases).
    if (NS_EXTRA(CALayer, self)->_context == nil)
        return nil;

    CABasicAnimation *basic = [CABasicAnimation animationWithKeyPath: key];

    [basic setFromValue: [self valueForKey: key]];

    return basic;
}

- (NSNumber *) _textureId {
    return NS_EXTRA(CALayer, self)->_textureId;
}

- (void) _setTextureId: (NSNumber *) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_textureId release];
    NS_EXTRA(CALayer, self)->_textureId = value;
}

- (id) _textureContents {
    return NS_EXTRA(CALayer, self)->_textureContents;
}

- (void) _setTextureContents: (id) value {
    value = [value retain];
    [NS_EXTRA(CALayer, self)->_textureContents release];
    NS_EXTRA(CALayer, self)->_textureContents = value;
}

- (uint32_t) _textureSeed {
    return NS_EXTRA(CALayer, self)->_textureSeed;
}

- (void) _setTextureSeed: (uint32_t) value {
    NS_EXTRA(CALayer, self)->_textureSeed = value;
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
