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
    // The drawable rendered into: the subwindow's own one, which this context
    // created and owns, or the parent window's, which the subwindow lends.
    void* _cglWindow;
    BOOL _ownsCglWindow;
    BOOL _renderRequested;
    // The swap interval last set for the Metal layers in the tree, or -1.
    GLint _swapInterval;
}

@property(readonly) CGLContextObj glContext;

- initWithFrame: (CGRect) rect;

- (void) setFrame: (CGRect) value;
- (void) setLayer: (CALayer *) layer;
- (void) setHidden: (BOOL) hidden;
- (void) setSubwindow: (CGSubWindow*) subwindow;

- (void) invalidate;

- (void) render;

- (void) startTimerIfNeeded;

- (void) deleteTextureId: (NSNumber *) textureId;

- (void) flush;

@end
