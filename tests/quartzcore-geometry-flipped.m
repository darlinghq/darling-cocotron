// CALayer.geometryFlipped: the property, contentsAreFlipped parity, the flipped
// context -display hands to -drawInContext:, and where CARenderer puts sublayers
// and contents images. The render check draws into an offscreen framebuffer, so
// it needs a GL display (run it under X11); build against AppKit, OpenGL and
// QuartzCore.
#define GL_GLEXT_PROTOTYPES
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>

enum { kSize = 100 };

static void expect(BOOL condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

// Fills local rect (0, 0, width, 10): the bottom strip unflipped, the top strip flipped.
@interface StripDelegate : NSObject
@end

@implementation StripDelegate
- (void) drawLayer: (CALayer *) layer inContext: (CGContextRef) context {
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, layer.bounds.size.width, 10));
}
@end

static CALayer *layerWithFrame(CGRect frame, CGFloat r, CGFloat g, CGFloat b)
{
    CALayer *layer = [CALayer layer];
    CGColorRef color = CGColorCreateGenericRGB(r, g, b, 1);

    layer.anchorPoint = CGPointZero;
    layer.position = frame.origin;
    layer.bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
    layer.backgroundColor = color;
    CGColorRelease(color);
    return layer;
}

// Whether the first pixel of an image row (row 0 is the top) is opaque red.
static BOOL imageRowIsRed(CGImageRef image, size_t row)
{
    CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(image));
    const uint32_t *pixel = (const uint32_t *) (CFDataGetBytePtr(data) + row * CGImageGetBytesPerRow(image));
    // kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host: 0xAARRGGBB.
    uint32_t p = pixel[0];
    BOOL red = (p >> 24) > 0xF0 && ((p >> 16) & 0xFF) > 0xF0 && ((p >> 8) & 0xFF) < 0x10 && (p & 0xFF) < 0x10;
    CFRelease(data);
    return red;
}

static void checkDisplay(void)
{
    StripDelegate *delegate = [[StripDelegate alloc] init];
    CALayer *layer = [CALayer layer];

    layer.bounds = CGRectMake(0, 0, 40, 40);
    layer.delegate = (id) delegate;
    [layer display];
    expect(imageRowIsRed((CGImageRef) layer.contents, 39) &&
           !imageRowIsRed((CGImageRef) layer.contents, 0),
           "unflipped: drawing at y = 0 lands at the bottom of the contents image");

    layer.geometryFlipped = YES;
    [layer display];
    expect(imageRowIsRed((CGImageRef) layer.contents, 0) &&
           !imageRowIsRed((CGImageRef) layer.contents, 39),
           "flipped: drawing at y = 0 lands at the top of the contents image");
    [delegate release];
}

static const GLubyte *pixelAt(const GLubyte *pixels, int x, int yFromTop)
{
    return pixels + 4 * ((kSize - 1 - yFromTop) * kSize + x);
}

static BOOL isColor(const GLubyte *p, int r, int g, int b)
{
    return abs(p[0] - r) < 8 && abs(p[1] - g) < 8 && abs(p[2] - b) < 8;
}

static void render(CARenderer *renderer, GLubyte *pixels)
{
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, kSize, 0, kSize, -1, 1);
    [renderer render];
    glReadPixels(0, 0, kSize, kSize, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
}

