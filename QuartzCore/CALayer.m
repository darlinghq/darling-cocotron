#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <objc/runtime.h>
#import <QuartzCore/CAAnimation.h>
#import <QuartzCore/CAConstraintLayoutManager.h>
#import <QuartzCore/CALayer.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CAScrollLayer.h>
#import <QuartzCore/CATransaction.h>
#import <IOSurface/IOSurface.h>
#import <Onyx2D/O2Image.h>
#import "CAKeyedCoding.h"
#import <QuartzCore/CATransactionPrivate.h>
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

+ (instancetype) layer {
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

// _sublayers is never nil, so the mutators can copy it; the public getter
// reports a layer without sublayers as nil, as macOS does.
- (NSArray *) sublayers {
    NSArray *sublayers = NS_EXTRA(CALayer, self)->_sublayers;
    return [sublayers count] > 0 ? sublayers : nil;
}

- (void) setSublayers: (NSArray *) sublayers {
    sublayers = sublayers != nil ? [sublayers copy] : [NSArray new];

    // The same layers in the same order change nothing.
    if ([sublayers isEqualToArray: NS_EXTRA(CALayer, self)->_sublayers]) {
        [sublayers release];
        return;
    }

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
    // QUIRK: setting an animatable property to the value it has changes
    // nothing: the delegate and the layer's actions are not asked and no
    // implicit animation is added. Not documented. Evidence: black-box
    // observation on macOS 26.7.3 (tier 2): in a window-hosted layer tree,
    // position, bounds, opacity, cornerRadius, transform and hidden set to
    // their current values gave no -actionForLayer:forKey: call and no animation
    // key, while a different value gave one call and one animation key. On
    // macOS 10.14.4 (no window server, so no hosted tree and no animation
    // keys): same values gave no -actionForLayer:forKey: call, different
    // values gave one.
    // Test: tests/quartzcore-layer-idle-frames.m (same-value cases).
    if (CGPointEqualToPoint(NS_EXTRA(CALayer, self)->_position, value))
        return;

    CAAnimation *animation = [self animationForKey: @"position"];

    [CATransaction _openImplicitTransactionIfNeeded];
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
    // QUIRK: as in -setPosition:, nothing happens for the value it has.
    if (CGRectEqualToRect(NS_EXTRA(CALayer, self)->_bounds, value))
        return;

    CAAnimation *animation = [self animationForKey: @"bounds"];

    [CATransaction _openImplicitTransactionIfNeeded];
    if (animation == nil && ![CATransaction disableActions]) {
        id<CAAction> action = [self actionForKey: @"bounds"];

        [action runActionForKey: @"bounds" object: self arguments: nil];
    }

    CGRect oldBounds = NS_EXTRA(CALayer, self)->_bounds;
    BOOL sizeChanged = !CGSizeEqualToSize(oldBounds.size, value.size);
    NS_EXTRA(CALayer, self)->_bounds = value;
    if (sizeChanged)
        [self setNeedsLayout];
    if (sizeChanged && NS_EXTRA(CALayer, self)->_needsDisplayOnBoundsChange)
        [self setNeedsDisplay];
    // Any change of the bounds rectangle, an origin-only one included, informs
    // the sublayers; the sublayers apply their autoresizing masks synchronously.
    if (!CGRectEqualToRect(oldBounds, value))
        [self resizeSublayersWithOldSize: oldBounds.size];
}

// Splits the change of a superlayer's extent along one axis between the parts of
// a sublayer that its mask makes flexible. Returns the new origin and length.
static void CALayerAutoresizeAxis(CGFloat *origin, CGFloat *length, CGFloat delta, BOOL minMargin, BOOL sizable, BOOL maxMargin) {
    int margins = (minMargin ? 1 : 0) + (maxMargin ? 1 : 0);
    CGFloat sizeShare = 0, marginShare = 0;

    if (sizable) {
        // QUIRK: a flexible size takes a third of the change when a margin is
        // flexible too, and the flexible margins share the rest equally,
        // whatever the current sizes of the parts (unlike NSView's proportional
        // split). Not documented. Evidence: black-box observation on macOS 26.7.3
        // (tier 2). Test: tests/src/quartzcore_autoresizing.m (split cases).
        sizeShare = margins > 0 ? delta / 3 : delta;
        if (margins > 0)
            marginShare = (delta - sizeShare) / margins;
    } else if (margins > 0) {
        marginShare = delta / margins;
    }
    if (minMargin)
        *origin += marginShare;
    *length += sizeShare;
}

- (void) resizeSublayersWithOldSize: (CGSize) size {
    NSArray *children = [NS_EXTRA(CALayer, self)->_sublayers copy];

    for (CALayer *child in [children reverseObjectEnumerator])
        [child resizeWithOldSuperlayerSize: size];
    [children release];
}

- (void) resizeWithOldSuperlayerSize: (CGSize) size {
    CAAutoresizingMask mask = NS_EXTRA(CALayer, self)->_autoresizingMask;
    CALayer *superlayer = NS_EXTRA(CALayer, self)->_superlayer;

    if (mask == kCALayerNotSizable || superlayer == nil)
        return;

    CGSize newSize = [superlayer bounds].size;
    CGRect frame = [self frame];

    CALayerAutoresizeAxis(&frame.origin.x, &frame.size.width, newSize.width - size.width,
                          (mask & kCALayerMinXMargin) != 0, (mask & kCALayerWidthSizable) != 0, (mask & kCALayerMaxXMargin) != 0);
    CALayerAutoresizeAxis(&frame.origin.y, &frame.size.height, newSize.height - size.height,
                          (mask & kCALayerMinYMargin) != 0, (mask & kCALayerHeightSizable) != 0, (mask & kCALayerMaxYMargin) != 0);

    // QUIRK: the result is a whole-number rectangle: the origin rounds down and
    // the far edges round up, and a negative extent is flipped to a positive one.
    // Not documented. Evidence: black-box observation on macOS 26.7.3 (tier 2).
    // Test: tests/src/quartzcore_autoresizing.m (rounding cases).
    frame = CGRectStandardize(frame);
    CGFloat minX = floor(CGRectGetMinX(frame)), minY = floor(CGRectGetMinY(frame));
    CGFloat maxX = ceil(CGRectGetMaxX(frame)), maxY = ceil(CGRectGetMaxY(frame));
    frame = CGRectMake(minX, minY, maxX - minX, maxY - minY);

    if (!CGRectEqualToRect(frame, [self frame]))
        [self setFrame: frame];
}

// Maps a corner of the layer, given relative to the anchor point, through the
// layer's transform to the superlayer's coordinates; the 3D result is
// projected to the plane.
static CGPoint CALayerTransformedCorner(CATransform3D t, CGFloat x, CGFloat y, CGFloat z, CGPoint position) {
    CGFloat w = x * t.m14 + y * t.m24 + z * t.m34 + t.m44;
    CGFloat px = x * t.m11 + y * t.m21 + z * t.m31 + t.m41;
    CGFloat py = x * t.m12 + y * t.m22 + z * t.m32 + t.m42;

    if (w != 0 && w != 1) {
        px /= w;
        py /= w;
    }
    return CGPointMake(position.x + px, position.y + py);
}

// Whether a transform has no part in the third dimension or the perspective.
// Rotations built by CATransform3DMakeRotation leave rounding residue (float on
// 32-bit) in these entries, so they are compared with a tolerance.
static BOOL CALayerTransformIsAffine(CATransform3D t) {
    const CGFloat eps = 1e-6;

    return fabs(t.m13) < eps && fabs(t.m14) < eps && fabs(t.m23) < eps && fabs(t.m24) < eps &&
           fabs(t.m31) < eps && fabs(t.m32) < eps && fabs(t.m34) < eps && fabs(t.m43) < eps &&
           fabs(t.m33 - 1) < eps && fabs(t.m44 - 1) < eps;
}

- (CGRect) frame {
    CGRect bounds = NS_EXTRA(CALayer, self)->_bounds;
    CGPoint anchor = NS_EXTRA(CALayer, self)->_anchorPoint;
    CGPoint position = NS_EXTRA(CALayer, self)->_position;
    CATransform3D t = NS_EXTRA(CALayer, self)->_transform;
    CGRect result;

    if (CATransform3DIsIdentity(t)) {
        result.size = bounds.size;
        result.origin.x = position.x - result.size.width * anchor.x;
        result.origin.y = position.y - result.size.height * anchor.y;
        return result;
    }

    // The frame of a transformed layer is the bounding box of its transformed
    // bounds, in the superlayer's coordinates. The bounds origin does not take
    // part: the corners are the bounds size, relative to the anchor point.
    CGFloat z = -NS_EXTRA(CALayer, self)->_anchorPointZ;
    CGFloat left = -bounds.size.width * anchor.x, top = -bounds.size.height * anchor.y;
    CGPoint corners[4] = {
        CALayerTransformedCorner(t, left, top, z, position),
        CALayerTransformedCorner(t, left + bounds.size.width, top, z, position),
        CALayerTransformedCorner(t, left, top + bounds.size.height, z, position),
        CALayerTransformedCorner(t, left + bounds.size.width, top + bounds.size.height, z, position),
    };
    CGFloat minX = corners[0].x, maxX = corners[0].x, minY = corners[0].y, maxY = corners[0].y;

    for (int i = 1; i < 4; i++) {
        minX = MIN(minX, corners[i].x);
        maxX = MAX(maxX, corners[i].x);
        minY = MIN(minY, corners[i].y);
        maxY = MAX(maxY, corners[i].y);
    }
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

- (void) setFrame: (CGRect) value {
    CGPoint anchor = NS_EXTRA(CALayer, self)->_anchorPoint;
    CATransform3D t = NS_EXTRA(CALayer, self)->_transform;
    CGSize size = value.size;

    // QUIRK: with a transform, setting the frame is documented as undefined.
    // Observed: the bounds size becomes the frame size taken through the
    // inverse of the transform's 2x2 part, with the sign dropped, when the
    // transform is affine and invertible (a non-affine transform keeps the
    // frame size as is); the position is the frame origin plus the anchor
    // point's share of the frame size, less the transform's translation; the
    // bounds origin stays. The resulting frame is therefore not always the one that
    // was set (a rotation keeps its size but not its extent). Evidence:
    // black-box observation on macOS 26.7.3 (tier 2), probes in
    // vd-upstream/mac-probes/calayer-transformed-frame. A singular affine
    // transform was seen once (bounds width 0) and is left to keep the
    // bounds size here.
    // Test: tests/src/quartzcore_transformed_frame.m (setFrame cases).
    if (!CATransform3DIsIdentity(t)) {
        if (CALayerTransformIsAffine(t)) {
            CGFloat det = t.m11 * t.m22 - t.m12 * t.m21;

            if (det != 0) {
                size.width = fabs((value.size.width * t.m22 - value.size.height * t.m21) / det);
                size.height = fabs((value.size.height * t.m11 - value.size.width * t.m12) / det);
            } else {
                size = NS_EXTRA(CALayer, self)->_bounds.size;
            }
        }
    }

    CGPoint position;

    position.x = value.origin.x + value.size.width * anchor.x - t.m41;
    position.y = value.origin.y + value.size.height * anchor.y - t.m42;

    [self setPosition: position];

    CGRect bounds = NS_EXTRA(CALayer, self)->_bounds;

    bounds.size = size;

    [self setBounds: bounds];
}

- (float) opacity {
    return NS_EXTRA(CALayer, self)->_opacity;
}

- (void) setOpacity: (float) value {
    // QUIRK: as in -setPosition:, nothing happens for the value it has.
    if (NS_EXTRA(CALayer, self)->_opacity == value)
        return;

    CAAnimation *animation = [self animationForKey: @"opacity"];

    [CATransaction _openImplicitTransactionIfNeeded];
    if (animation == nil && ![CATransaction disableActions]) {
        id<CAAction> action = [self actionForKey: @"opacity"];

        [action runActionForKey: @"opacity" object: self arguments: nil];
    }

    NS_EXTRA(CALayer, self)->_opacity = value;
}

- (BOOL) isOpaque {
    return NS_EXTRA(CALayer, self)->_opaque;
}

// SPI. Whether the layer's contents are known to be fully opaque, a hint kept apart from
// opaque. Observed on macOS 26.7.3: NO by default, independent of opaque in both directions,
// readable through key-value coding, and without an implicit action. Darling's renderer does
// not use the hint. Test: tests/quartzcore-contents-opaque.m.
- (BOOL) contentsOpaque {
    return NS_EXTRA(CALayer, self)->_contentsOpaque;
}

- (void) setContentsOpaque: (BOOL) value {
    NS_EXTRA(CALayer, self)->_contentsOpaque = value;
}

- (void) setOpaque: (BOOL) value {
    NS_EXTRA(CALayer, self)->_opaque = value;
}

// Setting a property to the value it already has changes nothing on screen,
// so it must not ask for a frame.
static BOOL colorsEqual(CGColorRef a, CGColorRef b) {
    return a == b || (a != NULL && b != NULL && CGColorEqualToColor(a, b));
}

static BOOL valuesEqual(id a, id b) {
    return a == b || [a isEqual: b];
}

- (id) contents {
    return NS_EXTRA(CALayer, self)->_contents;
}

// Whether setting the contents to value, which the layer already has, leaves
// what is drawn as it is. The renderer draws the same image object without
// uploading it again, and a surface whose pixels were not written to since
// they were last uploaded.
static BOOL contentsUnchanged(CALayer *layer, id value) {
    if (value != [layer contents])
        return NO;
    if (value == nil)
        return YES;
    if (CFGetTypeID((CFTypeRef) value) != IOSurfaceGetTypeID())
        return YES;
    return [layer _textureContents] == value &&
           IOSurfaceGetSeed((IOSurfaceRef) value) == [layer _textureSeed];
}

- (void) setContents: (id) value {
    if (contentsUnchanged(self, value))
        return;
    value = [value retain];
    [NS_EXTRA(CALayer, self)->_contents release];
    NS_EXTRA(CALayer, self)->_contents = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGFloat) contentsScale {
    return NS_EXTRA(CALayer, self)->_contentsScale;
}

- (void) setContentsScale: (CGFloat) value {
    if (NS_EXTRA(CALayer, self)->_contentsScale == value)
        return;
    NS_EXTRA(CALayer, self)->_contentsScale = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGRect) contentsCenter {
    return NS_EXTRA(CALayer, self)->_contentsCenter;
}

- (void) setContentsCenter: (CGRect) value {
    if (CGRectEqualToRect(NS_EXTRA(CALayer, self)->_contentsCenter, value))
        return;
    NS_EXTRA(CALayer, self)->_contentsCenter = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
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
    if (valuesEqual(NS_EXTRA(CALayer, self)->_contentsGravity, value))
        return;
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
    if (CATransform3DEqualToTransform(NS_EXTRA(CALayer, self)->_transform, value))
        return;
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
    if (CATransform3DEqualToTransform(NS_EXTRA(CALayer, self)->_sublayerTransform, value))
        return;
    NS_EXTRA(CALayer, self)->_sublayerTransform = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
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
    NS_EXTRA(CALayer, self)->_maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
                                              kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
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
    NS_EXTRA(CALayer, self)->_speed = 1;
    NS_EXTRA(CALayer, self)->_fillMode = [kCAFillModeRemoved copy];
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
    [NS_EXTRA(CALayer, self)->_fillMode release];
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
    [NS_EXTRA(CALayer, self)->_contents release];
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
    if (colorsEqual(NS_EXTRA(CALayer, self)->_backgroundColor, value))
        return;
    replaceColor(&NS_EXTRA(CALayer, self)->_backgroundColor, value);
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGColorRef) borderColor {
    return NS_EXTRA(CALayer, self)->_borderColor;
}

- (void) setBorderColor: (CGColorRef) value {
    if (colorsEqual(NS_EXTRA(CALayer, self)->_borderColor, value))
        return;
    replaceColor(&NS_EXTRA(CALayer, self)->_borderColor, value);
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGFloat) borderWidth {
    return NS_EXTRA(CALayer, self)->_borderWidth;
}

- (void) setBorderWidth: (CGFloat) value {
    if (NS_EXTRA(CALayer, self)->_borderWidth == value)
        return;
    NS_EXTRA(CALayer, self)->_borderWidth = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGFloat) cornerRadius {
    return NS_EXTRA(CALayer, self)->_cornerRadius;
}

- (void) setCornerRadius: (CGFloat) value {
    if (NS_EXTRA(CALayer, self)->_cornerRadius == value)
        return;
    NS_EXTRA(CALayer, self)->_cornerRadius = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CALayerCornerCurve) cornerCurve {
    return NS_EXTRA(CALayer, self)->_cornerCurve;
}

- (void) setCornerCurve: (CALayerCornerCurve) value {
    if (valuesEqual(NS_EXTRA(CALayer, self)->_cornerCurve, value))
        return;
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_cornerCurve release];
    NS_EXTRA(CALayer, self)->_cornerCurve = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CACornerMask) maskedCorners {
    return NS_EXTRA(CALayer, self)->_maskedCorners;
}

- (void) setMaskedCorners: (CACornerMask) value {
    if (NS_EXTRA(CALayer, self)->_maskedCorners == value)
        return;
    NS_EXTRA(CALayer, self)->_maskedCorners = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (BOOL) masksToBounds {
    return NS_EXTRA(CALayer, self)->_masksToBounds;
}

- (void) setMasksToBounds: (BOOL) value {
    if (NS_EXTRA(CALayer, self)->_masksToBounds == value)
        return;
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
    if (valuesEqual(NS_EXTRA(CALayer, self)->_filters, value))
        return;
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_filters release];
    NS_EXTRA(CALayer, self)->_filters = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (id) compositingFilter {
    return NS_EXTRA(CALayer, self)->_compositingFilter;
}

- (void) setCompositingFilter: (id) value {
    if (valuesEqual(NS_EXTRA(CALayer, self)->_compositingFilter, value))
        return;
    [value retain];
    [NS_EXTRA(CALayer, self)->_compositingFilter release];
    NS_EXTRA(CALayer, self)->_compositingFilter = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGColorRef) shadowColor {
    return NS_EXTRA(CALayer, self)->_shadowColor;
}

- (void) setShadowColor: (CGColorRef) value {
    if (colorsEqual(NS_EXTRA(CALayer, self)->_shadowColor, value))
        return;
    replaceColor(&NS_EXTRA(CALayer, self)->_shadowColor, value);
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (float) shadowOpacity {
    return NS_EXTRA(CALayer, self)->_shadowOpacity;
}

- (void) setShadowOpacity: (float) value {
    if (NS_EXTRA(CALayer, self)->_shadowOpacity == value)
        return;
    NS_EXTRA(CALayer, self)->_shadowOpacity = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGFloat) shadowRadius {
    return NS_EXTRA(CALayer, self)->_shadowRadius;
}

- (void) setShadowRadius: (CGFloat) value {
    if (NS_EXTRA(CALayer, self)->_shadowRadius == value)
        return;
    NS_EXTRA(CALayer, self)->_shadowRadius = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGSize) shadowOffset {
    return NS_EXTRA(CALayer, self)->_shadowOffset;
}

- (void) setShadowOffset: (CGSize) value {
    if (CGSizeEqualToSize(NS_EXTRA(CALayer, self)->_shadowOffset, value))
        return;
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
    if (NS_EXTRA(CALayer, self)->_allowsGroupOpacity == value)
        return;
    NS_EXTRA(CALayer, self)->_allowsGroupOpacity = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (BOOL) isHidden {
    return NS_EXTRA(CALayer, self)->_hidden;
}

- (void) setHidden: (BOOL) value {
    if (NS_EXTRA(CALayer, self)->_hidden == value)
        return;
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
    if (NS_EXTRA(CALayer, self)->_zPosition == value)
        return;
    NS_EXTRA(CALayer, self)->_zPosition = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGFloat) anchorPointZ {
    return NS_EXTRA(CALayer, self)->_anchorPointZ;
}

- (void) setAnchorPointZ: (CGFloat) value {
    if (NS_EXTRA(CALayer, self)->_anchorPointZ == value)
        return;
    NS_EXTRA(CALayer, self)->_anchorPointZ = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (CGRect) contentsRect {
    return NS_EXTRA(CALayer, self)->_contentsRect;
}

- (void) setContentsRect: (CGRect) value {
    if (CGRectEqualToRect(NS_EXTRA(CALayer, self)->_contentsRect, value))
        return;
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
    if (NS_EXTRA(CALayer, self)->_geometryFlipped == value)
        return;
    NS_EXTRA(CALayer, self)->_geometryFlipped = value;
    [NS_EXTRA(CALayer, self)->_context startTimerIfNeeded];
}

- (BOOL) contentsAreFlipped {
    BOOL flipped = NO;

    for (CALayer *layer = self; layer != nil; layer = NS_EXTRA(CALayer, layer)->_superlayer)
        flipped ^= NS_EXTRA(CALayer, layer)->_geometryFlipped;
    return flipped;
}

// Maps the layer's coordinates to those of its superlayer, after the
// superlayer's sublayerTransform, or, for a layer without one, to the space
// the layer is placed in. This is the geometry CARenderer draws with:
// - the bounds origin is removed and a geometryFlipped layer is flipped
//   within its bounds;
// - the anchor point goes to the position, through the layer's transform;
// - the superlayer's sublayerTransform applies about its anchor point, in
//   its own coordinates.
static CATransform3D layerToSuperlayerTransform(CALayer *layer) {
    CGRect bounds = NS_EXTRA(CALayer, layer)->_bounds;
    CGPoint anchor = NS_EXTRA(CALayer, layer)->_anchorPoint;
    CGPoint position = NS_EXTRA(CALayer, layer)->_position;
    CATransform3D m = CATransform3DMakeTranslation(-bounds.origin.x, -bounds.origin.y, 0);

    if (NS_EXTRA(CALayer, layer)->_geometryFlipped) {
        m = CATransform3DConcat(m, CATransform3DMakeScale(1, -1, 1));
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(0, bounds.size.height, 0));
    }
    m = CATransform3DConcat(m, CATransform3DMakeTranslation(-bounds.size.width * anchor.x,
                                                            -bounds.size.height * anchor.y, 0));
    m = CATransform3DConcat(m, NS_EXTRA(CALayer, layer)->_transform);
    m = CATransform3DConcat(m, CATransform3DMakeTranslation(position.x, position.y, 0));

    CALayer *superlayer = NS_EXTRA(CALayer, layer)->_superlayer;
    if (superlayer != nil) {
        CATransform3D sublayerTransform = NS_EXTRA(CALayer, superlayer)->_sublayerTransform;
        if (!CATransform3DIsIdentity(sublayerTransform)) {
            CGRect superBounds = NS_EXTRA(CALayer, superlayer)->_bounds;
            CGPoint superAnchor = NS_EXTRA(CALayer, superlayer)->_anchorPoint;
            CGFloat ax = superBounds.origin.x + superBounds.size.width * superAnchor.x;
            CGFloat ay = superBounds.origin.y + superBounds.size.height * superAnchor.y;
            m = CATransform3DConcat(m, CATransform3DMakeTranslation(-ax, -ay, 0));
            m = CATransform3DConcat(m, sublayerTransform);
            m = CATransform3DConcat(m, CATransform3DMakeTranslation(ax, ay, 0));
        }
    }
    return m;
}

// Maps the layer's coordinates to the space its tree's root layer is placed
// in. A nil layer stands for that space.
static CATransform3D layerToTreeSpaceTransform(CALayer *layer) {
    CATransform3D m = CATransform3DIdentity;
    for (; layer != nil; layer = NS_EXTRA(CALayer, layer)->_superlayer)
        m = CATransform3DConcat(m, layerToSuperlayerTransform(layer));
    return m;
}

// The transform from the coordinates of one layer to another's. Layers of
// different trees are related through the space their roots are placed in.
static CATransform3D transformBetweenLayers(CALayer *from, CALayer *to) {
    return CATransform3DConcat(layerToTreeSpaceTransform(from),
                               CATransform3DInvert(layerToTreeSpaceTransform(to)));
}

static CGPoint applyToPoint(CATransform3D m, CGPoint p) {
    CGFloat w = p.x * m.m14 + p.y * m.m24 + m.m44;
    CGFloat x = p.x * m.m11 + p.y * m.m21 + m.m41;
    CGFloat y = p.x * m.m12 + p.y * m.m22 + m.m42;
    if (w != 0 && w != 1) {
        x /= w;
        y /= w;
    }
    return CGPointMake(x, y);
}

// The bounding box of the rect's corners.
static CGRect applyToRect(CATransform3D m, CGRect rect) {
    if (CGRectIsNull(rect))
        return rect;
    CGPoint corners[4] = {
        applyToPoint(m, CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect))),
        applyToPoint(m, CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect))),
        applyToPoint(m, CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect))),
        applyToPoint(m, CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect))),
    };
    CGFloat minX = corners[0].x, maxX = corners[0].x;
    CGFloat minY = corners[0].y, maxY = corners[0].y;
    for (int i = 1; i < 4; i++) {
        minX = MIN(minX, corners[i].x);
        maxX = MAX(maxX, corners[i].x);
        minY = MIN(minY, corners[i].y);
        maxY = MAX(maxY, corners[i].y);
    }
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

