// NSSplitView autosaveName: divider positions are saved to user defaults and restored by a
// split view that takes the same name.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSSplitView *makeSplitView(void)
{
    NSSplitView *split = [[[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 305, 100)] autorelease];
    [split setVertical:YES];
    [split addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 150, 100)] autorelease]];
    [split addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(155, 0, 150, 100)] autorelease]];
    return split;
}

static CGFloat firstWidth(NSSplitView *split)
{
    return NSWidth([[[split subviews] objectAtIndex:0] frame]);
}

int main(void)
{
    @autoreleasepool
    {
        NSString *name = @"DarlingSplitAutosaveTest";
        NSString *key = @"NSSplitView Dividers DarlingSplitAutosaveTest";
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults removeObjectForKey:key];

        NSSplitView *split = makeSplitView();
        expect([split autosaveName] == nil, @"no autosave name by default");
        [split setAutosaveName:@""];
        expect([split autosaveName] == nil, @"an empty name disables autosaving");
        [split setPosition:100 ofDividerAtIndex:0];
        expect([defaults objectForKey:key] == nil, @"nothing saved without a name");

        [split setAutosaveName:name];
        expect([[split autosaveName] isEqualToString:name], @"name is kept");
        expect(fabs(firstWidth(split) - 100) < 0.5, @"no saved layout leaves the dividers alone");
        [split setPosition:60 ofDividerAtIndex:0];
        expect(fabs(firstWidth(split) - 60) < 0.5, @"divider moved");
        expect([defaults dictionaryForKey:key] != nil, @"divider layout saved under the name");

        NSSplitView *other = makeSplitView();
        expect(fabs(firstWidth(other) - 150) < 0.5, @"a fresh split view starts evenly");
        [other setAutosaveName:name];
        expect(fabs(firstWidth(other) - 60) < 0.5,
               [NSString stringWithFormat:@"saved divider position restored (got %g)", firstWidth(other)]);

        [defaults removeObjectForKey:key];
        NSLog(@"PASS: NSSplitView autosaveName");
    }
    return 0;
}
