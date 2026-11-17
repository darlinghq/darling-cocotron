// Copyright (C) 2026 Lubos Dolezel
//
// -[NSWorkspace setIcon:forFile:options:] sets a custom icon on a file or folder and removes it again for a
// nil image. The icon is kept the way Finder does: the kHasCustomIcon flag in the FinderInfo of the item, an
// 'icns' resource in the resource fork of a file, and an "Icon\r" file inside a folder.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/xattr.h>
#include <unistd.h>

#define EXPECT(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); return 1; } } while (0)

static int HasCustomIconFlag(NSString *path) {
    unsigned char info[32];
    if (getxattr([path fileSystemRepresentation], "com.apple.FinderInfo", info, sizeof(info), 0, 0) != (ssize_t)sizeof(info))
        return 0;
    return (info[8] & 0x04) != 0;
}

static int ResourceForkHasIcns(NSString *path) {
    const char *fsPath = [path fileSystemRepresentation];
    ssize_t length = getxattr(fsPath, "com.apple.ResourceFork", NULL, 0, 0, 0);
    if (length <= 0)
        return 0;
    NSMutableData *fork = [NSMutableData dataWithLength: (NSUInteger)length];
    if (getxattr(fsPath, "com.apple.ResourceFork", [fork mutableBytes], (size_t)length, 0, 0) != length)
        return 0;
    NSData *tag = [NSData dataWithBytes: "icns" length: 4];
    return [fork rangeOfData: tag options: 0 range: NSMakeRange(0, [fork length])].location != NSNotFound;
}

int main(void) {
    @autoreleasepool {
        char templ[] = "/tmp/wsseticonXXXXXX";
        EXPECT(mkdtemp(templ) != NULL, "temporary directory is created");
        NSString *dir = [NSString stringWithUTF8String: templ];
        NSString *file = [dir stringByAppendingPathComponent: @"f.txt"];
        NSString *folder = [dir stringByAppendingPathComponent: @"folder"];
        NSString *iconFile = [folder stringByAppendingPathComponent: @"Icon\r"];
        NSFileManager *fm = [NSFileManager defaultManager];
        EXPECT([@"x" writeToFile: file atomically: NO encoding: NSUTF8StringEncoding error: NULL], "test file is written");
        EXPECT([fm createDirectoryAtPath: folder withIntermediateDirectories: NO attributes: nil error: NULL], "test folder is created");

        NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(64, 64)] autorelease];
        [image lockFocus];
        [[NSColor redColor] set];
        NSRectFill(NSMakeRect(0, 0, 64, 64));
        [image unlockFocus];

        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];

        EXPECT(![workspace setIcon: image forFile: [dir stringByAppendingPathComponent: @"missing"] options: 0], "a missing path fails");
        EXPECT(![workspace setIcon: image forFile: nil options: 0], "a nil path fails");

        // A file.
        EXPECT([workspace setIcon: image forFile: file options: 0], "setting the icon of a file succeeds");
        EXPECT(HasCustomIconFlag(file), "the file has the custom icon flag");
        EXPECT(ResourceForkHasIcns(file), "the file has an icns resource");
        EXPECT([workspace iconForFile: file] != nil, "iconForFile: answers for the file with the icon");
        EXPECT([workspace setIcon: image forFile: file
                          options: NSExclude10_4ElementsIconCreationOption | NSExcludeQuickDrawElementsIconCreationOption],
               "setting the icon with options succeeds");
        // What the options leave of the icon differs between systems, so set it again without them.
        EXPECT([workspace setIcon: image forFile: file options: 0], "setting the icon again succeeds");
        EXPECT(HasCustomIconFlag(file), "the flag is set again");
        EXPECT([workspace setIcon: nil forFile: file options: 0], "removing the icon of a file succeeds");
        EXPECT(!HasCustomIconFlag(file), "the custom icon flag is cleared");
        EXPECT([workspace setIcon: nil forFile: file options: 0], "removing an icon that is not set succeeds");

        // A folder.
        EXPECT([workspace setIcon: image forFile: folder options: 0], "setting the icon of a folder succeeds");
        EXPECT(HasCustomIconFlag(folder), "the folder has the custom icon flag");
        EXPECT([fm fileExistsAtPath: iconFile], "the folder has an Icon file");
        EXPECT(ResourceForkHasIcns(iconFile), "the Icon file has an icns resource");
        EXPECT([workspace iconForFile: folder] != nil, "iconForFile: answers for the folder with the icon");
        EXPECT([workspace setIcon: nil forFile: folder options: 0], "removing the icon of a folder succeeds");
        EXPECT(!HasCustomIconFlag(folder), "the folder flag is cleared");
        EXPECT(![fm fileExistsAtPath: iconFile], "the Icon file is removed");

        [fm removeItemAtPath: dir error: NULL];
        printf("PASS\n");
    }
    return 0;
}
