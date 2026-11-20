/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A nib that is archived inside another archive (as Interface Builder does for
 * the nib of a table's cell views, which an NSTableView decodes from its own
 * nib) is decoded with -[NSNib initWithCoder:], and instantiates like any nib
 * that was read from a file. The nib data it holds is a keyed archive, so the
 * instantiation must use the keyed unarchiver and not NSUnarchiver, which
 * only reads NSArchiver data and refuses a keyed archive.
 *
 * The embedded nib and the archive that holds it are built here with
 * NSKeyedArchiver from stand-in classes, whose class names are then rewritten
 * to NSIBObjectData, NSCustomObject and NSNib. A second case embeds a nib
 * whose data is a typedstream (NSArchiver data), which must still be read as
 * one.
 *
 * Usage: appkit-nib-archived-nib
 * Prints PASS/FAIL lines; exit status 1 on failure. No ARC.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	if (!ok)
		failures++;
}

@interface ArchivedPlaceholder : NSObject <NSCoding>
@end
@implementation ArchivedPlaceholder
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:@"NSObject" forKey:@"NSClassName"]; }
- (id)initWithCoder:(NSCoder *)coder { return [self init]; }
@end

@interface ArchivedObjectData : NSObject <NSCoding> {
@public
	id root;
	id object;
}
@end
@implementation ArchivedObjectData
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:root forKey:@"NSRoot"];
	[coder encodeObject:[NSArray arrayWithObject:object] forKey:@"NSObjectsKeys"];
	[coder encodeObject:[NSArray arrayWithObject:root] forKey:@"NSObjectsValues"];
}
- (id)initWithCoder:(NSCoder *)coder { return [self init]; }
@end

@interface ArchivedNib : NSObject <NSCoding> {
@public
	NSData *data;
}
@end
@implementation ArchivedNib
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:data forKey:@"NSNibFileData"]; }
- (id)initWithCoder:(NSCoder *)coder { return [self init]; }
@end

// Rewrites the stand-in class names of a keyed archive; returns the archive as binary plist data.
static NSData *renameClasses(NSData *archive, NSDictionary *renames, NSUInteger expected)
{
	NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:archive
		options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
	NSUInteger renamed = 0;
	for (id object in plist[@"$objects"]) {
		if (![object isKindOfClass:[NSMutableDictionary class]] || renames[object[@"$classname"]] == nil)
			continue;
		object[@"$classes"] = @[renames[object[@"$classname"]], @"NSObject"];
		object[@"$classname"] = renames[object[@"$classname"]];
		renamed++;
	}
	expect(renamed == expected, "the stand-in classes were renamed");
	return [NSPropertyListSerialization dataWithPropertyList:plist
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}

// A keyed nib with File's Owner and one NSCustomObject of class NSObject.
static NSData *keyedNibData(void)
{
	ArchivedObjectData *objectData = [[ArchivedObjectData new] autorelease];
	objectData->root = [[ArchivedPlaceholder new] autorelease];
	objectData->object = [[ArchivedPlaceholder new] autorelease];
	NSMutableData *archive = [NSMutableData data];
	NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initForWritingWithMutableData:archive] autorelease];
	[archiver encodeObject:objectData forKey:@"IB.objectdata"];
	[archiver finishEncoding];
	return renameClasses(archive, @{@"ArchivedPlaceholder": @"NSCustomObject",
	                                @"ArchivedObjectData": @"NSIBObjectData"}, 2);
}

// The NSNib object that results from decoding an archive that holds a nib with this data.
static NSNib *decodeArchivedNib(NSData *nibData)
{
	ArchivedNib *stand = [[ArchivedNib new] autorelease];
	stand->data = nibData;
	NSMutableData *archive = [NSMutableData data];
	NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initForWritingWithMutableData:archive] autorelease];
	[archiver encodeObject:stand forKey:@"nib"];
	[archiver finishEncoding];
	NSData *renamed = renameClasses(archive, @{@"ArchivedNib": @"NSNib"}, 1);
	NSKeyedUnarchiver *unarchiver = [[[NSKeyedUnarchiver alloc] initForReadingWithData:renamed] autorelease];
	return [unarchiver decodeObjectForKey:@"nib"];
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];

		NSNib *nib = decodeArchivedNib(keyedNibData());
		expect([nib isKindOfClass:[NSNib class]], "an NSNib is decoded from the archive");

		NSArray *topLevel = nil;
		NSObject *owner = [[NSObject new] autorelease];
		BOOL loaded = NO;
		NSException *raised = nil;
		@try {
			loaded = [nib instantiateWithOwner:owner topLevelObjects:&topLevel];
		} @catch (NSException *e) {
			raised = e;
		}
		expect(raised == nil, "instantiating an archived keyed nib does not raise");
		expect(loaded, "an archived keyed nib instantiates");
		expect([topLevel count] == 1 && [[topLevel objectAtIndex:0] isMemberOfClass:[NSObject class]],
		       "its custom object is a top-level object");

		// Data that is NSArchiver output is still taken for a typedstream: this one is not a
		// nib, so the instantiation fails without crashing.
		NSData *typed = [NSArchiver archivedDataWithRootObject:@"not a nib"];
		NSNib *typedNib = decodeArchivedNib(typed);
		raised = nil;
		loaded = YES;
		@try {
			loaded = [typedNib instantiateWithOwner:owner topLevelObjects:NULL];
		} @catch (NSException *e) {
			raised = e;
		}
		expect(raised == nil && !loaded, "an archived typedstream that is not a nib fails to instantiate");
	}
	return failures != 0;
}
