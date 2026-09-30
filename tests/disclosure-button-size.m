#import <AppKit/AppKit.h>
#include <assert.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSImage *glyph = [NSImage imageNamed:@"NSButtonCell_disclosure_normal"];
        assert(glyph != nil);
        NSSize glyphSize = [glyph size];
        assert(glyphSize.width > 0 && glyphSize.height > 0);
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 2, 24, 24)];
        [button setButtonType:NSOnOffButton];
        [button setBezelStyle:NSDisclosureBezelStyle];
        [button setImagePosition:NSImageOnly];
        [button setControlSize:NSSmallControlSize];
        assert([button image] == nil);
        [button sizeToFit];
        NSSize closed = [button frame].size;
        fprintf(stderr, "disclosure glyph=%gx%g fitted=%gx%g\n",
                glyphSize.width, glyphSize.height, closed.width, closed.height);
        assert(closed.width >= glyphSize.width && closed.height >= glyphSize.height);
        [button setState:NSOnState];
        [button sizeToFit];
        assert(NSEqualSizes(closed, [button frame].size));
        [button setState:NSOffState];
        [button sizeToFit];
        assert(NSEqualSizes(closed, [button frame].size));
        [[button cell] setHighlighted:YES];
        [button sizeToFit];
        assert(NSEqualSizes(closed, [button frame].size));
        // Drawing forces disclosure cells to image-only regardless of title.
        [button setTitle:@"A title that is not drawn"];
        [button setImagePosition:NSImageLeft];
        [button sizeToFit];
        assert(NSEqualSizes(closed, [button frame].size));
        // Ordinary image-only buttons still measure their explicit image.
        NSButton *ordinary = [[NSButton alloc] initWithFrame:NSZeroRect];
        [ordinary setBezelStyle:NSRegularSquareBezelStyle];
        [ordinary setImagePosition:NSImageOnly];
        [ordinary setImage:glyph];
        [ordinary sizeToFit];
        assert(NSEqualSizes(closed, [ordinary frame].size));
        [ordinary setImage:nil];
        [ordinary sizeToFit];
        assert([ordinary frame].size.width < closed.width);
        assert([ordinary frame].size.height < closed.height);
        [ordinary release];
        [button release];
        puts("PASS disclosure button fits its built-in glyph and has stable state sizing");
    }
    return 0;
}