static void checkRenderer(void)
{
    [NSApplication sharedApplication]; // registers the window system's display with CGL

    CGLPixelFormatAttribute attributes[] = {0};
    CGLPixelFormatObj format;
    GLint screens;
    CGLContextObj context;

    expect(CGLChoosePixelFormat(attributes, &format, &screens) == kCGLNoError, "CGLChoosePixelFormat");
    expect(CGLCreateContext(format, NULL, &context) == kCGLNoError, "CGLCreateContext");
    expect(CGLSetCurrentContext(context) == kCGLNoError, "surfaceless CGLSetCurrentContext");

    GLuint framebuffer, colorbuffer;
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glGenRenderbuffers(1, &colorbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, colorbuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, kSize, kSize);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorbuffer);
    expect(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "offscreen framebuffer");
    glViewport(0, 0, kSize, kSize);

    // Blue root, green 20x20 sublayer at (10, 10) in the root's coordinates,
    // red 4x4 sublayer at (0, 0) in the green one's.
    CALayer *root = layerWithFrame(CGRectMake(0, 0, kSize, kSize), 0, 0, 1);
    CALayer *child = layerWithFrame(CGRectMake(10, 10, 20, 20), 0, 1, 0);
    [root addSublayer: child];
    [child addSublayer: layerWithFrame(CGRectMake(0, 0, 4, 4), 1, 0, 0)];

    // A 2x2 image, red top row and white bottom row, as the contents of a
    // 20x20 layer at (60, 10).
    const uint32_t imagePixels[4] = {0xFFFF0000, 0xFFFF0000, 0xFFFFFFFF, 0xFFFFFFFF};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate((void *) imagePixels, 2, 2, 8, 8, space,
                                                kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGImageRef image = CGBitmapContextCreateImage(bitmap);
    CALayer *picture = layerWithFrame(CGRectMake(60, 10, 20, 20), 0, 0, 0);
    picture.contents = (id) image;
    picture.magnificationFilter = kCAFilterNearest;
    [root addSublayer: picture];

    CARenderer *renderer = [CARenderer rendererWithCGLContext: context options: nil];
    renderer.layer = root;
    GLubyte *pixels = malloc(4 * kSize * kSize);

    render(renderer, pixels);
    expect(isColor(pixelAt(pixels, 20, 80), 0, 255, 0) && isColor(pixelAt(pixels, 20, 20), 0, 0, 255),
           "unflipped: a sublayer at y = 10 is drawn near the bottom");
    expect(isColor(pixelAt(pixels, 11, 88), 255, 0, 0), "unflipped: a nested sublayer at y = 0 is at the bottom");
    expect(isColor(pixelAt(pixels, 70, 72), 255, 0, 0) && isColor(pixelAt(pixels, 70, 87), 255, 255, 255),
           "unflipped: a contents image is upright");

    root.geometryFlipped = YES;
    render(renderer, pixels);
    expect(isColor(pixelAt(pixels, 20, 20), 0, 255, 0) && isColor(pixelAt(pixels, 20, 80), 0, 0, 255),
           "flipped: a sublayer at y = 10 is drawn near the top");
    expect(isColor(pixelAt(pixels, 11, 12), 255, 0, 0), "flipped parent: a nested sublayer at y = 0 is at the top");
    expect(isColor(pixelAt(pixels, 70, 12), 255, 0, 0) && isColor(pixelAt(pixels, 70, 27), 255, 255, 255),
           "flipped: a contents image is still upright");

    // Flipped twice: the nested sublayer goes back to the bottom of its parent,
    // and an image is still upright.
    child.geometryFlipped = YES;
    picture.geometryFlipped = YES;
    render(renderer, pixels);
    expect(isColor(pixelAt(pixels, 11, 28), 255, 0, 0) && isColor(pixelAt(pixels, 11, 12), 0, 255, 0),
           "flipped twice: a nested sublayer at y = 0 is at the bottom of its parent");
    expect(isColor(pixelAt(pixels, 70, 12), 255, 0, 0) && isColor(pixelAt(pixels, 70, 27), 255, 255, 255),
           "flipped twice: a contents image is still upright");

    free(pixels);
    CGImageRelease(image);
    CGContextRelease(bitmap);
    CGColorSpaceRelease(space);
    CGLSetCurrentContext(NULL);
    CGLReleaseContext(context);
    CGLReleasePixelFormat(format);
}

int main(void)
{
    @autoreleasepool {
        CALayer *root = [CALayer layer];
        CALayer *child = [CALayer layer];
        CALayer *grandchild = [CALayer layer];
        [root addSublayer: child];
        [child addSublayer: grandchild];

        expect(!root.geometryFlipped && !root.isGeometryFlipped, "geometryFlipped defaults to NO");
        expect(![grandchild contentsAreFlipped], "nothing flipped: contents not flipped");
        root.geometryFlipped = YES;
        expect(root.isGeometryFlipped, "geometryFlipped round trip");
        expect([root contentsAreFlipped] && [grandchild contentsAreFlipped],
               "one flipped ancestor flips the layer and its descendants");
        grandchild.geometryFlipped = YES;
        expect(![grandchild contentsAreFlipped] && [child contentsAreFlipped],
               "two flipped layers on the path cancel out");

        checkDisplay();
        checkRenderer();
    }
    puts("PASS: CALayer geometryFlipped");
    return 0;
}
