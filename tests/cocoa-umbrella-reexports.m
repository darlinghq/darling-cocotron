/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Cocoa is an umbrella framework: on macOS it re-exports AppKit (which in turn
// re-exports Foundation) and CoreData, so a program linked with nothing but
// -framework Cocoa can use the classes and constants of all three. This test is
// linked that way; without the re-exports it does not link at all. No window
// server is needed.
//
//   guest-cc.sh -o cocoa-umbrella-reexports cocoa-umbrella-reexports.m -framework Cocoa
#import <Cocoa/Cocoa.h>
#import <CoreData/CoreData.h>
#include <stdio.h>

int main(void)
{
	@autoreleasepool {
		int failures = 0;

		// Foundation, through AppKit
		NSString *string = [NSString stringWithFormat: @"%d", 42];
		if (![string isEqualToString: @"42"]) {
			printf("FAIL: NSString from Foundation\n");
			failures++;
		}

		// AppKit: a class and an exported constant
		NSColor *color = [NSColor colorWithCalibratedRed: 1 green: 0 blue: 0 alpha: 1];
		if (color == nil || NSFontAttributeName == nil) {
			printf("FAIL: NSColor or NSFontAttributeName from AppKit\n");
			failures++;
		}

		// CoreData: a class and an exported constant
		NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] init] autorelease];
		if (model == nil || NSSQLiteStoreType == nil) {
			printf("FAIL: NSManagedObjectModel or NSSQLiteStoreType from CoreData\n");
			failures++;
		}

		if (failures == 0)
			printf("PASS: Foundation, AppKit and CoreData symbols resolve through Cocoa\n");
		return failures != 0;
	}
}
