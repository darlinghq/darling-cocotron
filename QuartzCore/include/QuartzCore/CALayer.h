
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CAAction.h>
#import <QuartzCore/CATransform3D.h>

@class CAAnimation, CALayerContext, CALayer;
@protocol CALayoutManager;

typedef NS_OPTIONS(unsigned int, CAEdgeAntialiasingMask) {
    kCALayerLeftEdge = 1U << 0,
    kCALayerRightEdge = 1U << 1,
    kCALayerBottomEdge = 1U << 2,
    kCALayerTopEdge = 1U << 3,
};

typedef NS_OPTIONS(unsigned int, CAAutoresizingMask) {
    kCALayerNotSizable = 0x00,
    kCALayerMinXMargin = 0x01,
    kCALayerWidthSizable = 0x02,
    kCALayerMaxXMargin = 0x04,
    kCALayerMinYMargin = 0x08,
    kCALayerHeightSizable = 0x10,
    kCALayerMaxYMargin = 0x20,
};

typedef NSString *CALayerContentsGravity NS_TYPED_ENUM;
typedef NSString *CALayerCornerCurve NS_TYPED_ENUM;
typedef NSString *CALayerContentsFormat NS_TYPED_ENUM;
typedef NSString *CALayerContentsFilter NS_TYPED_ENUM;

CA_EXPORT CALayerContentsFilter const kCAFilterLinear NS_SWIFT_NAME(CALayerContentsFilter.linear);
CA_EXPORT CALayerContentsFilter const kCAFilterNearest NS_SWIFT_NAME(CALayerContentsFilter.nearest);
CA_EXPORT CALayerContentsFilter const kCAFilterTrilinear NS_SWIFT_NAME(CALayerContentsFilter.trilinear);

CA_EXPORT CALayerContentsGravity const kCAGravityResizeAspect NS_SWIFT_NAME(CALayerContentsGravity.resizeAspect);
CA_EXPORT CALayerContentsGravity const kCAGravityResizeAspectFill NS_SWIFT_NAME(CALayerContentsGravity.resizeAspectFill);

CA_EXPORT CALayerContentsGravity const kCAGravityCenter NS_SWIFT_NAME(CALayerContentsGravity.center);
CA_EXPORT CALayerContentsGravity const kCAGravityTop NS_SWIFT_NAME(CALayerContentsGravity.top);
CA_EXPORT CALayerContentsGravity const kCAGravityBottom NS_SWIFT_NAME(CALayerContentsGravity.bottom);
CA_EXPORT CALayerContentsGravity const kCAGravityLeft NS_SWIFT_NAME(CALayerContentsGravity.left);
CA_EXPORT CALayerContentsGravity const kCAGravityRight NS_SWIFT_NAME(CALayerContentsGravity.right);
CA_EXPORT CALayerContentsGravity const kCAGravityTopLeft NS_SWIFT_NAME(CALayerContentsGravity.topLeft);
CA_EXPORT CALayerContentsGravity const kCAGravityTopRight NS_SWIFT_NAME(CALayerContentsGravity.topRight);
CA_EXPORT CALayerContentsGravity const kCAGravityBottomLeft NS_SWIFT_NAME(CALayerContentsGravity.bottomLeft);
CA_EXPORT CALayerContentsGravity const kCAGravityBottomRight NS_SWIFT_NAME(CALayerContentsGravity.bottomRight);
CA_EXPORT CALayerContentsGravity const kCAGravityResize NS_SWIFT_NAME(CALayerContentsGravity.resize);

CA_EXPORT CALayerCornerCurve const kCACornerCurveCircular NS_SWIFT_NAME(CALayerCornerCurve.circular);
CA_EXPORT CALayerCornerCurve const kCACornerCurveContinuous NS_SWIFT_NAME(CALayerCornerCurve.continuous);

CA_EXPORT NSString *const kCAOnOrderIn;
CA_EXPORT NSString *const kCAOnOrderOut;
CA_EXPORT NSString *const kCATransition;

CA_EXPORT CALayerContentsFormat const kCAContentsFormatRGBA8Uint NS_SWIFT_NAME(CALayerContentsFormat.RGBA8Uint);
CA_EXPORT CALayerContentsFormat const kCAContentsFormatRGBA16Float NS_SWIFT_NAME(CALayerContentsFormat.RGBA16Float);
CA_EXPORT CALayerContentsFormat const kCAContentsFormatGray8Uint NS_SWIFT_NAME(CALayerContentsFormat.gray8Uint);

@protocol CALayerDelegate <NSObject>

@optional

