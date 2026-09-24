#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSData *pixels(NSImage *image)
{
    NSBitmapImageRep *rep = (NSBitmapImageRep *)image.representations.firstObject;
    return [NSData dataWithBytes:rep.bitmapData length:rep.bytesPerRow * rep.pixelsHigh];
}

int main(void)
{
    @autoreleasepool
    {
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSData *folder = pixels([NSImage imageNamed:NSImageNameFolder]);

        NSDictionary *types = @{
            @"public.folder" : @"folder UTI",
            @"public.directory" : @"directory UTI",
        };
        for (NSString *type in types)
        {
            NSImage *icon = [workspace iconForFileType:type];
            expect(icon != nil && [pixels(icon) isEqual:folder], [NSString stringWithFormat:@"%@ gets the folder icon", types[type]]);
        }

        NSImage *text = [workspace iconForFileType:@"public.plain-text"];
        NSImage *textByExtension = [workspace iconForFileType:@"txt"];
        NSImage *image = [workspace iconForFileType:@"png"];
        NSImage *unknown = [workspace iconForFileType:@"no-such-extension-xyz"];
        for (NSImage *icon in @[ text, textByExtension, image, unknown ])
            expect(NSEqualSizes(icon.size, NSMakeSize(32, 32)), @"file type icons are 32x32");
        expect([pixels(text) isEqual:pixels(textByExtension)], @"a UTI and its extension share an icon");
        expect(![pixels(text) isEqual:folder], @"a text file is not a folder");
        expect(![pixels(image) isEqual:pixels(text)], @"images and text have different icons");
        expect(![pixels(unknown) isEqual:pixels(text)] && ![pixels(unknown) isEqual:folder], @"unknown types get the generic icon");
        expect([workspace iconForFileType:@"txt"] == textByExtension, @"icons are cached");
        NSLog(@"PASS: NSWorkspace iconForFileType:");
    }
    return 0;
}
