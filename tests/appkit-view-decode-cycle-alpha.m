// Copyright (C) 2026 Lubos Dolezel
// A view that an archive refers to before its superview (a nib's user defined runtime attributes
// connect to a control first) is still being decoded while the superview decodes the hierarchy
// around it, and a superview that turns layers on creates the layer of that unfinished view. The
// view must come out with alpha value 1 and an opaque layer.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

// Like a nib's custom view that turns layers on once it is decoded.
@interface LayerContainer : NSView
@end
@implementation LayerContainer
- (id)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder: coder]))
        [self setWantsLayer: YES];
    return self;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSView *container = [[[LayerContainer alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
        NSButton *first = [[[NSButton alloc] initWithFrame: NSMakeRect(10, 10, 80, 22)] autorelease];
        NSButton *second = [[[NSButton alloc] initWithFrame: NSMakeRect(100, 10, 80, 22)] autorelease];
        [container addSubview: first];
        [container addSubview: second];

        // The button is encoded (and so decoded) before the container that holds it.
        NSMutableData *data = [NSMutableData data];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData: data];
        [archiver setRequiresSecureCoding: NO];
        [archiver encodeObject: first forKey: @"first"];
        [archiver encodeObject: container forKey: @"container"];
        [archiver finishEncoding];
        [archiver release];

        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData: data];
        [unarchiver setRequiresSecureCoding: NO];
        NSButton *decodedFirst = [unarchiver decodeObjectForKey: @"first"];
        NSView *decodedContainer = [unarchiver decodeObjectForKey: @"container"];
        [unarchiver finishDecoding];
        [unarchiver release];

        CHECK(decodedFirst != nil);
        CHECK(decodedContainer != nil);
        CHECK([[decodedContainer subviews] count] == 2);
        CHECK([decodedFirst superview] == decodedContainer);
        CHECK([decodedFirst alphaValue] == 1.0);
        if ([decodedFirst layer] != nil)
            CHECK([[decodedFirst layer] opacity] == 1.0f);
        for (NSView *view in [decodedContainer subviews]) {
            CHECK([view alphaValue] == 1.0);
            if ([view layer] != nil)
                CHECK([[view layer] opacity] == 1.0f);
        }
    }
    if (g_failures == 0)
        printf("PASS\n");
    return g_failures != 0;
}
