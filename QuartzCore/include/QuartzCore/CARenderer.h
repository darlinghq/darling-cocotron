#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/LegacyIvarLayout.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CABase.h>

CA_EXPORT NSString *const kCARendererColorSpace;

@class CALayer, O2Surface;

@interface CARenderer : NSObject {
    NS_EXTRA_IVARS_BEGIN(CARenderer)
        void *_cglContext;
        CGRect _bounds;
        CALayer *_rootLayer;
        BOOL _clearsToTransparent;
        CGImageRef _backdropImage;
        unsigned int _backdropTexture;
        unsigned int _roundedClipProgram;
        BOOL _roundedClipUnavailable;
    NS_EXTRA_IVARS_END(CARenderer)
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
