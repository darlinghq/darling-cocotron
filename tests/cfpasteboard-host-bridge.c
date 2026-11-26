// Copyright (C) 2026 Lubos Dolezel
//
// Helper of cfpasteboard-host-bridge.sh: a process of CoreGraphics and the Pasteboard Manager with no AppKit.
// The general pasteboard of CoreFoundation shows the host's clipboard in such a process too, because CoreGraphics
// owns the connection to the window system and connects them (AppKit's NSPasteboard is only a view of the same
// pasteboard).
//   copy TEXT SECONDS    puts TEXT (and <b>TEXT</b> as public.html) on the clipboard and keeps running, serving it
//   paste SECONDS TEXT   runs until the clipboard holds TEXT as UTF-8 text (exit 0) or SECONDS have passed (exit 1)
//   pastehtml SECONDS TEXT   the same for a public.html flavor that contains TEXT
//   hold SECONDS         only runs for SECONDS
// With HOSTCLIP_WINDOW set the process also shows a Carbon window: a Wayland compositor only tells a client about
// the clipboard (and takes it from one) while a window of the client has the keyboard focus.
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static CFStringRef const kText = CFSTR("public.utf8-plain-text");
static CFStringRef const kHTML = CFSTR("public.html");

static void run(double seconds, int (*done)(void *), void *info)
{
	CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + seconds;
	while (CFAbsoluteTimeGetCurrent() < end && !(done != NULL && done(info)))
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
}

struct pasteWait { PasteboardRef pb; CFStringRef type; const char *text; int contains; char *got; };

// The data of the first item's flavor of the given type as a C string, or NULL.
static char *flavorString(PasteboardRef pb, CFStringRef type)
{
	ItemCount count = 0;
	PasteboardItemID item;
	CFDataRef data = NULL;
	PasteboardSynchronize(pb);
	if (PasteboardGetItemCount(pb, &count) != noErr || count < 1 || PasteboardGetItemIdentifier(pb, 1, &item) != noErr ||
	    PasteboardCopyItemFlavorData(pb, item, type, &data) != noErr || data == NULL)
		return NULL;
	char *s = malloc((size_t)CFDataGetLength(data) + 1);
	memcpy(s, CFDataGetBytePtr(data), (size_t)CFDataGetLength(data));
	s[CFDataGetLength(data)] = 0;
	CFRelease(data);
	return s;
}

static int pasted(void *info)
{
	struct pasteWait *w = info;
	free(w->got);
	w->got = flavorString(w->pb, w->type);
	return w->got != NULL && (w->contains ? strstr(w->got, w->text) != NULL : strcmp(w->got, w->text) == 0);
}

int main(int argc, char **argv)
{
	if (argc < 2)
		return 2;
	// A process with a window system connection has the pasteboard bridged to the host's clipboard from the moment
	// CoreGraphics opens the connection, which has to be before the process makes its first pasteboard. Asking for
	// the main display opens it.
	CGDirectDisplayID display = CGMainDisplayID();
	if (display == 0 || CGDisplayPixelsWide(display) == 0) {
		printf("no display\n");
		return 3;
	}
	if (getenv("HOSTCLIP_WINDOW") != NULL) {
		Rect bounds = {100, 100, 300, 400};
		WindowRef window = NULL;
		OSStatus status = CreateNewWindow(kDocumentWindowClass, kWindowStandardDocumentAttributes | kWindowCompositingAttribute, &bounds, &window);
		if (status != noErr) {
			printf("no window (%d)\n", (int)status);
			return 5;
		}
		ShowWindow(window);
	}

	PasteboardRef pb = NULL;
	if (PasteboardCreate(kPasteboardClipboard, &pb) != noErr)
		return 4;
	if (strcmp(argv[1], "copy") == 0 && argc == 4) {
		CFDataRef text = CFDataCreate(NULL, (const UInt8 *)argv[2], (CFIndex)strlen(argv[2]));
		char html[1024];
		snprintf(html, sizeof(html), "<b>%s</b>", argv[2]);
		CFDataRef htmlData = CFDataCreate(NULL, (const UInt8 *)html, (CFIndex)strlen(html));
		PasteboardClear(pb);
		PasteboardSynchronize(pb);
		PasteboardPutItemFlavor(pb, (PasteboardItemID)1, kText, text, kPasteboardFlavorNoFlags);
		PasteboardPutItemFlavor(pb, (PasteboardItemID)1, kHTML, htmlData, kPasteboardFlavorNoFlags);
		printf("copied %s\n", argv[2]);
		fflush(stdout);
		run(atof(argv[3]), NULL, NULL);
		return 0;
	}
	if (strcmp(argv[1], "hold") == 0 && argc == 3) {
		printf("ready\n");
		fflush(stdout);
		run(atof(argv[2]), NULL, NULL);
		return 0;
	}
	if ((strcmp(argv[1], "paste") == 0 || strcmp(argv[1], "pastehtml") == 0) && argc == 4) {
		printf("ready\n");
		fflush(stdout);
		struct pasteWait w = {pb, strcmp(argv[1], "paste") == 0 ? kText : kHTML, argv[3], strcmp(argv[1], "paste") != 0, NULL};
		run(atof(argv[2]), pasted, &w);
		int ok = pasted(&w);
		printf("%s\n", w.got != NULL ? w.got : "(nothing)");
		return ok ? 0 : 1;
	}
	return 2;
}
