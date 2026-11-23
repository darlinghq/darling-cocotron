/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The first NSDocumentController that is created becomes the shared document
 * controller, however it was created, and stays alive for the life of the
 * application: an application that creates its own (subclass) instance early,
 * for instance from +load, and releases it still finds it from
 * +sharedDocumentController, and the application uses it when it launches.
 *
 * Usage: appkit-document-controller-first-instance-shared
 * Prints PASS/FAIL lines; exit status 1 on failure. No ARC.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static BOOL controllerDeallocated;

static void expect(BOOL ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	if (!ok)
		failures++;
}

@interface FirstController : NSDocumentController
@end

@implementation FirstController
- (void)dealloc
{
	controllerDeallocated = YES;
	[super dealloc];
}
@end

int main(void)
{
	setvbuf(stdout, NULL, _IOLBF, 0);
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	// An early instance, created and released by the application (here also
	// autoreleased, as +load code does under its own pool).
	NSDocumentController *early = [[[FirstController alloc] init] autorelease];
	void *earlyAddress = early;
	[pool drain];
	pool = [[NSAutoreleasePool alloc] init];

	expect(!controllerDeallocated, "the first controller is not deallocated when its creator lets go");

	NSDocumentController *shared = [NSDocumentController sharedDocumentController];
	expect(shared == earlyAddress, "the shared controller is the first one created");
	expect([shared isKindOfClass: [FirstController class]], "the shared controller keeps its class");
	expect([shared documents] != nil, "the shared controller is usable");

	// A second instance does not replace it.
	NSDocumentController *second = [[NSDocumentController alloc] init];
	expect([NSDocumentController sharedDocumentController] == shared,
		   "a later instance does not become the shared controller");
	[second release];
	expect(!controllerDeallocated, "the shared controller outlives other instances");

	[pool drain];
	return failures != 0;
}