- (CGPoint) convertPoint: (CGPoint) point fromLayer: (CALayer *) layer {
    return applyToPoint(transformBetweenLayers(layer, self), point);
}

- (CGPoint) convertPoint: (CGPoint) point toLayer: (CALayer *) layer {
    return applyToPoint(transformBetweenLayers(self, layer), point);
}

- (CGRect) convertRect: (CGRect) rect fromLayer: (CALayer *) layer {
    return applyToRect(transformBetweenLayers(layer, self), rect);
}

- (CGRect) convertRect: (CGRect) rect toLayer: (CALayer *) layer {
    return applyToRect(transformBetweenLayers(self, layer), rect);
}
// CAMediaTiming: a layer's local time is (parent time - beginTime) * speed +
// timeOffset, and the root layer's parent time is the absolute time
// (CACurrentMediaTime). A layer whose speed is 0 holds its local time at
// timeOffset, so its parent's time for it is taken to be its beginTime.
static CFTimeInterval localTimeToParent(CALayer *layer, CFTimeInterval time) {
    float speed = NS_EXTRA(CALayer, layer)->_speed;
    CFTimeInterval begin = NS_EXTRA(CALayer, layer)->_beginTime;
    if (speed == 0)
        return begin;
    return (time - NS_EXTRA(CALayer, layer)->_timeOffset) / speed + begin;
}

