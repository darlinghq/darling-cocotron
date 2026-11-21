// CARenderer follows a CAKeyframeAnimation (documented behaviour of
// https://developer.apple.com/documentation/quartzcore/cakeyframeanimation):
// linear mode interpolates between neighbouring values, keyTimes place the
// values in time (unusable ones, a NaN or a wrong count, are ignored), discrete
// mode holds a value until the next key time (one more key time than values), paced
// mode moves at constant speed, and a path makes the values ignored.
// Needs a GL-capable backend (X11 on Xvfb).
// Exit 2/3: no GL context; otherwise the number of failed checks.
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

#define W 64
#define H 64

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static unsigned char pixels[W * H * 4];
static CARenderer *renderer;
static CALayer *square;

static void render(void) {
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    [renderer render];
    glFinish();
    glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
}

static BOOL lit(int x, int y) {
    const unsigned char *p = pixels + (y * W + x) * 4;
    return p[0] > 200 && p[1] > 200 && p[2] > 200;
}

// An animation whose time is `fraction` of its (long) duration at the moment it renders.
static void run(CAKeyframeAnimation *animation, double fraction, NSString *key) {
    animation.duration = 1000;
    animation.beginTime = CACurrentMediaTime() - 1000 * fraction;
    animation.removedOnCompletion = NO;
    [square removeAllAnimations];
    [square addAnimation: animation forKey: key];
    render();
    [square removeAllAnimations];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect frame = NSMakeRect(0, 0, W, H);
        NSWindow *window = [[NSWindow alloc] initWithContentRect: frame
                                                      styleMask: NSBorderlessWindowMask
                                                        backing: NSBackingStoreBuffered
                                                          defer: NO];
        NSOpenGLView *view = [[NSOpenGLView alloc] initWithFrame: frame];
        [window setContentView: view];
        [view release];
        NSOpenGLContext *context = [view openGLContext];
        if (context == nil || [context CGLContextObj] == NULL)
            return 2;
        [view lockFocus];
        if (CGLGetCurrentContext() != [context CGLContextObj])
            return 3;
        glViewport(0, 0, W, H);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glOrtho(0, W, 0, H, -1, 1);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glPixelStorei(GL_PACK_ALIGNMENT, 1);

        CGColorRef white = CGColorCreateGenericRGB(1, 1, 1, 1);
        CALayer *root = [CALayer layer];
        root.anchorPoint = CGPointZero;
        root.position = CGPointZero;
        root.bounds = CGRectMake(0, 0, W, H);
        square = [CALayer layer];
        square.anchorPoint = CGPointZero;
        square.position = CGPointZero;
        square.bounds = CGRectMake(0, 0, 8, 8);
        square.backgroundColor = white;
        [root addSublayer: square];
        renderer = [CARenderer rendererWithCGLContext: [context CGLContextObj] options: nil];
        renderer.bounds = CGRectMake(0, 0, W, H);
        renderer.layer = root;

        // Linear, evenly spaced: a quarter of the way through three values
        // (0, 40, 0) is halfway to the middle one, x = 20.
        CAKeyframeAnimation *move = [CAKeyframeAnimation animationWithKeyPath: @"position"];
        move.values = @[[NSValue valueWithPoint: NSMakePoint(0, 0)], [NSValue valueWithPoint: NSMakePoint(40, 0)],
                        [NSValue valueWithPoint: NSMakePoint(0, 0)]];
        run(move, 0.25, @"position");
        CHECK(lit(24, 4), "linear: square at x = 20");
        CHECK(!lit(4, 4) && !lit(36, 4), "linear: nowhere else");

        // keyTimes move the middle value to 0.25: now at the middle value, x = 40.
        move.keyTimes = @[@0, @0.25, @1];
        run(move, 0.25, @"position");
        CHECK(lit(44, 4) && !lit(24, 4), "keyTimes: square at x = 40");

        // A timing function on the first span: ease-in is behind linear at half the span
        // (about x = 13 instead of 20).
        move.keyTimes = nil;
        move.timingFunctions = @[[CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseIn],
                                 [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionLinear]];
        run(move, 0.25, @"position");
        CHECK(lit(16, 4) && !lit(4, 4) && !lit(24, 4), "timing function of the span: behind the linear x = 20");

        // Paced: constant speed over spans of length 10 and 30 reaches the middle value at 0.25.
        CAKeyframeAnimation *paced = [CAKeyframeAnimation animationWithKeyPath: @"position"];
        paced.calculationMode = kCAAnimationPaced;
        paced.values = @[[NSValue valueWithPoint: NSMakePoint(0, 0)], [NSValue valueWithPoint: NSMakePoint(10, 0)],
                         [NSValue valueWithPoint: NSMakePoint(40, 0)]];
        run(paced, 0.25, @"position");
        CHECK(lit(14, 4) && !lit(4, 4), "paced: square at x = 10");

        // Discrete: two values need three key times; the first value holds until 0.8
        // (evenly spaced key times would switch at 0.5, so ignoring them shows).
        CAKeyframeAnimation *blink = [CAKeyframeAnimation animationWithKeyPath: @"opacity"];
        blink.calculationMode = kCAAnimationDiscrete;
        blink.values = @[@0.0, @1.0];
        blink.keyTimes = @[@0, @0.8, @1];
        run(blink, 0.6, @"opacity");
        CHECK(!lit(4, 4), "discrete: first value held before the second key time");
        run(blink, 0.9, @"opacity");
        CHECK(lit(4, 4), "discrete: second value after it");

        // QUIRK (observed on macOS 26.7.3): a discrete animation may also have as many key
        // times as values; each value holds from its key time to the next and the last one
        // is not reached before the end.
        CAKeyframeAnimation *three = [CAKeyframeAnimation animationWithKeyPath: @"opacity"];
        three.calculationMode = kCAAnimationDiscrete;
        three.values = @[@0.0, @1.0, @0.0];
        three.keyTimes = @[@0, @0.5, @1];
        run(three, 0.4, @"opacity");
        CHECK(!lit(4, 4), "discrete, as many key times as values: first value");
        run(three, 0.6, @"opacity");
        CHECK(lit(4, 4), "discrete, as many key times as values: second value");
        run(three, 0.9, @"opacity");
        CHECK(lit(4, 4), "discrete, as many key times as values: the last value is not reached");

        // QUIRK (observed on macOS 26.7.3): an animation of a single value shows nothing: the
        // layer stays at its model value, here opaque, not the value given.
        CAKeyframeAnimation *single = [CAKeyframeAnimation animationWithKeyPath: @"opacity"];
        single.values = @[@0.0];
        run(single, 0.5, @"opacity");
        CHECK(lit(4, 4), "a single value: the layer keeps its model value");

        // key times that are not usable are ignored: a NaN, then a count that does not match.
        move.timingFunctions = nil;
        move.keyTimes = @[@0, @(NAN), @1];
        run(move, 0.25, @"position");
        CHECK(lit(24, 4) && !lit(44, 4), "NaN key time: ignored, evenly spaced (x = 20)");
        // QUIRK (observed on macOS 26.7.3): fewer key times than values are used for the
        // leading values only: 0 -> 40 over the whole animation, x = 10 at a quarter.
        move.keyTimes = @[@0, @1];
        run(move, 0.25, @"position");
        CHECK(lit(14, 4) && !lit(4, 4) && !lit(24, 4), "fewer key times than values: the leading values only");
        // QUIRK: more key times than values, the surplus ones are not used.
        move.keyTimes = @[@0, @0.25, @1, @1];
        run(move, 0.25, @"position");
        CHECK(lit(44, 4) && !lit(24, 4), "more key times than values: the leading ones");
        // QUIRK: key times that do not start at 0 or end at 1 are used as they are, the first
        // value showing before the first key time and the last after the last.
        move.keyTimes = @[@0.5, @0.75, @1];
        run(move, 0.25, @"position");
        CHECK(lit(4, 4) && !lit(24, 4), "first key time 0.5: the first value before it");
        move.keyTimes = @[@0, @0.1, @0.2];
        run(move, 0.25, @"position");
        CHECK(lit(4, 4) && !lit(44, 4), "last key time 0.2: the last value after it");

        // With a path set the values are ignored: the layer stays at its model value (x = 0).
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddLineToPoint(path, NULL, 40, 0);
        move.keyTimes = nil;
        move.path = path;
        CGPathRelease(path);
        run(move, 0.25, @"position");
        CHECK(lit(4, 4) && !lit(24, 4), "path set: values ignored, model value");
        move.path = NULL;

        // Linear opacity between 0 and 1 reaches full white only at the end.
        CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath: @"opacity"];
        fade.values = @[@0.0, @1.0];
        run(fade, 0.5, @"opacity");
        CHECK(!lit(4, 4), "linear opacity at 0.5 is not opaque");
        run(fade, 1.0, @"opacity");
        CHECK(lit(4, 4), "linear opacity at the end is opaque");

        CGColorRelease(white);
        CHECK(glGetError() == GL_NO_ERROR, "GL error");
        [view unlockFocus];
        [NSOpenGLContext clearCurrentContext];
        [window release];
        if (failures == 0)
            puts("PASS: CAKeyframeAnimation rendering");
        return failures != 0;
    }
}
