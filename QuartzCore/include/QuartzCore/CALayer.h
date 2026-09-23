
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CAAction.h>
#import <QuartzCore/CATransform3D.h>

@class CAAnimation, CALayerContext, CALayer;

enum {
    kCALayerNotSizable = 0x00,
    kCALayerMinXMargin = 0x01,
    kCALayerWidthSizable = 0x02,
    kCALayerMaxXMargin = 0x04,
    kCALayerMinYMargin = 0x08,
    kCALayerHeightSizable = 0x10,
    kCALayerMaxYMargin = 0x20,
};

CA_EXPORT NSString *const kCAFilterLinear;
CA_EXPORT NSString *const kCAFilterNearest;
CA_EXPORT NSString *const kCAFilterTrilinear;

typedef NSString *CALayerContentsGravity NS_TYPED_ENUM;
typedef NSString *CALayerCornerCurve NS_TYPED_ENUM;
typedef NSString *CALayerContentsFormat NS_TYPED_ENUM;
typedef NSString *CALayerContentsFilter NS_TYPED_ENUM;

CA_EXPORT CALayerContentsGravity const kCAGravityResizeAspect;
CA_EXPORT CALayerContentsGravity const kCAGravityResizeAspectFill;

CA_EXPORT CALayerContentsGravity const kCAGravityCenter;
CA_EXPORT CALayerContentsGravity const kCAGravityTop;
CA_EXPORT CALayerContentsGravity const kCAGravityBottom;
CA_EXPORT CALayerContentsGravity const kCAGravityLeft;
CA_EXPORT CALayerContentsGravity const kCAGravityRight;
CA_EXPORT CALayerContentsGravity const kCAGravityTopLeft NS_SWIFT_NAME(CALayerContentsGravity.topLeft);
CA_EXPORT CALayerContentsGravity const kCAGravityTopRight;
CA_EXPORT CALayerContentsGravity const kCAGravityBottomLeft;
CA_EXPORT CALayerContentsGravity const kCAGravityBottomRight;
CA_EXPORT CALayerContentsGravity const kCAGravityResize;

CA_EXPORT CALayerCornerCurve const kCACornerCurveCircular NS_SWIFT_NAME(CALayerCornerCurve.circular);
CA_EXPORT CALayerCornerCurve const kCACornerCurveContinuous NS_SWIFT_NAME(CALayerCornerCurve.continuous);

CA_EXPORT NSString *const kCAOnOrderIn;
CA_EXPORT NSString *const kCAOnOrderOut;
CA_EXPORT NSString *const kCATransition;

CA_EXPORT CALayerContentsFormat const kCAContentsFormatRGBA8Uint NS_SWIFT_NAME(CALayerContentsFormat.RGBA8Uint);
CA_EXPORT NSString *const kCAContentsFormatRGBA16Float;
CA_EXPORT NSString *const kCAContentsFormatGray8Uint;

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
    BOOL _allowsEdgeAntialiasing;
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
    BOOL _needsDisplayOnBoundsChange;
}

+ layer;

@property(readonly) CALayer *superlayer;
@property(copy) NSArray *sublayers;
@property(assign) id<CALayerDelegate> delegate;
@property CGPoint anchorPoint;
@property CGPoint position;
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

@property CATransform3D transform;
@property CATransform3D sublayerTransform;

- (CGAffineTransform) affineTransform;
- (void) setAffineTransform: (CGAffineTransform) transform;

@property(copy) NSString *minificationFilter;
@property(copy) NSString *magnificationFilter;

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
@property CGColorRef shadowColor;
@property float shadowOpacity;
@property CGFloat shadowRadius;
@property CGSize shadowOffset;
@property CGPathRef shadowPath;
@property(getter=isHidden) BOOL hidden;
@property BOOL allowsGroupOpacity;

// Stored only; CARenderer does not yet antialias layer edges.
@property BOOL allowsEdgeAntialiasing;

// When YES, a change of the bounds size marks the layer as needing display.
@property BOOL needsDisplayOnBoundsChange;

- (nonnull instancetype)init;

- (void) addSublayer: (CALayer *) layer;
- (void) insertSublayer: (CALayer *) layer atIndex: (unsigned int) index;
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

- (id<CAAction>) actionForKey: (NSString *) key;

@end

@protocol CALayoutManager <NSObject>
@optional

- (CGSize) preferredSizeOfLayer: (CALayer *) layer;
- (void) invalidateLayoutOfLayer: (CALayer *) layer;
- (void) layoutSublayersOfLayer: (CALayer *) layer;

@end