static CFTimeInterval parentTimeToLocal(CALayer *layer, CFTimeInterval time) {
    return (time - NS_EXTRA(CALayer, layer)->_beginTime) * NS_EXTRA(CALayer, layer)->_speed
        + NS_EXTRA(CALayer, layer)->_timeOffset;
}

static CFTimeInterval absoluteTimeFromLayer(CALayer *layer, CFTimeInterval time) {
    for (; layer != nil; layer = NS_EXTRA(CALayer, layer)->_superlayer)
        time = localTimeToParent(layer, time);
    return time;
}

static CFTimeInterval layerTimeFromAbsolute(CALayer *layer, CFTimeInterval time) {
    if (layer == nil)
        return time;
    return parentTimeToLocal(layer, layerTimeFromAbsolute(NS_EXTRA(CALayer, layer)->_superlayer, time));
}

- (CFTimeInterval) convertTime: (CFTimeInterval) time fromLayer: (CALayer *) layer {
    return layerTimeFromAbsolute(self, absoluteTimeFromLayer(layer, time));
}

- (CFTimeInterval) convertTime: (CFTimeInterval) time toLayer: (CALayer *) layer {
    return layerTimeFromAbsolute(layer, absoluteTimeFromLayer(self, time));
}

- (CFTimeInterval) beginTime {
    return NS_EXTRA(CALayer, self)->_beginTime;
}

