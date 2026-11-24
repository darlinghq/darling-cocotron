/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * <QuartzCore/QuartzCore.h> and <QuartzCore/CoreAnimation.h> can be included from C and give the
 * C parts (CATransform3D and its functions); the Objective-C classes are only declared for
 * Objective-C, as in Apple's headers.
 */
#include <QuartzCore/QuartzCore.h>
#include <QuartzCore/CoreAnimation.h>
#include <stdio.h>

int main(void)
{
	CATransform3D scale = CATransform3DMakeScale(2, 3, 4);
	CATransform3D identity = CATransform3DIdentity;
	int ok = scale.m11 == 2 && scale.m22 == 3 && scale.m33 == 4 && CATransform3DIsIdentity(identity)
		&& !CATransform3DIsIdentity(scale);
	printf("%s QuartzCore umbrella headers from C\n", ok ? "PASS" : "FAIL");
	return ok ? 0 : 1;
}
