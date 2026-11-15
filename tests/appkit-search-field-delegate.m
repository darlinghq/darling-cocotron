// Copyright (C) 2026 Lubos Dolezel
//
// NSSearchFieldDelegate: searchFieldDidStartSearching: when the text becomes non-empty and
// searchFieldDidEndSearching: when it is empty again.
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

@interface Recorder : NSObject <NSSearchFieldDelegate> {
    NSMutableArray *_events;
}
@property (retain) NSMutableArray *events;
@end
@implementation Recorder
@synthesize events = _events;
- (void)searchFieldDidStartSearching:(NSSearchField *)sender
{
    [self.events addObject:[@"start:" stringByAppendingString:[sender stringValue]]];
}
- (void)searchFieldDidEndSearching:(NSSearchField *)sender
{
    [self.events addObject:[@"end:" stringByAppendingString:[sender stringValue]]];
}
@end

static void spin(void)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 100)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO] autorelease];
        NSSearchField *search = [[[NSSearchField alloc] initWithFrame:NSMakeRect(10, 40, 200, 24)] autorelease];
        Recorder *recorder = [[[Recorder alloc] init] autorelease];
        recorder.events = [NSMutableArray array];
        [search setDelegate:recorder];
        [[window contentView] addSubview:search];
        expect([window makeFirstResponder:search], @"field takes focus");
        NSTextView *editor = (NSTextView *)[search currentEditor];
        expect(editor != nil, @"field editor");

        [editor insertText:@"a"];
        spin();
        expect([recorder.events isEqualToArray:@[@"start:a"]], @"first text starts searching");

        [editor insertText:@"b"];
        spin();
        expect([recorder.events count] == 1, @"more text is not a new start");

        [editor setString:@""];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSTextDidChangeNotification object:editor];
        spin();
        expect([recorder.events count] == 2, @"clearing the text ends searching");
        expect([[recorder.events lastObject] isEqualToString:@"end:"], @"the end comes last with an empty string");

        [editor insertText:@"c"];
        spin();
        expect([[recorder.events lastObject] isEqualToString:@"start:c"], @"typing again starts again");
    }
    printf("PASS\n");
    return 0;
}
