// Copyright (C) 2026 Lubos Dolezel
//
// -[NSWorkspace isFilePackageAtPath:] gives the same answer as
// NSURLIsPackageKey: a directory whose type is declared as a package (.app,
// with or without an Info.plist, .bundle, .plugin, .rtfd) or that has the
// Finder's bundle bit is one; a .framework, a plain folder, a file, a
// symbolic link to a package and a missing path are not. Built without ARC.
// Values are those observed on macOS 26.7.3 and Mac OS X 10.14.4 (x86_64 and
// i386), where the program builds and runs too.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/xattr.h>

static int failures;
static NSString *root;

static void makeDirectory(NSString *rel)
{
    [[NSFileManager defaultManager] createDirectoryAtPath:[root stringByAppendingPathComponent:rel]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
}

static void checkPackage(NSString *rel, BOOL expected)
{
    NSString *path = [root stringByAppendingPathComponent:rel];
    BOOL value = [[NSWorkspace sharedWorkspace] isFilePackageAtPath:path];

    NSNumber *urlValue = nil;
    [[NSURL fileURLWithPath:path] getResourceValue:&urlValue forKey:NSURLIsPackageKey error:NULL];
    BOOL same = (urlValue == nil && !value) || (urlValue != nil && [urlValue boolValue] == value);

    printf("%s %s: isFilePackageAtPath: is %s (got %s), NSURLIsPackageKey %s\n",
           (value == expected && same) ? "PASS" : "FAIL", [rel UTF8String],
           expected ? "YES" : "NO", value ? "YES" : "NO", same ? "agrees" : "differs");
    if (value != expected || !same)
        failures++;
}

int main(void)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSFileManager *fm = [NSFileManager defaultManager];
    char dirTemplate[] = "/tmp/wsfilepackage.XXXXXX";
    if (mkdtemp(dirTemplate) == NULL) {
        perror("mkdtemp");
        return 1;
    }
    root = [[NSString stringWithUTF8String:dirTemplate] retain];

    makeDirectory(@"App.app/Contents");
    [[NSData data] writeToFile:[root stringByAppendingPathComponent:@"App.app/Contents/Info.plist"] atomically:NO];
    makeDirectory(@"Plain.app");
    makeDirectory(@"Thing.bundle");
    makeDirectory(@"Ext.plugin");
    makeDirectory(@"Doc.rtfd");
    makeDirectory(@"Kit.framework");
    makeDirectory(@"Folder");
    makeDirectory(@"Bit");
    [[NSData data] writeToFile:[root stringByAppendingPathComponent:@"file.app"] atomically:NO];
    [fm createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"LinkApp.app"] withDestinationPath:@"App.app" error:NULL];

    // kHasBundle (0x2000) in the Finder flags, bytes 8 and 9 of com.apple.FinderInfo.
    unsigned char finderInfo[32] = { 0 };
    finderInfo[8] = 0x20;
    if (setxattr([[root stringByAppendingPathComponent:@"Bit"] fileSystemRepresentation], "com.apple.FinderInfo",
                 finderInfo, sizeof finderInfo, 0, 0) != 0) {
        printf("FAIL the bundle bit can be set on a directory\n");
        failures++;
    }

    checkPackage(@"App.app", YES);
    checkPackage(@"Plain.app", YES);
    checkPackage(@"Thing.bundle", YES);
    checkPackage(@"Ext.plugin", YES);
    checkPackage(@"Doc.rtfd", YES);
    checkPackage(@"Kit.framework", NO);
    checkPackage(@"Folder", NO);
    checkPackage(@"Bit", YES);
    checkPackage(@"file.app", NO);
    checkPackage(@"LinkApp.app", NO);
    checkPackage(@"Missing.app", NO);

    [fm removeItemAtPath:root error:NULL];
    printf("%s\n", failures == 0 ? "ALL PASS" : "SOME FAILED");
    [pool drain];
    return failures == 0 ? 0 : 1;
}
