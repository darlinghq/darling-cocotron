// Copyright (C) 2026 Lubos Dolezel
// nsworkspace-icon-kinds <mount point of a disk image>: -[NSWorkspace iconForFile:], iconForFiles: and
// iconForContentType: for missing paths, plain files, folders, disk images, application bundles without an icon and
// volumes. Icons are compared by their pixels, drawn at 32x32. Prints "FAIL: ..." for each check that does not hold
// and exits 1 if any did. Link with -framework AppKit -framework UniformTypeIdentifiers. Also passes on macOS; the
// behaviour is described in darling's tests/volumes.md.
#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <unistd.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    if (!ok)
    {
        printf("FAIL: %s\n", [what UTF8String]);
        failures++;
    }
}

static NSData *pixels(NSImage *image)
{
    if (image == nil)
        return nil;
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:32 pixelsHigh:32
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:32 * 4 bitsPerPixel:32] autorelease];
    memset([rep bitmapData], 0, 32 * 32 * 4);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [image drawInRect:NSMakeRect(0, 0, 32, 32) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    return [NSData dataWithBytes:[rep bitmapData] length:32 * 32 * 4];
}

static void same(NSImage *a, NSImage *b, NSString *what)
{
    NSData *pa = pixels(a), *pb = pixels(b);
    expect(pa != nil && [pa isEqual:pb], what);
}

static void differ(NSImage *a, NSImage *b, NSString *what)
{
    NSData *pa = pixels(a), *pb = pixels(b);
    expect(pa != nil && pb != nil && ![pa isEqual:pb], what);
}

int main(int argc, char **argv)
{
    if (argc != 2)
    {
        fprintf(stderr, "usage: nsworkspace-icon-kinds <mount point of a disk image>\n");
        return 2;
    }
    @autoreleasepool
    {
        NSWorkspace *ws = [NSWorkspace sharedWorkspace];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *volume = [NSString stringWithUTF8String:argv[1]];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"icon-kinds-%d", getpid()]];
        [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"folder"] withIntermediateDirectories:YES attributes:nil error:NULL];
        for (NSString *name in @[ @"a.txt", @"b.zzqq", @"noext", @"c.dmg" ])
            [@"x" writeToFile:[dir stringByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        NSString *app = [dir stringByAppendingPathComponent:@"Bare.app"];
        [fm createDirectoryAtPath:[app stringByAppendingPathComponent:@"Contents/MacOS"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [@{ @"CFBundleName": @"Bare", @"CFBundleIdentifier": @"org.darlinghq.test.bare", @"CFBundlePackageType": @"APPL",
            @"CFBundleExecutable": @"Bare" } writeToFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:NO];

        NSImage *data = [ws iconForFileType:@"public.data"];
        NSImage *folderType = [ws iconForFileType:@"public.folder"];
        NSImage *diskImage = [ws iconForFileType:@"public.disk-image"];
        NSImage *volumeType = [ws iconForFileType:@"public.volume"];

        same([ws iconForFile:[dir stringByAppendingPathComponent:@"missing"]], data, @"a missing path gets the public.data icon");
        same([ws iconForFile:@""], data, @"an empty path gets the public.data icon");
        same([ws iconForFile:[dir stringByAppendingPathComponent:@"b.zzqq"]], data, @"an unknown extension gets the public.data icon");
        same([ws iconForFile:[dir stringByAppendingPathComponent:@"noext"]], data, @"no extension gets the public.data icon");
        same([ws iconForFile:[dir stringByAppendingPathComponent:@"folder"]], folderType, @"a folder gets the public.folder icon");
        same([ws iconForFile:[dir stringByAppendingPathComponent:@"a.txt"]], [ws iconForFileType:@"txt"], @"a.txt gets the txt icon");
        differ(diskImage, data, @"the public.disk-image icon is not the public.data icon");
        // The .dmg type (com.apple.disk-image-udif) is declared by DiskImageMounter on macOS; where no app declares
        // it, a .dmg is a file of unknown type.
        BOOL dmgDeclared = [[UTType typeWithFilenameExtension:@"dmg"] isDeclared];
        NSImage *dmg = [ws iconForFile:[dir stringByAppendingPathComponent:@"c.dmg"]];
        same(dmg, [ws iconForFileType:@"dmg"], @"a .dmg gets the dmg type icon");
        if (dmgDeclared)
            differ(dmg, data, @"the disk image icon is not the public.data icon");
        else
            printf("SKIP: the .dmg type is not declared\n");
        // macOS gives an app without an icon, and /, icons of their own that no file type has
        NSImage *bare = [ws iconForFile:app];
        differ(bare, data, @"the application icon is not the public.data icon");
        differ(bare, folderType, @"an application is not shown as a folder");
        NSImage *root = [ws iconForFile:@"/"];
        differ(root, data, @"/ does not get the public.data icon");
        differ(root, folderType, @"/ is not shown as a folder");
        NSImage *image = [ws iconForFile:volume];
        differ(image, root, @"a disk image's volume has another icon than /");
        differ(image, folderType, @"a disk image's volume is not shown as a folder");

        expect([ws iconForFiles:@[]] == nil, @"iconForFiles: of no files is nil");
        NSString *a = [dir stringByAppendingPathComponent:@"a.txt"];
        same([ws iconForFiles:@[ a ]], [ws iconForFile:a], @"iconForFiles: of one file is its icon");
        same([ws iconForFiles:@[ a, [dir stringByAppendingPathComponent:@"noext"] ]],
            [NSImage imageNamed:NSImageNameMultipleDocuments], @"iconForFiles: of two files is the multiple documents image");
        same([ws iconForContentType:UTTypeDiskImage], diskImage, @"iconForContentType: is iconForFileType: of the identifier");
        if (dmgDeclared)
            same([ws iconForContentType:[UTType typeWithIdentifier:@"com.apple.disk-image-udif"]], dmg,
                @"iconForContentType: of com.apple.disk-image-udif is the .dmg icon");

        for (NSImage *icon in @[ data, folderType, diskImage, volumeType, dmg, bare, root, image ])
            expect(NSEqualSizes([icon size], NSMakeSize(32, 32)),
                [NSString stringWithFormat:@"an icon is %g x %g", [icon size].width, [icon size].height]);

        [fm removeItemAtPath:dir error:NULL];
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