- (void) setBeginTime: (CFTimeInterval) value {
    NS_EXTRA(CALayer, self)->_beginTime = value;
}

- (CFTimeInterval) duration {
    return NS_EXTRA(CALayer, self)->_duration;
}

- (void) setDuration: (CFTimeInterval) value {
    NS_EXTRA(CALayer, self)->_duration = value;
}

- (CFTimeInterval) timeOffset {
    return NS_EXTRA(CALayer, self)->_timeOffset;
}

- (void) setTimeOffset: (CFTimeInterval) value {
    NS_EXTRA(CALayer, self)->_timeOffset = value;
}

- (CFTimeInterval) repeatDuration {
    return NS_EXTRA(CALayer, self)->_repeatDuration;
}

- (void) setRepeatDuration: (CFTimeInterval) value {
    NS_EXTRA(CALayer, self)->_repeatDuration = value;
}

- (float) speed {
    return NS_EXTRA(CALayer, self)->_speed;
}

- (void) setSpeed: (float) value {
    NS_EXTRA(CALayer, self)->_speed = value;
}

- (float) repeatCount {
    return NS_EXTRA(CALayer, self)->_repeatCount;
}

- (void) setRepeatCount: (float) value {
    NS_EXTRA(CALayer, self)->_repeatCount = value;
}