- (void)displayLayer: (CALayer*)layer;

- (void)drawLayer: (CALayer*)layer
        inContext: (CGContextRef)ctx;

- (void)layerWillDraw: (CALayer*)layer;

- (void)layoutSublayersOfLayer: (CALayer*)layer;

- (id<CAAction>)actionForLayer: (CALayer*)layer
                        forKey: (NSString*)event;

@end

typedef NSString *CADynamicRange NS_TYPED_ENUM;
typedef NSString *CAToneMapMode NS_TYPED_ENUM;

CA_EXPORT CADynamicRange const CADynamicRangeAutomatic;
CA_EXPORT CADynamicRange const CADynamicRangeStandard;
CA_EXPORT CADynamicRange const CADynamicRangeConstrainedHigh;
CA_EXPORT CADynamicRange const CADynamicRangeHigh;

CA_EXPORT CAToneMapMode const CAToneMapModeAutomatic;
CA_EXPORT CAToneMapMode const CAToneMapModeNever;
CA_EXPORT CAToneMapMode const CAToneMapModeIfSupported;

@interface CALayer : NSObject {
    CALayerContext *_context;
    CALayer *_superlayer;
    NSArray *_sublayers;
    id _delegate;
    CGPoint _anchorPoint;
    CGPoint _position;
    CGRect _bounds;
    CGFloat _opacity;
    BOOL _opaque;
    id _contents;
    CGFloat _contentsScale;
    CGRect _contentsCenter;
    NSString *_contentsFormat;
    NSString *_contentsGravity;
    NSString *_cornerCurve;
    BOOL _allowsGroupOpacity;
    CGPathRef _shadowPath;
    BOOL _needsLayout;
    NSString *_preferredDynamicRange;
    NSString *_toneMapMode;
    BOOL _allowsEdgeAntialiasing;
    CAEdgeAntialiasingMask _edgeAntialiasingMask;
    CATransform3D _transform;
    CATransform3D _sublayerTransform;
    NSString *_minificationFilter;
    NSString *_magnificationFilter;
    BOOL _needsDisplay;
    NSMutableDictionary *_animations;
    NSNumber *_textureId;
    CGColorRef _backgroundColor;
    CGColorRef _borderColor;
    CGFloat _borderWidth;
    CGFloat _cornerRadius;
    BOOL _masksToBounds;
    CALayer *_mask;
    NSArray *_filters;
    id _compositingFilter;
    CGColorRef _shadowColor;
    float _shadowOpacity;
    CGFloat _shadowRadius;
    CGSize _shadowOffset;
    BOOL _hidden;
    id _textureContents;
    uint32_t _textureSeed;
    BOOL _needsDisplayOnBoundsChange;
    NSString *_name;
    id _layoutManager;
    NSArray *_constraints;
    BOOL _geometryFlipped;
    CAAutoresizingMask _autoresizingMask;
    CGFloat _zPosition;
    CGFloat _anchorPointZ;
    BOOL _doubleSided;
    CGRect _contentsRect;
    float _minificationFilterBias;
    BOOL _shouldRasterize;
    CGFloat _rasterizationScale;
    BOOL _drawsAsynchronously;
    NSArray *_backgroundFilters;
    NSDictionary *_actions;
    NSDictionary *_style;
}

+ layer;

@property(copy) NSString *name;
@property(readonly) CALayer *superlayer;
@property(copy) NSArray<CALayer *> *sublayers;
@property(assign) id<CALayerDelegate> delegate;
@property(retain) id<CALayoutManager> layoutManager;
@property CAAutoresizingMask autoresizingMask;
@property CGPoint anchorPoint;
@property CGPoint position;
@property CGFloat zPosition;
@property CGFloat anchorPointZ;
@property CGRect bounds;
@property CGRect frame;
@property CGFloat opacity;
@property(getter=isOpaque) BOOL opaque;
@property(retain) id contents;

// How contents maps onto the layer: contentsScale is the ratio of contents
// pixels to layer points, contentsCenter the stretchable region of the
// contents in unit coordinates. Stored and defaulted per the documented
// behaviour, but CARenderer still draws contents unscaled and unstretched,
// the way masksToBounds is stored without clipping yet.
@property CGFloat contentsScale;
@property CGRect contentsCenter;
@property(copy) CALayerContentsFormat contentsFormat;
@property(copy) CALayerContentsGravity contentsGravity;
// The part of the contents to draw, in unit coordinates.
@property CGRect contentsRect;

// Stored for callers; CARenderer draws standard dynamic range only.
@property(copy) CADynamicRange preferredDynamicRange;
@property(copy) CAToneMapMode toneMapMode;

