/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CoreGraphics.framework re-exports /usr/lib/swift/libswiftCoreGraphics.dylib, so a symbol of the Swift
 * CoreGraphics overlay resolves when looked up through the CoreGraphics image, and loading CoreGraphics
 * loads the overlay image. Run in the x86_64 and arm64 guests alike.
 */
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>

static int image_loaded(const char *suffix)
{
	size_t sl = strlen(suffix);
	for (uint32_t i = 0; i < _dyld_image_count(); i++) {
		const char *n = _dyld_get_image_name(i);
		size_t nl = n ? strlen(n) : 0;
		if (nl >= sl && strcmp(n + nl - sl, suffix) == 0)
			return 1;
	}
	return 0;
}

int main(void)
{
	int failures = 0;
	void *cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
	if (!cg) {
		printf("FAIL: dlopen CoreGraphics: %s\n", dlerror());
		return 1;
	}
	if (!image_loaded("/usr/lib/swift/libswiftCoreGraphics.dylib")) {
		printf("FAIL: libswiftCoreGraphics.dylib was not loaded with CoreGraphics\n");
		failures++;
	}
	/* CGContextRef.addLine(to:), an entry point of the Swift CoreGraphics overlay. */
	const char *sym = "$sSo12CGContextRefa12CoreGraphicsE7addLine2toySo7CGPointV_tF";
	if (!dlsym(cg, sym)) {
		printf("FAIL: %s not found through CoreGraphics: %s\n", sym, dlerror());
		failures++;
	}
	if (failures == 0)
		printf("PASS: CoreGraphics re-exports the Swift overlay\n");
	return failures != 0;
}
