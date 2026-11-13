// A CAShapeLayer whose delegate implements -displayLayer: (as SwiftUI's
// shape view does) must still draw its path, and layer.transform must rotate
// it about the anchor point. Exit 5: nothing drawn; 6: transform ignored.
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static BOOL pixelIsRed(const unsigned char *pixel) {
    return pixel[0] > 200 && pixel[1] < 20 && pixel[2] < 20 && pixel[3] > 200;
}

static BOOL pixelIsBlack(const unsigned char *pixel) {
    return pixel[0] < 20 && pixel[1] < 20 && pixel[2] < 20 && pixel[3] > 200;
}

@interface NullDisplayDelegate : NSObject
@end
@implementation NullDisplayDelegate
- (void)displayLayer:(CALayer *)layer {}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSRect frame = NSMakeRect(0, 0, 64, 64);
        NSWindow *window = [[NSWindow alloc] initWithContentRect: frame
                                                      styleMask: NSBorderlessWindowMask
                                                        backing: NSBackingStoreBuffered
                                                          defer: NO];
        if (window == nil) return 1;

        NSOpenGLView *view = [[NSOpenGLView alloc] initWithFrame: frame];
        [window setContentView: view];
        [view release];

        NSOpenGLContext *context = [view openGLContext];
        if (context == nil || [context CGLContextObj] == NULL) {
            [window release];
            return 2;
        }

        [view lockFocus];
        if ([NSOpenGLContext currentContext] != context ||
            CGLGetCurrentContext() != [context CGLContextObj]) {
            [view unlockFocus];
            [window release];
            return 3;
        }

        glViewport(0, 0, 64, 64);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glOrtho(0, 64, 0, 64, -1, 1);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);

        NullDisplayDelegate *delegate = [[NullDisplayDelegate alloc] init];
        CAShapeLayer *shape = [CAShapeLayer layer];
        shape.delegate = delegate;
        shape.bounds = CGRectMake(0, 0, 20, 10);
        shape.position = CGPointMake(32, 32);
        shape.transform = CATransform3DMakeRotation(M_PI / 2, 0, 0, 1);
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathAddRect(path, NULL, CGRectMake(0, 0, 20, 10));
        shape.path = path;
        CGPathRelease(path);
        CGColorRef red = CGColorCreateGenericRGB(1, 0, 0, 1);
        shape.fillColor = red;
        CGColorRelease(red);

        CALayer *root = [CALayer layer];
        root.bounds = CGRectMake(0, 0, 64, 64);
        root.anchorPoint = CGPointZero;
        root.position = CGPointZero;
        [root addSublayer: shape];

        CARenderer *renderer = [CARenderer rendererWithCGLContext: [context CGLContextObj]
                                                          options: nil];
        renderer.bounds = CGRectMake(0, 0, 64, 64);
        renderer.layer = root;
        [renderer render];
        glFinish();

        unsigned char rotated[4], unrotated[4];
        glReadPixels(32, 40, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, rotated);
        glReadPixels(24, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, unrotated);
        GLenum error = glGetError();

        [view unlockFocus];
        [NSOpenGLContext clearCurrentContext];
        [window release];
        [delegate release];

        if (error != GL_NO_ERROR) {
            fprintf(stderr, "OpenGL error: %u\n", error);
            return 4;
        }
        if (pixelIsBlack(rotated) && pixelIsBlack(unrotated)) {
            fprintf(stderr, "shape layer drew nothing\n");
            return 5;
        }
        if (!pixelIsRed(rotated) || !pixelIsBlack(unrotated)) {
            fprintf(stderr, "rotated=(%u,%u,%u,%u) unrotated=(%u,%u,%u,%u)\n",
                    rotated[0], rotated[1], rotated[2], rotated[3],
                    unrotated[0], unrotated[1], unrotated[2], unrotated[3]);
            return 6;
        }
        return 0;
    }
}