@property CATransform3D transform;
@property CATransform3D sublayerTransform;

- (CGAffineTransform) affineTransform;
- (void) setAffineTransform: (CGAffineTransform) transform;

@property(copy) CALayerContentsFilter minificationFilter;
@property(copy) CALayerContentsFilter magnificationFilter;
@property float minificationFilterBias;

// Appearance. CARenderer draws the background and the border as rounded rects
// with cornerRadius, and the contents between them (not clipped to the corners).
// masksToBounds is stored but sublayers aren't clipped yet.
@property CGColorRef backgroundColor;
@property CGColorRef borderColor;
@property CGFloat borderWidth;
@property CGFloat cornerRadius;
@property(copy) CALayerCornerCurve cornerCurve;
@property BOOL masksToBounds;
// These properties retain the public layer state. CARenderer does not yet
// apply masks, Core Image filters, or blurred shadows when drawing.
@property(retain) CALayer *mask;
@property(copy) NSArray *filters;
@property(retain) id compositingFilter;
@property(copy) NSArray *backgroundFilters;
@property CGColorRef shadowColor;
@property float shadowOpacity;
@property CGFloat shadowRadius;
@property CGSize shadowOffset;
@property CGPathRef shadowPath;
@property(getter=isHidden) BOOL hidden;
@property BOOL allowsGroupOpacity;

// Stored only; CARenderer does not yet antialias layer edges.
@property BOOL allowsEdgeAntialiasing;
@property CAEdgeAntialiasingMask edgeAntialiasingMask;

// When YES, a change of the bounds size marks the layer as needing display.
@property BOOL needsDisplayOnBoundsChange;

// Rendering hints. They are stored, but CARenderer draws every layer flat,
// front-facing and unrasterized, on the calling thread.
@property(getter=isDoubleSided) BOOL doubleSided;
@property BOOL shouldRasterize;
@property CGFloat rasterizationScale;
@property BOOL drawsAsynchronously;

// Actions keyed by property or event name; -actionForKey: looks here after
// the delegate. An NSNull value means no action.
@property(copy) NSDictionary *actions;
// Stored; property defaults are not looked up in it yet.
@property(copy) NSDictionary *style;

// YES puts the origin at the top of the bounds for sublayers and drawing;
// images set as contents display the same either way.
@property(getter=isGeometryFlipped) BOOL geometryFlipped;
// YES when an odd number of layers from this one up to the root are flipped.
- (BOOL) contentsAreFlipped;

- (nonnull instancetype)init;
// Makes a layer in the default state; subclasses override it to copy their own
// state from the layer they are given. The properties of that layer are not
// carried over and the argument is not checked.
- (nonnull instancetype)initWithLayer: (nonnull id)layer;

- (void) addSublayer: (CALayer *) layer;
- (void) insertSublayer: (CALayer *) layer atIndex: (unsigned int) index;
- (void) insertSublayer: (CALayer *) layer below: (CALayer *) sibling;
- (void) insertSublayer: (CALayer *) layer above: (CALayer *) sibling;
- (void) replaceSublayer: (CALayer *) layer with: (CALayer *) other;
- (void) display;
- (void) displayIfNeeded;
- (void) layoutSublayers;
- (void) layoutIfNeeded;
- (void) setNeedsLayout;
- (BOOL) needsLayout;
- (void) drawInContext: (CGContextRef) context;
- (BOOL) needsDisplay;
- (void) removeFromSuperlayer;
- (void) setNeedsDisplay;
- (void) setNeedsDisplayInRect: (CGRect) rect;

- (void) addAnimation: (CAAnimation *) animation forKey: (NSString *) key;
- (CAAnimation *) animationForKey: (NSString *) key;
- (void) removeAllAnimations;
- (void) removeAnimationForKey: (NSString *) key;
- (NSArray *) animationKeys;

// The action for key: the first one that the delegate, actions, the style's
// actions or +defaultActionForKey: provides, else the implicit animation of
// the property. NSNull from any of these means no action.
- (id<CAAction>) actionForKey: (NSString *) key;
+ (id<CAAction>) defaultActionForKey: (NSString *) key;

@end

// NSNull in an actions dictionary disables the action for its key.
@interface NSNull (CAActionAdditions) <CAAction>
@end

@protocol CALayoutManager <NSObject>
@optional

- (CGSize) preferredSizeOfLayer: (CALayer *) layer;
- (void) invalidateLayoutOfLayer: (CALayer *) layer;
- (void) layoutSublayersOfLayer: (CALayer *) layer;

@end
