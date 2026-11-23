// Copyright (C) 2026 Lubos Dolezel
//
// A layer tree that does not change is not composited again: no frame is drawn
// or presented while nothing is set, and none when properties and contents are
// set to the values they already have (as a layer tree that is updated from
// the model every frame does), neither in the window's tree nor in a remote
// context that a CALayerHost shows. A change that shows (a different colour,
// pixels written into a surface that is then set as the contents again) draws
// a frame.
//
// Composites are counted at CALayerContext's -renderLayerTree:, the drawing of
// a window's tree, and at the remote context's -render.
//
// Needs a display server (Xvfb for X11, a compositor for Wayland).
// Exit 2: no window system; otherwise the number of failures.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurface.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

typedef uint32_t CAContextID;

@interface CAContext : NSObject
+ (instancetype) remoteContext;
@property(readonly) CAContextID contextId;
@property(retain) CALayer *layer;
@end

@interface CALayerHost : CALayer
@property CAContextID contextId;
@end

static int failures;

#define CHECK(cond, ...) do { if (!(cond)) { fprintf(stderr, "FAIL %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); failures++; } } while (0)

static unsigned composites, remoteRenders;

static void countCalls(Class cls, SEL sel, unsigned *counter) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m == NULL)
        return;
    IMP original = method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^(id self, id arg) {
        (*counter)++;
        return ((id (*)(id, SEL, id)) original)(self, sel, arg);
    }));
}

static void countVoidCalls(Class cls, SEL sel, unsigned *counter) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m == NULL)
        return;
    IMP original = method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^(id self) {
        (*counter)++;
        ((void (*)(id, SEL)) original)(self, sel);
    }));
}

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static IOSurfaceRef makeSurface(int w, int h) {
    NSDictionary *props = @{
        (NSString *) kIOSurfaceWidth : @(w),
        (NSString *) kIOSurfaceHeight : @(h),
        (NSString *) kIOSurfaceBytesPerElement : @4,
        (NSString *) kIOSurfacePixelFormat : @((uint32_t) 'BGRA'),
    };
    return IOSurfaceCreate((CFDictionaryRef) props);
}

static void writeSurface(IOSurfaceRef s, uint8_t v) {
    IOSurfaceLock(s, 0, NULL);
    memset(IOSurfaceGetBaseAddress(s), v, IOSurfaceGetBytesPerRow(s) * IOSurfaceGetHeight(s));
    IOSurfaceUnlock(s, 0, NULL);
}

