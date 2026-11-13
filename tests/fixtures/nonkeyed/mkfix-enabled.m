// Copyright (C) 2026 Lubos Dolezel
//
// Writes NSArchiver (typedstream) archives of enabled and disabled controls
// into the directory given as argv[1], and prints isEnabled of each after a
// round trip through NSUnarchiver on the same system. Build for x86_64 against
// the system frameworks and run on the Mac named by the fixture directory. The
// expected values are checked by tests/appkit-nonkeyed-control-enabled.m.
#import <AppKit/AppKit.h>

static void put(NSString *dir, NSString *name, NSControl *control)
{
    @try {
        NSData *d = [NSArchiver archivedDataWithRootObject: control];
        name = [name stringByAppendingString: @".typedstream"];
        [d writeToFile: [dir stringByAppendingPathComponent: name] atomically: NO];
        NSControl *back = [NSUnarchiver unarchiveObjectWithData: d];
        printf("%s %lu bytes, enabled %d, round trip enabled %d\n", [name UTF8String],
               (unsigned long) [d length], (int) [control isEnabled], (int) [back isEnabled]);
    } @catch (NSException *e) {
        printf("%s EXC %s\n", [name UTF8String], [[e reason] UTF8String]);
    }
}

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSString *dir = [NSString stringWithUTF8String: argv[1]];

    [NSApplication sharedApplication];

    for (int enabled = 1; enabled >= 0; enabled--) {
        NSString *suffix = enabled ? @"on" : @"off";

        NSButton *button = [[[NSButton alloc] initWithFrame: NSMakeRect(10, 20, 90, 28)] autorelease];
        [button setTitle: @"Push"];
        [button setEnabled: enabled];
        put(dir, [@"enabled-button-" stringByAppendingString: suffix], button);

        NSScroller *scroller = [[[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 16, 100)] autorelease];
        [scroller setEnabled: enabled];
        put(dir, [@"enabled-scroller-" stringByAppendingString: suffix], scroller);

        NSTextField *field = [[[NSTextField alloc] initWithFrame: NSMakeRect(1, 2, 100, 22)] autorelease];
        [field setStringValue: @"Field"];
        [field setEnabled: enabled];
        put(dir, [@"enabled-textfield-" stringByAppendingString: suffix], field);

        NSSlider *slider = [[[NSSlider alloc] initWithFrame: NSMakeRect(1, 2, 100, 22)] autorelease];
        [slider setEnabled: enabled];
        put(dir, [@"enabled-slider-" stringByAppendingString: suffix], slider);
    }
    [pool release];
    return 0;
}
