// https://developer.apple.com/documentation/appkit/nsbrowsercell/image
// The image of a browser cell can be set and removed (nil); it is drawn beside the cell's title, which stays.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSBrowserCell *cell = [[[NSBrowserCell alloc] initTextCell: @"Name"] autorelease];
        NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(16, 16)] autorelease];

        CHECK([cell image] == nil);
        [cell setImage: image];
        CHECK([cell image] == image);
        CHECK([[cell stringValue] isEqual: @"Name"]);   // the title stays
        CHECK([cell type] == NSTextCellType);           // and the cell stays a text cell

        [cell setImage: nil];
        CHECK([cell image] == nil);
        CHECK([[cell stringValue] isEqual: @"Name"]);
        CHECK([cell type] == NSTextCellType);
    }
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
