/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The drag API of macOS 10.7 (NSDraggingItem, NSDraggingImageComponent,
 * -[NSView beginDraggingSessionWithItems:event:source:], NSDraggingSession)
 * and the file promises of 10.12 (NSFilePromiseProvider,
 * NSFilePromiseReceiver), as observed on macOS 26.7.3:
 *  - an item keeps its object; its frame starts empty and it has no image
 *    components until it is given some; -setDraggingFrame:contents: makes one
 *    icon component with the contents that fills the frame;
 *  - a session is returned before its source hears of the drag, with the
 *    defaults its header gives (no formation, animates back, a sequence
 *    number), the items written to the drag pasteboard, and items enumerated
 *    as new NSDraggingItems holding what the classes read;
 *  - quirk (see the QUIRK comment in NSDraggingSession.m): while a session
 *    waits for the run loop, another one is not begun and nil is returned;
 *  - a provider writes a promise as the metadata, name, suggested name,
 *    content type and ID types (the names promised), and the pasteboard adds
 *    the legacy promise type; a receiver reads such an item, and nothing else,
 *    with the provider's file type, and no file names until asked for them.
 *    (Receiving the file could not be observed outside a real drag.)
 * Needs a window server (the session's view is in a window), but the drag is
 * never run: the test ends without returning to the run loop.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface Source : NSView <NSDraggingSource> {
  @public
    int calls;
}
@end

@implementation Source
- (NSDragOperation) draggingSession: (NSDraggingSession *) session
    sourceOperationMaskForDraggingContext: (NSDraggingContext) context
{
    calls++;
    return NSDragOperationCopy;
}
- (void) draggingSession: (NSDraggingSession *) session willBeginAtPoint: (NSPoint) point {
    calls++;
}
- (void) draggingSession: (NSDraggingSession *) session
            endedAtPoint: (NSPoint) point
               operation: (NSDragOperation) operation
{
    calls++;
}
@end

@interface PromiseDelegate : NSObject <NSFilePromiseProviderDelegate>
@end

@implementation PromiseDelegate
- (NSString *) filePromiseProvider: (NSFilePromiseProvider *) provider fileNameForType: (NSString *) type {
    return @"promised.txt";
}
- (void) filePromiseProvider: (NSFilePromiseProvider *) provider
           writePromiseToURL: (NSURL *) url
           completionHandler: (void (^)(NSError *)) completion
{
    completion(nil);
}
@end

static void testItems(void)
{
    NSString *object = @"hello";
    NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter: object];
    expect(item.item == object, "an item keeps its object");
    expect(NSEqualRects(item.draggingFrame, NSZeroRect), "an item's frame starts empty");
    expect(item.imageComponentsProvider == nil && item.imageComponents == nil,
           "an item has no image components until it is given some");

    NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(10, 20)];
    [item setDraggingFrame: NSMakeRect(5, 6, 30, 40) contents: image];
    expect(NSEqualRects(item.draggingFrame, NSMakeRect(5, 6, 30, 40)), "setDraggingFrame:contents: sets the frame");
    expect(item.imageComponentsProvider != nil, "setDraggingFrame:contents: sets a provider");
    NSArray<NSDraggingImageComponent *> *components = item.imageComponents;
    expect(components.count == 1, "setDraggingFrame:contents: makes one component");
    NSDraggingImageComponent *icon = components.firstObject;
    expect([icon.key isEqualToString: NSDraggingImageComponentIconKey], "the component is the icon");
    expect(icon.contents == image, "the component shows the contents");
    expect(NSEqualRects(icon.frame, NSMakeRect(0, 0, 30, 40)), "the component fills the item");

    NSDraggingImageComponent *component = [[NSDraggingImageComponent alloc] initWithKey: @"custom"];
    expect([component.key isEqualToString: @"custom"], "a component keeps its key");
    expect(component.contents == nil && NSEqualRects(component.frame, NSZeroRect),
           "a component starts without contents or frame");
    expect([NSDraggingImageComponentIconKey isEqualToString: @"icon"]
           && [NSDraggingImageComponentLabelKey isEqualToString: @"label"], "the component keys");
}

