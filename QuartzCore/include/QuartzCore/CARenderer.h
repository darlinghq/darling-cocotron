#import <ApplicationServices/ApplicationServices.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CABase.h>

CA_EXPORT NSString *const kCARendererColorSpace;

@class CALayer, O2Surface;

@interface CARenderer : NSObject {
    void *_cglContext;
    CGRect _bounds;
    CALayer *_rootLayer;
}

@property(assign) CGRect bounds;
@property(retain) CALayer *layer;

+ (CARenderer *) rendererWithCGLContext: (void *) cglContext
                                options: (NSDictionary *) options;

- (void) beginFrameAtTime: (CFTimeInterval) currentTime
                timeStamp: (CVTimeStamp *) timeStamp;

- (void) render;

- (void) endFrame;

@end
