#import <AppKit/AppKit.h>
#include <assert.h>
#include <stdio.h>
#ifdef NDEBUG
#error Assertions required
#endif
int main(void) {
    @autoreleasepool {
        setbuf(stdout,NULL);
        [NSApplication sharedApplication];
        NSPopUpButton *button=[[NSPopUpButton alloc]
            initWithFrame:NSMakeRect(0,0,120,30) pullsDown:YES];
        [button removeAllItems];
        assert([button numberOfItems]==0);
        [button setTitle:@"Actions"];
        assert([button numberOfItems]==1);
        assert([[button title] isEqualToString:@"Actions"]);
        assert([[[button itemAtIndex:0] title] isEqualToString:@"Actions"]);
        [button setTitle:@"More"];
        assert([button numberOfItems]==1);
        [button addItemWithTitle:@"Command"];
        [button selectItemAtIndex:1];
        [button setTitle:@"Operations"];
        assert([button numberOfItems]==2);
        assert([button indexOfSelectedItem]==1);
        assert([[button title] isEqualToString:@"Operations"]);
        assert([[[button itemAtIndex:1] title] isEqualToString:@"Command"]);
        [button removeAllItems];
        [button setTitle:@""];
        assert([button numberOfItems]==1 && [[button title] isEqualToString:@""]);
        [button release];
        NSPopUpButton *popup=[[NSPopUpButton alloc]
            initWithFrame:NSMakeRect(0,0,120,30) pullsDown:NO];
        [popup removeAllItems];
        [popup setTitle:@"Selected"];
        assert([popup numberOfItems]==1);
        assert([[popup title] isEqualToString:@"Selected"]);
        assert([popup indexOfSelectedItem]==0);
        [popup release];
        puts("PASS: empty pull-down titles and existing selection");
    }
    return 0;
}
