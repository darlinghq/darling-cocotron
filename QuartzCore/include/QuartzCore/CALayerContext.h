#import <CoreGraphics/CGGeometry.h>
#import <Foundation/NSObject.h>
#import <OpenGL/OpenGL.h>
#import <CoreGraphics/CGSubWindow.h>

@class CARenderer, CALayer, CGLPixelSurface, NSTimer, NSMutableArray, NSNumber;

@interface CALayerContext : NSObject {
    CGRect _frame;
    CGLPixelFormatObj _pixelFormat;
    CGLContextObj _glContext;
    CALayer *_layer;
    CARenderer *_renderer;

    NSMutableArray *_deleteTextureIds;

    NSTimer *_timer;
    CGSubWindow* _subwindow;
    void* _cglWindow;
}

@property(readonly) CGLContextObj glContext;

- initWithFrame: (CGRect) rect;

- (void) setFrame: (CGRect) value;
- (void) setLayer: (CALayer *) layer;
- (void) setSubwindow: (CGSubWindow*) subwindow;

- (void) invalidate;

- (void) render;

- (void) startTimerIfNeeded;

- (void) deleteTextureId: (NSNumber *) textureId;

- (void) flush;

@end
