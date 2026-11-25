// CFLAGS: -framework AppKit -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// Code that looks a font family up by name (browser engines do) scans -[NSFontManager availableFontFamilies]
// case-insensitively and then asks -availableMembersOfFontFamily: and +[NSFont fontWithName:size:] for
// the match. The families every macOS provides must therefore be in the list, and the lookup must end in
// a font. Observed on macOS 10.14.4 and 26.7.3 (26.7.3 lacks Times and Courier in the list; Mojave
// has them, so they are required only where the list is Mojave's, see below).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL: %s (line %d)\n", #c, __LINE__); failures++; } } while (0)

static NSString *listedName(NSString *desired) {
	for (NSString *family in [[NSFontManager sharedFontManager] availableFontFamilies]) {
		if ([desired caseInsensitiveCompare: family] == NSOrderedSame)
			return family;
	}
	return nil;
}

// The lookup of a family by name as such code makes it.
static NSFont *lookup(NSString *desired) {
	NSString *family = listedName(desired);
	if (family == nil)
		return nil;
	NSArray *members = [[NSFontManager sharedFontManager] availableMembersOfFontFamily: family];
	if ([members count] == 0)
		return nil;
	return [NSFont fontWithName: [[members objectAtIndex: 0] objectAtIndex: 0] size: 16];
}

int main(void)
{
	@autoreleasepool {
		NSArray *names = @[ @"Helvetica", @"Arial", @"Lucida Grande", @"Times New Roman", @"Courier New",
		                    @"Georgia", @"Verdana", @"Menlo", @"Monaco", @"Geneva" ];
		for (NSString *name in names) {
			if (lookup(name) == nil)
				printf("no font for %s\n", [name UTF8String]);
			CHECK(listedName(name) != nil);
			CHECK(lookup(name) != nil);
		}
		// Times and Courier: listed on Mojave, not on macOS 26.7.3. The first member must exist
		// whenever the family is listed.
		for (NSString *name in @[ @"Times", @"Courier" ]) {
			if (listedName(name) != nil)
				CHECK(lookup(name) != nil);
		}
		// Whatever the list names has members, and none is listed twice.
		NSArray *all = [[NSFontManager sharedFontManager] availableFontFamilies];
		CHECK([all count] == [[NSSet setWithArray: all] count]);
		for (NSString *family in all)
			CHECK([[[NSFontManager sharedFontManager] availableMembersOfFontFamily: family] count] > 0);
		// An unknown family is not listed and has no members.
		CHECK(listedName(@"NoSuchFamilyXyz") == nil);
		CHECK([[[NSFontManager sharedFontManager] availableMembersOfFontFamily: @"NoSuchFamilyXyz"] count] == 0);
	}
	printf(failures ? "FAILED\n" : "PASS\n");
	return failures != 0;
}
