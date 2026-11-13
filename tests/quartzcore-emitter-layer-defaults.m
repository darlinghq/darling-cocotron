// Copyright (C) 2026 Lubos Dolezel
//
// CAEmitterLayer starts with the documented defaults (rates, velocity, scale
// and spin 1; point shape, volume mode, unordered rendering) and
// -initWithLayer: makes a copy with the defaults. Passes on macOS.
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

int main(void) {
    @autoreleasepool {
        CAEmitterLayer *e = [CAEmitterLayer layer];
        CHECK(e.birthRate == 1 && e.lifetime == 1, "birthRate/lifetime default");
        CHECK(e.velocity == 1 && e.scale == 1 && e.spin == 1, "velocity/scale/spin default");
        CHECK(e.seed == 0 && !e.preservesDepth, "seed/preservesDepth default");
        CHECK([e.emitterShape isEqualToString: kCAEmitterLayerPoint], "shape default %s", [e.emitterShape UTF8String]);
        CHECK([e.emitterMode isEqualToString: kCAEmitterLayerVolume], "mode default");
        CHECK([e.renderMode isEqualToString: kCAEmitterLayerUnordered], "renderMode default");
        CHECK(e.emitterCells == nil, "no cells by default");
        CHECK(e.emitterPosition.x == 0 && e.emitterSize.width == 0, "geometry default");

        e.birthRate = 7;
        e.emitterShape = kCAEmitterLayerCircle;
        e.emitterMode = kCAEmitterLayerOutline;
        e.renderMode = kCAEmitterLayerAdditive;
        e.emitterPosition = CGPointMake(3, 4);
        e.emitterCells = @[ [[CAEmitterCell alloc] init] ];

        // -[CALayer initWithLayer:] leaves the emitter state at the defaults.
        CAEmitterLayer *copy = [[CAEmitterLayer alloc] initWithLayer: e];
        CHECK(copy.birthRate == 1 && copy.velocity == 1, "copy birthRate/velocity are the defaults");
        CHECK([copy.emitterShape isEqualToString: kCAEmitterLayerPoint], "copy shape is the default");
        CHECK([copy.renderMode isEqualToString: kCAEmitterLayerUnordered], "copy render mode is the default");
        CHECK(copy.emitterCells == nil && copy.emitterPosition.x == 0, "copy has no cells or position");

        // Names of the constants.
        CHECK([kCAEmitterLayerLine isEqualToString: @"line"] && [kCAEmitterLayerOldestFirst isEqualToString: @"oldestFirst"],
              "constant values");
        if (failures == 0) puts("PASS: CAEmitterLayer defaults");
        return failures != 0;
    }
}
