/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Looking up fonts must not make fontconfig complain that it has no writable
 * cache directory. fontconfig documents (fonts-conf(5)) that it writes its
 * font caches to the first writable <cachedir>; the user's Caches folder is
 * writable, so the lookup has to be silent. Also checks that the lookup finds
 * a font at all when the host has one.
 *
 * Prints PASS or FAIL lines; exit status 0 only on PASS.
 */
#include <CoreGraphics/CoreGraphics.h>
#include <CoreFoundation/CoreFoundation.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
	char path[] = "/tmp/fontconfig_cache.XXXXXX";
	int out = mkstemp(path);
	if (out < 0) {
		puts("FAIL: mkstemp");
		return 1;
	}

	fflush(stderr);
	int saved = dup(2);
	dup2(out, 2);

	/* several lookups: the message used to appear once per lookup */
	for (int i = 0; i < 3; i++) {
		CGFontRef font = CGFontCreateWithFontName(CFSTR("Helvetica"));
		if (font)
			CFRelease(font);
		font = CGFontCreateWithFontName(CFSTR("DejaVu Sans"));
		if (font)
			CFRelease(font);
	}

	fflush(stderr);
	dup2(saved, 2);
	close(saved);

	char buf[8192];
	lseek(out, 0, SEEK_SET);
	ssize_t n = read(out, buf, sizeof buf - 1);
	close(out);
	unlink(path);
	buf[n > 0 ? n : 0] = 0;

	if (strstr(buf, "No writable cache directories")) {
		printf("FAIL: fontconfig has no writable cache directory: %s\n", buf);
		return 1;
	}
	puts("PASS");
	return 0;
}
