/* Copyright (C) 2026 Lubos Dolezel */
// -[NSPathControl delegate] and -setDelegate: store and return the receiver's delegate, nil in a new control
// (https://developer.apple.com/documentation/appkit/nspathcontrol/delegate). Apple's SDK declares the property weak:
// setting it does not retain the delegate, and the property reads nil once the delegate is deallocated.
// Needs a Darling guest (a window system session is not assumed to be absent). Build without ARC.
#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface PathDelegate : NSObject <NSPathControlDelegate>
@end
@implementation PathDelegate
- (BOOL)pathControl:(NSPathControl *)pathControl acceptDrop:(id<NSDraggingInfo>)info { return NO; }
- (BOOL)pathControl:(NSPathControl *)pathControl
        shouldDragPathComponentCell:(NSPathComponentCell *)cell
                     withPasteboard:(NSPasteboard *)pasteboard { return NO; }
- (NSDragOperation)pathControl:(NSPathControl *)pathControl validateDrop:(id<NSDraggingInfo>)info {
    return NSDragOperationNone;
}
- (void)pathControl:(NSPathControl *)pathControl willDisplayOpenPanel:(NSOpenPanel *)openPanel {}
- (void)pathControl:(NSPathControl *)pathControl willPopUpMenu:(NSMenu *)menu {}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSPathControl *control = [[NSPathControl alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
        expect([control delegate] == nil, @"a new path control has no delegate");

        PathDelegate *delegate = [[PathDelegate alloc] init];
        NSUInteger retainsBefore = [delegate retainCount];
        [control setDelegate:delegate];
        // Measured before the getter: loading a weak reference returns the object retained and autoreleased,
        // which raises the count until the pool drains.
        expect([delegate retainCount] == retainsBefore, @"setting the delegate does not retain it");
        expect([control delegate] == delegate, @"the delegate is the one set");

        PathDelegate *other = [[PathDelegate alloc] init];
        [control setDelegate:other];
        expect([control delegate] == other, @"a second delegate replaces the first");

        NSPathControl *second = [[NSPathControl alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
        expect([second delegate] == nil, @"the delegate belongs to one control");

        [control setDelegate:nil];
        expect([control delegate] == nil, @"nil clears the delegate");

        // Weak: the property does not keep the delegate alive and reads nil after it is deallocated.
        PathDelegate *transient = [[PathDelegate alloc] init];
        [control setDelegate:transient];
        @autoreleasepool {
            // The getter returns the weak reference retained and autoreleased: keep that in an inner pool, so the
            // release below really deallocates the delegate.
            expect([control delegate] == transient, @"the transient delegate is set");
        }
        [transient release];
        expect([control delegate] == nil, @"the delegate reads nil after the delegate object is deallocated");

        // A control that is deallocated with a delegate set releases its weak slot without touching the delegate.
        NSPathControl *dying = [[NSPathControl alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
        [dying setDelegate:other];
        [dying release];
        printf("OK\n");
    }
    return 0;
}
