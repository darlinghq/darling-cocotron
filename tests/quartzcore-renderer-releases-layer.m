// Copyright (C) 2026 Lubos Dolezel
//
// CARenderer's layer property is declared retain. By the Cocoa memory
// management rules an object that took ownership by retaining a value gives it
// up when it is itself deallocated:
// https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmRules.html
// https://developer.apple.com/documentation/quartzcore/carenderer/layer
// Exit 1: the layer outlived its renderer; 2: replacing the layer did not
// release the old one; 3: the renderer did not retain its layer; 0: correct.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int liveLayers;

@interface CountedLayer : CALayer
@end

@implementation CountedLayer
- (id)init {
    if ((self = [super init]))
        liveLayers++;
    return self;
}
- (void)dealloc {
    liveLayers--;
    [super dealloc];
}
@end

int main(void) {
    @autoreleasepool {
        CARenderer *renderer = [[CARenderer alloc] init];
        CountedLayer *first = [[CountedLayer alloc] init];
        renderer.layer = first;
        [first release];
        if (liveLayers != 1) {
            fprintf(stderr, "layer not retained by the renderer: %d\n", liveLayers);
            return 3;
        }

        CountedLayer *second = [[CountedLayer alloc] init];
        renderer.layer = second;
        [second release];
        if (liveLayers != 1) {
            fprintf(stderr, "replaced layer still alive: %d\n", liveLayers);
            return 2;
        }

        [renderer release];
        if (liveLayers != 0) {
            fprintf(stderr, "layer outlived its renderer: %d\n", liveLayers);
            return 1;
        }
        puts("PASS: CARenderer releases its layer");
        return 0;
    }
}