static void testSession(void)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 200)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    Source *view = [[Source alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)];
    window.contentView = view;
    [window orderFront: nil];
    NSEvent *event = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown
                                        location: NSMakePoint(50, 50)
                                   modifierFlags: 0
                                       timestamp: 0
                                    windowNumber: window.windowNumber
                                         context: nil
                                     eventNumber: 0
                                      clickCount: 1
                                        pressure: 1];

    NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter: @"dragged"];
    [item setDraggingFrame: NSMakeRect(40, 40, 10, 10)
                  contents: [[NSImage alloc] initWithSize: NSMakeSize(10, 10)]];
    NSDraggingSession *session = [view beginDraggingSessionWithItems: @[ item ] event: event source: view];
    expect(session != nil, "a session is returned");
    expect(view->calls == 0, "the source hears of the drag only after the method returns");
    expect(session.draggingFormation == NSDraggingFormationNone, "the default formation is none");
    expect(session.animatesToStartingPositionsOnCancelOrFail, "a session animates back by default");
    expect(session.draggingLeaderIndex == 0, "the leader is the item under the event");
    expect(session.draggingSequenceNumber > 0, "a session has a sequence number");

    NSPasteboard *pasteboard = session.draggingPasteboard;
    expect([pasteboard.name isEqualToString: NSPasteboardNameDrag], "a session uses the drag pasteboard");
    expect([[pasteboard stringForType: NSPasteboardTypeString] isEqualToString: @"dragged"],
           "the items are written to the pasteboard");

    __block int strings = 0;
    [session enumerateDraggingItemsWithOptions: 0 forView: view classes: @[ [NSString class] ]
                                 searchOptions: @{} usingBlock: ^(NSDraggingItem *found, NSInteger idx, BOOL *stop) {
        strings++;
        expect(idx == 0, "the index of the item");
        expect(found != item, "the enumeration gives a new item");
        expect([found.item isEqual: @"dragged"], "the new item holds what the class read");
        expect(NSEqualSizes(found.draggingFrame.size, NSMakeSize(10, 10)), "the new item has the item's size");
    }];
    expect(strings == 1, "the string item is enumerated");

    __block int urls = 0;
    [session enumerateDraggingItemsWithOptions: 0 forView: view classes: @[ [NSURL class] ]
                                 searchOptions: @{} usingBlock: ^(NSDraggingItem *found, NSInteger idx, BOOL *stop) {
        urls++;
    }];
    expect(urls == 0, "an item no class can read is skipped");

    __block int items = 0;
    [session enumerateDraggingItemsWithOptions: 0 forView: nil classes: @[ [NSPasteboardItem class] ]
                                 searchOptions: @{} usingBlock: ^(NSDraggingItem *found, NSInteger idx, BOOL *stop) {
        items++;
        expect([found.item isKindOfClass: [NSPasteboardItem class]], "NSPasteboardItem reads any item");
    }];
    expect(items == 1, "the pasteboard item is enumerated");

    NSDraggingItem *second = [[NSDraggingItem alloc] initWithPasteboardWriter: @"second"];
    second.draggingFrame = NSMakeRect(0, 0, 10, 10);
    NSDraggingSession *next = [view beginDraggingSessionWithItems: @[ second ] event: event source: view];
    expect(next == nil, "quirk: a second session waits for none, it is not begun");

    session.draggingFormation = NSDraggingFormationStack;
    expect(session.draggingFormation == NSDraggingFormationStack, "the formation can be set");
}

static void testFilePromises(void)
{
    NSArray *readable = [NSFilePromiseReceiver readableDraggedTypes];
    expect(readable.count == 3 && [readable containsObject: @"com.apple.NSFilePromiseItemMetaData"]
           && [readable containsObject: @"com.apple.pasteboard.promised-file-content-type"],
           "the types a receiver reads");

    PromiseDelegate *delegate = [[PromiseDelegate alloc] init];
    NSFilePromiseProvider *provider = [[NSFilePromiseProvider alloc] initWithFileType: @"public.plain-text"
                                                                             delegate: delegate];
    expect([provider.fileType isEqualToString: @"public.plain-text"] && provider.delegate == delegate
           && provider.userInfo == nil, "a provider keeps its file type and delegate");

    NSPasteboard *scratch = [NSPasteboard pasteboardWithUniqueName];
    NSArray *writable = [provider writableTypesForPasteboard: scratch];
    NSArray *expected = @[ @"com.apple.NSFilePromiseItemMetaData", @"com.apple.pasteboard.promised-file-name",
                           @"com.apple.pasteboard.promised-suggested-file-name",
                           @"com.apple.pasteboard.promised-file-content-type",
                           @"com.apple.pasteboard.NSFilePromiseID" ];
    expect([writable isEqualToArray: expected], "the types a provider writes");
    expect([provider writingOptionsForType: expected[1] pasteboard: scratch] == NSPasteboardWritingPromised
           && [provider writingOptionsForType: expected[2] pasteboard: scratch] == NSPasteboardWritingPromised
           && [provider writingOptionsForType: expected[0] pasteboard: scratch] == 0
           && [provider writingOptionsForType: expected[3] pasteboard: scratch] == 0,
           "the names are promised");
    expect([[provider pasteboardPropertyListForType: expected[0]]
            isEqual: @{ @"com.apple.pasteboard.promised-file-content-type": @"public.plain-text" }],
           "the metadata names the file type");
    expect([[provider pasteboardPropertyListForType: expected[2]] isEqual: @"promised.txt"],
           "the suggested name is the delegate's");
    expect([[provider pasteboardPropertyListForType: expected[3]] isEqual: @"public.plain-text"],
           "the content type is the file type");
    expect([provider pasteboardPropertyListForType: expected[1]] == nil, "the file name is not known yet");

    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [pasteboard clearContents];
    expect([pasteboard writeObjects: @[ provider ]], "a provider can be written");
    expect([pasteboard.types containsObject: NSFilesPromisePboardType], "the legacy promise type is added");

    NSArray *receivers = [pasteboard readObjectsForClasses: @[ [NSFilePromiseReceiver class] ] options: nil];
    expect(receivers.count == 1, "a promise is read as a receiver");
    NSFilePromiseReceiver *receiver = receivers.firstObject;
    expect([receiver.fileTypes isEqualToArray: @[ @"public.plain-text" ]], "the receiver has the file type");
    expect(receiver.fileNames.count == 0, "the receiver has no file names yet");

    [pasteboard clearContents];
    [pasteboard writeObjects: @[ @"text" ]];
    expect([[pasteboard readObjectsForClasses: @[ [NSFilePromiseReceiver class] ] options: nil] count] == 0,
           "text is not a promise");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        testItems();
        testFilePromises();
        // last: it leaves the drags waiting for the run loop
        testSession();
    }

    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
