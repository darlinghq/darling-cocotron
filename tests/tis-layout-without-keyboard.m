// Copyright (C) 2026 Lubos Dolezel
//
// The Text Input Sources API describes a keyboard layout in every session:
// TISCopyCurrentKeyboardLayoutInputSource() returns an input source with a
// language list and 'uchr' layout data, also when the window system's seat has
// no keyboard (a headless Wayland compositor with no input devices).
// Run under the window-system backend to be tested (X11 or Wayland).
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#include <stdio.h>

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 200, 100)
		                                          styleMask:NSWindowStyleMaskTitled
		                                            backing:NSBackingStoreBuffered defer:NO];
		[w makeKeyAndOrderFront:nil];
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
		int failures = 0;
		TISInputSourceRef src = TISCopyCurrentKeyboardLayoutInputSource();
		if (src == NULL) { printf("FAIL: no input source\n"); return 1; }
		if (TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) == NULL) { printf("FAIL: no languages\n"); failures++; }
		CFDataRef data = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData);
		if (data == NULL || CFDataGetLength(data) == 0) { printf("FAIL: no layout data\n"); failures++; }
		CFRelease(src);
		printf(failures ? "FAIL\n" : "PASS\n");
		return failures;
	}
}
