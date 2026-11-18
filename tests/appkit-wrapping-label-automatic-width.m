// Copyright (C) 2026 Lubos Dolezel
// A wrapping label laid out by constraints, without a preferredMaxLayoutWidth, takes the height of its
// text wrapped at the width layout gives it when the program was built against the 10.11 SDK or later,
// and the height of the unwrapped text for older programs; -intrinsicContentSize keeps reporting the
// unwrapped size. Pins the QUIRK in NSTextField. Reference (macOS 10.14.4 and 26.7.3, 13 point system
// font, text of two paragraphs of 119 and 34 points in a label 356 points wide): the label is 119 high
// for an SDK of 10.11 or later and 34 high for 10.10 or earlier. The checks here are relative.
// Run the test twice, built with a new and with an old SDK stamp:
//   guest-cc.sh -t 10.13 -o t-new t.m -framework AppKit -Wl,-sdk_version,10.14
//   guest-cc.sh -t 10.13 -o t-old t.m -framework AppKit -Wl,-sdk_version,10.10
// and pass "old" to the second.
#import <AppKit/AppKit.h>
#include <mach-o/dyld_priv.h>
#include <stdio.h>
#include <string.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

static NSTextField *makeLabel(NSView *container, CGFloat width)
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, width, 20)] autorelease];
    label.bezeled = NO; label.drawsBackground = NO; label.editable = NO; label.selectable = NO;
    label.font = [NSFont systemFontOfSize: 13];
    label.stringValue = @"A long sentence that wraps over several lines when the label is only a few hundred "
                         "points wide, because it keeps going with more and more words until the end.";
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview: label];
    [container addConstraints: [NSLayoutConstraint constraintsWithVisualFormat: @"H:|-10-[l]-10-|"
                                                                      options: 0 metrics: nil
                                                                        views: @{@"l": label}]];
    [container addConstraints: [NSLayoutConstraint constraintsWithVisualFormat: @"V:|-10-[l]"
                                                                      options: 0 metrics: nil
                                                                        views: @{@"l": label}]];
    return label;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        BOOL old = argc > 1 && strcmp(argv[1], "old") == 0;
        uint32_t sdk = dyld_get_program_sdk_version();
        if (old != (sdk < 0x000a0b00)) {
            printf("SKIP: the program's SDK version is 0x%08x, not an %s program\n", sdk, old ? "old" : "new");
            return 0;
        }

        NSView *container = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 220, 400)] autorelease];
        NSTextField *label = makeLabel(container, 200);
        CGFloat line = [[label cell] cellSize].height;
        NSSize unwrapped = label.intrinsicContentSize;
        CHECK(unwrapped.height <= line + 1);       // the public intrinsic size is the unwrapped one
        CHECK(unwrapped.width > 400);

        [container layoutSubtreeIfNeeded];
        CGFloat narrow = label.frame.size.height;
        // Programs built with old SDKs also resist compression of a label in the other axis (their
        // labels are not squeezed to the pinned width), so the width is only checked for new ones.
        if (!old)
            CHECK(label.frame.size.width >= 200 && label.frame.size.width <= 204);  // 204: alignment insets
        if (old) {
            CHECK(narrow <= line + 1);             // cut to one line
        } else {
            CHECK(narrow > line * 3);              // all the wrapped lines
        }
        CHECK(label.intrinsicContentSize.height <= line + 1);   // still unwrapped after layout

        // A wider container needs fewer lines; the height follows the new width.
        [container setFrameSize: NSMakeSize(420, 400)];
        [container layoutSubtreeIfNeeded];
        CGFloat wide = label.frame.size.height;
        if (!old)
            CHECK(label.frame.size.width >= 400 && label.frame.size.width <= 404);
        if (old)
            CHECK(wide <= line + 1);
        else
            CHECK(wide > line && wide < narrow);

        // An explicit preferredMaxLayoutWidth wins for every SDK.
        NSView *second = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 220, 400)] autorelease];
        NSTextField *fixed = makeLabel(second, 200);
        fixed.preferredMaxLayoutWidth = 200;
        [second layoutSubtreeIfNeeded];
        CHECK(fixed.frame.size.height > line * 3);

        // A label that does not wrap keeps the height of one line.
        NSView *third = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 220, 400)] autorelease];
        NSTextField *clip = makeLabel(third, 200);
        clip.lineBreakMode = NSLineBreakByClipping;
        [third layoutSubtreeIfNeeded];
        CHECK(clip.frame.size.height <= line + 1);
    }
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
