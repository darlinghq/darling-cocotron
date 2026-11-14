// Copyright (C) 2026 Lubos Dolezel
// The CoreAnimation umbrella header must be usable by a client: every header it imports has to be one
// the framework installs. Compiling this file is the test.
#import <QuartzCore/CoreAnimation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

int main(void) {
	@autoreleasepool {
		CALayer *layer = [CALayer layer];
		printf(layer != nil ? "PASS\n" : "FAIL\n");
		return layer == nil;
	}
}
