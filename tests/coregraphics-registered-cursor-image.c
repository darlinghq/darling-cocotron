/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * CGSCreateRegisteredCursorImage(): a cursor name that is not registered gives
 * NULL and leaves the hot spot untouched, and the hot spot pointer is optional.
 * Registered names (the arrow, the cursor currently shown) give an image on
 * macOS; here no cursor image can be read, so the result for them is not
 * checked beyond not crashing and, when there is an image, it having a size.
 */
#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <stdio.h>

typedef CGImageRef (*CreateFn)(int, const char *, CGPoint *);
typedef int (*ConnectionFn)(void);

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } } while (0)

int main(void)
{
	CreateFn create = (CreateFn) dlsym(RTLD_DEFAULT, "CGSCreateRegisteredCursorImage");
	ConnectionFn mainConnection = (ConnectionFn) dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
	if (!create || !mainConnection) {
		printf("FAIL: symbols missing\n");
		return 1;
	}
	int cid = mainConnection();

	CGPoint hotspot = { -7, -7 };
	CGImageRef image = create(cid, "no.such.cursor", &hotspot);
	CHECK(image == NULL, "an unregistered name gives NULL");
	CHECK(hotspot.x == -7 && hotspot.y == -7, "the hot spot is left alone");

	hotspot = (CGPoint) { -7, -7 };
	image = create(cid, "com.apple.coregraphics.GlobalCurrent", &hotspot);
	if (image) {
		CHECK(CGImageGetWidth(image) > 0 && CGImageGetHeight(image) > 0, "a cursor image has a size");
		CFRelease(image);
	}
	image = create(cid, "com.apple.coregraphics.GlobalCurrent", NULL);
	if (image)
		CFRelease(image);
	image = create(cid, "no.such.cursor", NULL);
	CHECK(image == NULL, "an unregistered name gives NULL without a hot spot pointer");

	if (failures == 0)
		printf("PASS\n");
	return failures ? 1 : 0;
}
