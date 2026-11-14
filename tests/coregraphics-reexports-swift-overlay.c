/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CoreGraphics.framework re-exports /usr/lib/swift/libswiftCoreGraphics.dylib, so a symbol of the Swift
 * CoreGraphics overlay resolves when looked up through the CoreGraphics image, and loading CoreGraphics
 * loads the overlay image. Run in the x86_64 and arm64 guests alike.
 */
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdio.h>
#include <string.h>

#ifdef __LP64__
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

/* Whether the image whose path ends in image_suffix carries an LC_REEXPORT_DYLIB for the install name `reexported`.
 * dlsym through a handle can also see symbols of plain dependencies, so only the load command proves a re-export. */
static int image_reexports(const char *image_suffix, const char *reexported)
{
	size_t sl = strlen(image_suffix);
	for (uint32_t i = 0; i < _dyld_image_count(); i++) {
		const char *n = _dyld_get_image_name(i);
		size_t nl = n ? strlen(n) : 0;
		if (nl < sl || strcmp(n + nl - sl, image_suffix) != 0)
			continue;
		const struct mach_header_64 *mh = (const struct mach_header_64 *) _dyld_get_image_header(i);
		const struct load_command *lc = (const struct load_command *) (mh + 1);
		for (uint32_t c = 0; c < mh->ncmds; c++) {
			if (lc->cmd == LC_REEXPORT_DYLIB) {
				const struct dylib_command *dc = (const struct dylib_command *) lc;
				if (strcmp((const char *) dc + dc->dylib.name.offset, reexported) == 0)
					return 1;
			}
			lc = (const struct load_command *) ((const char *) lc + lc->cmdsize);
		}
	}
	return 0;
}
#endif

int main(void)
{
	int failures = 0;
	void *cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
	if (!cg) {
		printf("FAIL: dlopen CoreGraphics: %s\n", dlerror());
		return 1;
	}
#ifdef __LP64__
	/* The Swift overlays are built for 64-bit only; the 32-bit CoreGraphics must merely keep loading. */
	if (!image_loaded("/usr/lib/swift/libswiftCoreGraphics.dylib")) {
		printf("FAIL: libswiftCoreGraphics.dylib was not loaded with CoreGraphics\n");
		failures++;
	}
	if (!image_reexports("/CoreGraphics.framework/Versions/A/CoreGraphics", "/usr/lib/swift/libswiftCoreGraphics.dylib")) {
		printf("FAIL: CoreGraphics has no LC_REEXPORT_DYLIB for the Swift overlay\n");
		failures++;
	}
	/* CGContextRef.addLine(to:), an entry point of the Swift CoreGraphics overlay. */
	const char *sym = "$sSo12CGContextRefa12CoreGraphicsE7addLine2toySo7CGPointV_tF";
	if (!dlsym(cg, sym)) {
		printf("FAIL: %s not found through CoreGraphics: %s\n", sym, dlerror());
		failures++;
	}
#endif
	if (failures == 0)
		printf("PASS: CoreGraphics re-exports the Swift overlay\n");
	return failures != 0;
}
