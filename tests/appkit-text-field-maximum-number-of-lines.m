// https://developer.apple.com/documentation/appkit/nstextfield/maximumnumberoflines
// maximumNumberOfLines is 0 (no limit) by default; otherwise it is the number of lines a wrapping field
// shows before the text is clipped, and it affects the intrinsic content size. The checks are relative to
// the height of one line, so any font works.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

static NSTextField *wrappingField(NSString *text) {
    NSTextField *f = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    f.bezeled = NO; f.drawsBackground = NO; f.editable = NO; f.selectable = NO;
    f.font = [NSFont systemFontOfSize: 13];
    f.stringValue = text;
    f.lineBreakMode = NSLineBreakByWordWrapping;
    return f;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *text = @"one two three four five six seven eight nine ten eleven twelve thirteen fourteen "
                          "fifteen sixteen seventeen eighteen nineteen twenty";
        NSTextField *f = wrappingField(text);

        // The property keeps what it is given.
        CHECK(f.maximumNumberOfLines == 0);
        f.maximumNumberOfLines = 3;
        CHECK(f.maximumNumberOfLines == 3);
        f.maximumNumberOfLines = 0;
        CHECK(f.maximumNumberOfLines == 0);

        NSCell *cell = [f cell];
        CGFloat line = [cell cellSize].height;
        NSRect bounds = NSMakeRect(0, 0, 120, CGFLOAT_MAX);
        CGFloat all = [cell cellSizeForBounds: bounds].height;
        CHECK(all > line * 4);                                    // the text needs several lines at this width

        // The cap limits the measured height to that many lines.
        f.maximumNumberOfLines = 2;
        CHECK([cell cellSizeForBounds: bounds].height < line * 2 + 1);
        CHECK([cell cellSizeForBounds: bounds].height > line * 2 - 1);
        f.maximumNumberOfLines = 1;
        CHECK([cell cellSizeForBounds: bounds].height < line + 1);
        f.maximumNumberOfLines = 3;
        CGFloat three = [cell cellSizeForBounds: bounds].height;
        CHECK(three > line * 3 - 1 && three < line * 3 + 1);

        // A cap above the number of lines the text takes changes nothing.
        f.maximumNumberOfLines = 100;
        CHECK([cell cellSizeForBounds: bounds].height == all);
        f.maximumNumberOfLines = 0;
        CHECK([cell cellSizeForBounds: bounds].height == all);

        // The cap affects the intrinsic content size.
        f.preferredMaxLayoutWidth = 120;
        CGFloat uncapped = f.intrinsicContentSize.height;
        CHECK(uncapped == all);
        f.maximumNumberOfLines = 2;
        CHECK(f.intrinsicContentSize.height == [cell cellSizeForBounds: bounds].height);
        CHECK(f.intrinsicContentSize.height < uncapped);

        // The cap is not a property of a field whose text does not wrap.
        NSTextField *clip = wrappingField(text);
        clip.lineBreakMode = NSLineBreakByClipping;
        CGFloat clipped = [[clip cell] cellSizeForBounds: bounds].height;
        clip.maximumNumberOfLines = 2;
        CHECK([[clip cell] cellSizeForBounds: bounds].height == clipped);

        // A negative cap is kept as given and is no limit (macOS 26.7.3 and 10.14.4, black-box observation).
        f.maximumNumberOfLines = -4;
        CHECK(f.maximumNumberOfLines == -4);
        CHECK([cell cellSizeForBounds: bounds].height > line * 4);
    }
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