- (BOOL) autoreverses {
    return NS_EXTRA(CALayer, self)->_autoreverses;
}

- (void) setAutoreverses: (BOOL) value {
    NS_EXTRA(CALayer, self)->_autoreverses = value;
}

- (CAMediaTimingFillMode) fillMode {
    return NS_EXTRA(CALayer, self)->_fillMode;
}

- (void) setFillMode: (CAMediaTimingFillMode) value {
    value = [value copy];
    [NS_EXTRA(CALayer, self)->_fillMode release];
    NS_EXTRA(CALayer, self)->_fillMode = value;
}

// The part of the layer's bounds that shows through the scroll layers above it
// (a layer outside any scroll layer shows all of its bounds; clipping by
// masksToBounds does not count).
- (CGRect) visibleRect {
    CGRect visible = [self bounds];
    for (CALayer *ancestor = [self superlayer]; ancestor != nil;
         ancestor = [ancestor superlayer]) {
        if (![ancestor isKindOfClass: [CAScrollLayer class]])
            continue;
        visible = CGRectIntersection(
                visible, [self convertRect: [ancestor bounds] fromLayer: ancestor]);
        if (CGRectIsNull(visible))
            return CGRectZero;
    }
    return visible;
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

// A layer is a key-value coding container: it keeps a value for any key it has no property for, and
// such a key reads as nil until then (Core Animation Programming Guide, "Key-Value Coding
// Extensions"). Observed on macOS 26.7.3: setting nil removes the value, +defaultValueForKey: is
// not consulted for such keys, and neither -initWithLayer: nor archiving carries them over.
// Test: tests/quartzcore-kvc-arbitrary-keys.m.
static char CALayerUndefinedValuesKey;

- (void) setValue: (id) value forUndefinedKey: (NSString *) key {
    NSMutableDictionary *values = objc_getAssociatedObject(self, &CALayerUndefinedValuesKey);
    if (values == nil) {
        values = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &CALayerUndefinedValuesKey, values, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (value != nil)
        [values setObject: value forKey: key];
    else
        [values removeObjectForKey: key];
}

- (id) valueForUndefinedKey: (NSString *) key {
    return [objc_getAssociatedObject(self, &CALayerUndefinedValuesKey) objectForKey: key];
}

- valueForKey: (NSString *) key {
    if ([key isEqualToString: @"bounds"])
        return [NSValue valueWithRect: NS_EXTRA(CALayer, self)->_bounds];
    if ([key isEqualToString: @"frame"])
        return [NSValue valueWithRect: [self frame]];

    return [super valueForKey: key];
}

// Key paths into the struct-valued properties of a layer. NSValue does not
// support key-value coding of its members, so the members of these structs are
// read and written through the layer's accessors, which keeps their side
// effects (autoresizing, actions) in place. The result of splitting a path is
// the property (head) and the rest of the path (tail) within its struct.
typedef enum {
    CALayerStructNone,
    CALayerStructRect,
    CALayerStructPoint,
    CALayerStructSize,
    CALayerStructTransform,
} CALayerStructKind;

static CALayerStructKind CALayerStructKindOfKey(NSString *key) {
    if ([key isEqualToString: @"bounds"] || [key isEqualToString: @"frame"] ||
        [key isEqualToString: @"contentsRect"])
        return CALayerStructRect;
    if ([key isEqualToString: @"position"] || [key isEqualToString: @"anchorPoint"])
        return CALayerStructPoint;
    if ([key isEqualToString: @"shadowOffset"])
        return CALayerStructSize;
    if ([key isEqualToString: @"transform"] || [key isEqualToString: @"sublayerTransform"])
        return CALayerStructTransform;
    return CALayerStructNone;
}

static BOOL CALayerSplitKeyPath(NSString *path, NSString **head, NSString **tail) {
    NSRange dot = [path rangeOfString: @"."];

    if (dot.location == NSNotFound)
        return NO;
    *head = [path substringToIndex: dot.location];
    *tail = [path substringFromIndex: dot.location + 1];
    return CALayerStructKindOfKey(*head) != CALayerStructNone;
}

// The member of a rect, point or size addressed by the tail, or NULL.
static CGFloat *CALayerStructMember(CALayerStructKind kind, NSString *tail, CGRect *rect, CGPoint *point, CGSize *size) {
    if (kind == CALayerStructRect) {
        if ([tail isEqualToString: @"origin.x"]) return &rect->origin.x;
        if ([tail isEqualToString: @"origin.y"]) return &rect->origin.y;
        if ([tail isEqualToString: @"size.width"]) return &rect->size.width;
        if ([tail isEqualToString: @"size.height"]) return &rect->size.height;
    } else if (kind == CALayerStructPoint) {
        if ([tail isEqualToString: @"x"]) return &point->x;
        if ([tail isEqualToString: @"y"]) return &point->y;
    } else if (kind == CALayerStructSize) {
        if ([tail isEqualToString: @"width"]) return &size->width;
        if ([tail isEqualToString: @"height"]) return &size->height;
    }
    return NULL;
}

// The rotation or scale entries of a transform that a key path like
// transform.rotation.z or transform.scale.x addresses.
static BOOL CALayerTransformComponent(NSString *tail, CATransform3D *t, CGFloat *value, BOOL set) {
    CGFloat v = set ? *value : 0;

    if ([tail isEqualToString: @"scale"] || [tail isEqualToString: @"scale.x"]) {
        if (set) { t->m11 = v; if ([tail isEqualToString: @"scale"]) { t->m22 = v; t->m33 = v; } }
        else *value = t->m11;
    } else if ([tail isEqualToString: @"scale.y"]) {
        if (set) t->m22 = v; else *value = t->m22;
    } else if ([tail isEqualToString: @"scale.z"]) {
        if (set) t->m33 = v; else *value = t->m33;
    } else if ([tail isEqualToString: @"rotation"] || [tail isEqualToString: @"rotation.z"]) {
        if (set) { t->m11 = cos(v); t->m12 = sin(v); t->m21 = -sin(v); t->m22 = cos(v); }
        else *value = atan2(t->m12, t->m11);
    } else if ([tail isEqualToString: @"rotation.x"]) {
        if (set) { t->m22 = cos(v); t->m23 = sin(v); t->m32 = -sin(v); t->m33 = cos(v); }
        else *value = atan2(t->m23, t->m22);
    } else if ([tail isEqualToString: @"rotation.y"]) {
        if (set) { t->m11 = cos(v); t->m13 = -sin(v); t->m31 = sin(v); t->m33 = cos(v); }
        else *value = atan2(-t->m13, t->m11);
    } else if ([tail isEqualToString: @"translation.x"]) {
        if (set) t->m41 = v; else *value = t->m41;
    } else if ([tail isEqualToString: @"translation.y"]) {
        if (set) t->m42 = v; else *value = t->m42;
    } else if ([tail isEqualToString: @"translation.z"]) {
        if (set) t->m43 = v; else *value = t->m43;
    } else {
        return NO;
    }
    return YES;
}

- valueForKeyPath: (NSString *) path {
    NSString *head, *tail;

    if (!CALayerSplitKeyPath(path, &head, &tail))
        return [super valueForKeyPath: path];

    CALayerStructKind kind = CALayerStructKindOfKey(head);
    CGFloat v;

    if (kind == CALayerStructTransform) {
        CATransform3D t = [head isEqualToString: @"transform"] ? [self transform] : [self sublayerTransform];

        if ([tail isEqualToString: @"translation"])
            return [NSValue valueWithSize: NSMakeSize(t.m41, t.m42)];
        if (CALayerTransformComponent(tail, &t, &v, NO))
            return [NSNumber numberWithDouble: v];
        return [super valueForKeyPath: path];
    }

    CGRect rect = CGRectZero;
    CGPoint point = CGPointZero;
    CGSize size = CGSizeZero;

    if (kind == CALayerStructRect)
        rect = [head isEqualToString: @"bounds"] ? [self bounds] : [head isEqualToString: @"frame"] ? [self frame] : [self contentsRect];
    else if (kind == CALayerStructPoint)
        point = [head isEqualToString: @"position"] ? [self position] : [self anchorPoint];
    else
        size = [self shadowOffset];

    if (kind == CALayerStructRect && [tail isEqualToString: @"origin"])
        return [NSValue valueWithPoint: NSMakePoint(rect.origin.x, rect.origin.y)];
    if (kind == CALayerStructRect && [tail isEqualToString: @"size"])
        return [NSValue valueWithSize: NSMakeSize(rect.size.width, rect.size.height)];

    CGFloat *member = CALayerStructMember(kind, tail, &rect, &point, &size);

    if (member == NULL)
        return [super valueForKeyPath: path];
    return [NSNumber numberWithDouble: *member];
}

- (void) setValue: (id) value forKeyPath: (NSString *) path {
    NSString *head, *tail;

    if (!CALayerSplitKeyPath(path, &head, &tail)) {
        [super setValue: value forKeyPath: path];
        return;
    }

    CALayerStructKind kind = CALayerStructKindOfKey(head);

    if (kind == CALayerStructTransform) {
        BOOL sublayer = [head isEqualToString: @"sublayerTransform"];
        CATransform3D t = sublayer ? [self sublayerTransform] : [self transform];
        CGFloat v = [value doubleValue];

        if ([tail isEqualToString: @"translation"]) {
            NSSize s = [value sizeValue];

            t.m41 = s.width;
            t.m42 = s.height;
        } else if (!CALayerTransformComponent(tail, &t, &v, YES)) {
            [super setValue: value forKeyPath: path];
            return;
        }
        if (sublayer)
            [self setSublayerTransform: t];
        else
            [self setTransform: t];
        return;
    }

    CGRect rect = CGRectZero;
    CGPoint point = CGPointZero;
    CGSize size = CGSizeZero;
    BOOL isPosition = [head isEqualToString: @"position"];

    if (kind == CALayerStructRect)
        rect = [head isEqualToString: @"bounds"] ? [self bounds] : [head isEqualToString: @"frame"] ? [self frame] : [self contentsRect];
    else if (kind == CALayerStructPoint)
        point = isPosition ? [self position] : [self anchorPoint];
    else
        size = [self shadowOffset];

    if (kind == CALayerStructRect && [tail isEqualToString: @"origin"])
        { NSPoint o = [value pointValue]; rect.origin = CGPointMake(o.x, o.y); }
    else if (kind == CALayerStructRect && [tail isEqualToString: @"size"])
        { NSSize z = [value sizeValue]; rect.size = CGSizeMake(z.width, z.height); }
    else {
        CGFloat *member = CALayerStructMember(kind, tail, &rect, &point, &size);

        if (member == NULL) {
            [super setValue: value forKeyPath: path];
            return;
        }
        *member = [value doubleValue];
    }

    if ([head isEqualToString: @"bounds"])
        [self setBounds: rect];
    else if ([head isEqualToString: @"frame"])
        [self setFrame: rect];
    else if ([head isEqualToString: @"contentsRect"])
        [self setContentsRect: rect];
    else if (isPosition)
        [self setPosition: point];
    else if ([head isEqualToString: @"anchorPoint"])
        [self setAnchorPoint: point];
    else
        [self setShadowOffset: size];
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

// The default value of each property whose default is not zero or nil; YES/NO properties answer
// their default either way, and anything else gives nil. Values observed on macOS 26.7.3.
// Test: tests/quartzcore-kvc-arbitrary-keys.m.
+ (id) defaultValueForKey: (NSString *) key {
    static NSDictionary *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGColorRef black = CGColorCreateGenericRGB(0, 0, 0, 1);
        defaults = [@{
            @"opacity" : @1.0f,
            @"anchorPoint" : [NSValue valueWithPoint: NSMakePoint(0.5, 0.5)],
            @"borderColor" : (id) black,
            @"shadowColor" : (id) black,
            @"shadowOffset" : [NSValue valueWithSize: NSMakeSize(0, -3)],
            @"shadowRadius" : @3.0,
            @"contentsRect" : [NSValue valueWithRect: NSMakeRect(0, 0, 1, 1)],
            @"contentsCenter" : [NSValue valueWithRect: NSMakeRect(0, 0, 1, 1)],
            @"contentsScale" : @1.0,
            @"contentsGravity" : kCAGravityResize,
            @"contentsFormat" : kCAContentsFormatRGBA8Uint,
            @"minificationFilter" : kCAFilterLinear,
            @"magnificationFilter" : kCAFilterLinear,
            @"rasterizationScale" : @1.0,
            @"edgeAntialiasingMask" : @15,
            @"cornerCurve" : kCACornerCurveCircular,
            @"maskedCorners" : @15,
            @"speed" : @1.0f,
            @"duration" : @(INFINITY),
            @"fillMode" : kCAFillModeRemoved,
            @"hidden" : @NO,
            @"masksToBounds" : @NO,
            @"doubleSided" : @YES,
            @"geometryFlipped" : @NO,
            @"opaque" : @NO,
            @"contentsOpaque" : @NO,
            @"needsDisplayOnBoundsChange" : @NO,
            @"drawsAsynchronously" : @NO,
            @"allowsEdgeAntialiasing" : @YES,
            @"allowsGroupOpacity" : @YES,
            @"shouldRasterize" : @NO,
            @"wantsExtendedDynamicRangeContent" : @NO,
        } retain];
        CGColorRelease(black);
    });
    return [defaults objectForKey: key];
}

// Whether a change of the property needs the layer redrawn; none of CALayer's own do.
+ (BOOL) needsDisplayForKey: (NSString *) key {
    return NO;
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

- (BOOL) _drawLayerContents: (CGRect) bounds opacity: (float) opacity {
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
