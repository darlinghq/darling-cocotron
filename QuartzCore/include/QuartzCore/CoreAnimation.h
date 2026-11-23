// The C parts for any language, the classes for Objective-C, as in Apple's CoreAnimation.h: C code
// includes QuartzCore for CATransform3D (VLC's video_chroma/cvpx.c does).
#import <QuartzCore/CABase.h>
#import <QuartzCore/CATransform3D.h>

#ifdef __OBJC__
#import <QuartzCore/CAAnimation.h>
#import <QuartzCore/CADisplayLink.h>
#import <QuartzCore/CAConstraintLayoutManager.h>
#import <QuartzCore/CAEmitterCell.h>
#import <QuartzCore/CAEmitterLayer.h>
#import <QuartzCore/CAFrameRateRange.h>
#import <QuartzCore/CALayer.h>
#import <QuartzCore/CAMediaTimingFunction.h>
#import <QuartzCore/CARenderer.h>
#import <QuartzCore/CATextLayer.h>
#import <QuartzCore/CATransaction.h>

#import <QuartzCore/CAEDRMetadata.h>
#import <QuartzCore/CAGradientLayer.h>
#import <QuartzCore/CAMetalDrawable.h>
#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/CAOpenGLLayer.h>
#import <QuartzCore/CAReplicatorLayer.h>
#import <QuartzCore/CAScrollLayer.h>
#import <QuartzCore/CAShapeLayer.h>
#import <QuartzCore/CATiledLayer.h>
#import <QuartzCore/CATransformLayer.h>
#import <QuartzCore/CASpringAnimation.h>
#endif