// Sets every property of the layer that asks for a frame to the value it has.
static void setPropertiesToTheirValues(CALayer *layer) {
    layer.backgroundColor = layer.backgroundColor;
    layer.borderColor = layer.borderColor;
    layer.borderWidth = layer.borderWidth;
    layer.cornerRadius = layer.cornerRadius;
    layer.masksToBounds = layer.masksToBounds;
    layer.hidden = layer.hidden;
    layer.zPosition = layer.zPosition;
    layer.transform = layer.transform;
    layer.sublayerTransform = layer.sublayerTransform;
    layer.contentsScale = layer.contentsScale;
    layer.contentsRect = layer.contentsRect;
    layer.contentsCenter = layer.contentsCenter;
    layer.contentsGravity = layer.contentsGravity;
    layer.shadowOpacity = layer.shadowOpacity;
    layer.shadowRadius = layer.shadowRadius;
    layer.shadowOffset = layer.shadowOffset;
    layer.shadowColor = layer.shadowColor;
    layer.geometryFlipped = layer.geometryFlipped;
    layer.opacity = layer.opacity;
    layer.position = layer.position;
    layer.bounds = layer.bounds;
    layer.anchorPoint = layer.anchorPoint;
    layer.contents = layer.contents;
    layer.sublayers = layer.sublayers;
    // A new colour object of the same colour.
    CGColorRef background = layer.backgroundColor;
    if (background != NULL) {
        CGColorRef copy = CGColorCreateCopy(background);
        layer.backgroundColor = copy;
        CGColorRelease(copy);
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        countCalls(NSClassFromString(@"CALayerContext"), @selector(renderLayerTree:), &composites);
        countVoidCalls(NSClassFromString(@"CARemoteLayerContext"), @selector(render), &remoteRenders);

        const int kWidth = 320, kHeight = 200;
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(50, 50, kWidth, kHeight)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        NSView *content = [window contentView];
        [content setWantsLayer: YES];
        CALayer *root = content.layer;

        CALayer *background = [CALayer layer];
        background.frame = CGRectMake(0, 0, kWidth, kHeight);
        CGColorRef gray = CGColorCreateGenericRGB(0.8, 0.8, 0.8, 1);
        background.backgroundColor = gray;
        CGColorRelease(gray);
        [root addSublayer: background];

        IOSurfaceRef surface = makeSurface(64, 64);
        if (surface == NULL)
            return 2;
        writeSurface(surface, 100);
        CALayer *surfaceLayer = [CALayer layer];
        surfaceLayer.frame = CGRectMake(10, 10, 64, 64);
        surfaceLayer.contents = (id) surface;
        [root addSublayer: surfaceLayer];

        // A remote context and its host.
        CALayer *remoteRoot = [CALayer layer];
        remoteRoot.frame = CGRectMake(0, 0, 64, 64);
        CGColorRef blue = CGColorCreateGenericRGB(0, 0, 1, 1);
        remoteRoot.backgroundColor = blue;
        CGColorRelease(blue);
        IOSurfaceRef remoteSurface = makeSurface(32, 32);
        writeSurface(remoteSurface, 50);
        CALayer *remoteContent = [CALayer layer];
        remoteContent.frame = CGRectMake(4, 4, 32, 32);
        remoteContent.contents = (id) remoteSurface;
        [remoteRoot addSublayer: remoteContent];
        CAContext *remote = [CAContext remoteContext];
        if (remote == nil)
            return 2;
        remote.layer = remoteRoot;
        CALayerHost *host = [CALayerHost layer];
        host.frame = CGRectMake(100, 10, 64, 64);
        host.contextId = remote.contextId;
        [root addSublayer: host];

        [window makeKeyAndOrderFront: nil];
        spin(2);
        if (composites == 0) {
            fprintf(stderr, "SKIP: the window's tree is never composited here\n");
            return 2;
        }

        // Nothing is set: nothing is drawn.
        composites = remoteRenders = 0;
        spin(1.5);
        CHECK(composites == 0, "idle tree: %u composites in 1.5 s", composites);
        CHECK(remoteRenders == 0, "idle remote tree: %u renders in 1.5 s", remoteRenders);

        // Setting what is there draws nothing.
        for (int i = 0; i < 20; i++) {
            setPropertiesToTheirValues(background);
            setPropertiesToTheirValues(surfaceLayer);
            setPropertiesToTheirValues(host);
            setPropertiesToTheirValues(remoteRoot);
            setPropertiesToTheirValues(remoteContent);
            spin(0.05);
        }
        // QUIRK (see CALayer.m -setPosition:): no implicit animation is added
        // for a property set to the value it has, observed on macOS 26.7.3.
        // Pins the quirk: an animation would still be running here.
        for (CALayer *layer in @[ background, surfaceLayer, host, remoteRoot, remoteContent ])
            CHECK([[layer animationKeys] count] == 0, "implicit animations after same-value sets: %lu",
                  (unsigned long) [[layer animationKeys] count]);
        spin(0.3);
        CHECK(composites == 0, "properties set to their values: %u composites", composites);
        CHECK(remoteRenders == 0, "remote properties set to their values: %u renders", remoteRenders);

        // The same surface set again, its pixels not written to.
        composites = remoteRenders = 0;
        for (int i = 0; i < 10; i++) {
            surfaceLayer.contents = (id) surface;
            remoteContent.contents = (id) remoteSurface;
            spin(0.05);
        }
        spin(0.3);
        CHECK(composites == 0, "an unwritten surface set again: %u composites", composites);
        CHECK(remoteRenders == 0, "a remote unwritten surface set again: %u renders", remoteRenders);

        // Changes that show draw a frame.
        composites = 0;
        CGColorRef red = CGColorCreateGenericRGB(1, 0, 0, 1);
        background.backgroundColor = red;
        CGColorRelease(red);
        spin(0.4);
        CHECK(composites >= 1, "a new colour: %u composites", composites);

        composites = 0;
        writeSurface(surface, 200);
        surfaceLayer.contents = (id) surface;
        spin(0.4);
        CHECK(composites >= 1, "a written surface set again: %u composites", composites);

        composites = remoteRenders = 0;
        writeSurface(remoteSurface, 150);
        remoteContent.contents = (id) remoteSurface;
        spin(0.5);
        CHECK(remoteRenders >= 1, "a written remote surface set again: %u renders", remoteRenders);
        CHECK(composites >= 1, "the host of a changed remote tree: %u composites", composites);

        // And idle again.
        composites = remoteRenders = 0;
        spin(1);
        CHECK(composites == 0, "idle again: %u composites", composites);
        CHECK(remoteRenders == 0, "idle again: %u remote renders", remoteRenders);
    }
    if (failures == 0)
        printf("PASS\n");
    return failures;
}
