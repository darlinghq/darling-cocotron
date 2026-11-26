/* Copyright (C) 2026 Lubos Dolezel

   Licensed under the MIT license, the same as the rest of this project. */

// NSDocument does not remove undo actions of its own accord. On macOS 26.7.3 and 10.14.4 (x86_64, i386;
// black-box observation, probes p798 and p798b) the actions registered with a document or one of its window
// controllers as target stay in the undo manager after -removeWindowController:, after -setUndoManager: (in
// the old manager) and after the document and the controller are deallocated; and with
// -prepareWithInvocationTarget: the manager keeps the document alive. Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures, docDeallocs, ctlDeallocs;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

@interface Doc : NSDocument
@end
@implementation Doc
- (void)dealloc { docDeallocs++; [super dealloc]; }
- (void)ping:(id)x {}
- (BOOL)readFromData:(NSData *)d ofType:(NSString *)t error:(NSError **)e { return YES; }
- (NSData *)dataOfType:(NSString *)t error:(NSError **)e { return [NSData data]; }
@end
@interface Ctl : NSWindowController
@end
@implementation Ctl
- (void)dealloc { ctlDeallocs++; [super dealloc]; }
- (void)ping:(id)x {}
@end

static NSUndoManager *manager(void)
{
    NSUndoManager *um = [[[NSUndoManager alloc] init] autorelease];
    [um setGroupsByEvent:NO];
    return um;
}

static void group(NSUndoManager *um, id target)
{
    [um beginUndoGrouping];
    [um registerUndoWithTarget:target selector:@selector(ping:) object:nil];
    [um endUndoGrouping];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSUndoManager *um = manager();
        Doc *doc = [[Doc alloc] init];
        Ctl *ctl = [[Ctl alloc] initWithWindow:nil];
        [doc setUndoManager:um];
        [doc addWindowController:ctl];
        group(um, ctl);
        [doc removeWindowController:ctl];
        CHECK([um canUndo]);

        NSUndoManager *old = manager();
        [doc setUndoManager:old];
        group(old, doc);
        [doc setUndoManager:manager()];
        CHECK([old canUndo]);
        [ctl release];
        [doc release];

        NSUndoManager *kept = manager();
        Doc *d2 = [[Doc alloc] init];
        Ctl *c2 = [[Ctl alloc] initWithWindow:nil];
        [d2 setUndoManager:kept];
        [d2 addWindowController:c2];
        group(kept, d2);
        group(kept, c2);
        docDeallocs = ctlDeallocs = 0;
        [c2 release];
        [d2 release];
        CHECK(docDeallocs == 1 && ctlDeallocs == 1);
        CHECK([kept canUndo]);
        [kept removeAllActions];

        NSUndoManager *invocation = manager();
        Doc *d3 = [[Doc alloc] init];
        [d3 setUndoManager:invocation];
        [invocation beginUndoGrouping];
        [[invocation prepareWithInvocationTarget:d3] ping:nil];
        [invocation endUndoGrouping];
        docDeallocs = 0;
        [d3 release];
        CHECK(docDeallocs == 0);
        [invocation removeAllActions];
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
