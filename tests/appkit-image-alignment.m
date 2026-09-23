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

static BOOL sameRect(NSRect a, NSRect b)
{
    return a.origin.x == b.origin.x && a.origin.y == b.origin.y &&
           a.size.width == b.size.width && a.size.height == b.size.height;
}

int main(void)
{
    @autoreleasepool
    {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(20, 30)];
        expect(sameRect(image.alignmentRect, NSMakeRect(0, 0, 20, 30)), @"default alignment rect");
        image.size = NSMakeSize(40, 50);
        expect(sameRect(image.alignmentRect, NSMakeRect(0, 0, 40, 50)), @"default follows image size");

        image.alignmentRect = NSMakeRect(2, 3, 36, 44);
        expect(sameRect(image.alignmentRect, NSMakeRect(2, 3, 36, 44)), @"custom alignment rect");
        image.size = NSMakeSize(60, 70);
        expect(sameRect(image.alignmentRect, NSMakeRect(2, 3, 36, 44)), @"custom alignment stays independent");

        NSImage *copy = [image copy];
        expect(sameRect(copy.alignmentRect, image.alignmentRect), @"copy preserves alignment metadata");
        copy.alignmentRect = NSMakeRect(1, 1, 10, 10);
        expect(sameRect(image.alignmentRect, NSMakeRect(2, 3, 36, 44)), @"copy has independent metadata");
        [copy release];
        [image release];
        NSLog(@"PASS: NSImage alignment rectangle defaults, updates, and copies");
    }
    return 0;
}
