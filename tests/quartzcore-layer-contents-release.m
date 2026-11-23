// Copyright (C) 2026 Lubos Dolezel
//
// CALayer's contents property is declared retain, and the Cocoa memory
// management rules say an object that took ownership by retaining a value gives
// it up when it is itself deallocated:
// https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmRules.html
// A layer that is freed must therefore release the object set as its contents.
// Exit 1: the contents object outlived its layer; 2: replacing the contents did
// not release the old object; 3: the layer did not retain its contents; 0: correct.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int liveContents;

@interface ContentsProbe : NSObject
@end

@implementation ContentsProbe
- (id)init {
    if ((self = [super init]))
        liveContents++;
    return self;
}
- (void)dealloc {
    liveContents--;
    [super dealloc];
}
@end

int main(void) {
    @autoreleasepool {
        CALayer *layer = [[CALayer alloc] init];
        ContentsProbe *first = [[ContentsProbe alloc] init];
        layer.contents = first;
        [first release];
        if (liveContents != 1) {
            fprintf(stderr, "contents not retained by the layer: %d\n", liveContents);
            return 3;
        }

        ContentsProbe *second = [[ContentsProbe alloc] init];
        layer.contents = second;
        [second release];
        if (liveContents != 1) {
            fprintf(stderr, "replaced contents still alive: %d\n", liveContents);
            return 2;
        }

        [layer release];
        if (liveContents != 0) {
            fprintf(stderr, "contents outlived its layer: %d\n", liveContents);
            return 1;
        }
        puts("PASS: CALayer releases its contents");
        return 0;
    }
}
