// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// The dragging object model: NSDraggingItem, NSDraggingImageComponent and the
// NSDraggingSession -[NSView beginDraggingSessionWithItems:event:source:]
// returns before the drag runs. Observed on macOS 26.7.3 and 10.14.4
// (darling's tests/collection-view.md, "Dragging sessions"). It returns before
// the run loop runs, so no drag takes place.
// Also, as observed on macOS 26.7.3:
//  - the component -setDraggingFrame:contents: makes is the same one each time
//    the item is asked for its components;
//  - quirk (see the QUIRK comment in -[NSView beginDraggingSessionWithItems:
//    event:source:]): while a session waits for the run loop, another one is
//    not begun and nil is returned (an item without a frame still raises);
//  - the file promises of 10.12: a provider writes a promise as the metadata,
//    name, suggested name, content type and ID types (the names promised), and
//    the pasteboard adds the legacy promise type; a receiver reads such an
//    item, and nothing else, with the provider's file type, and no file names
//    until asked for them. (Receiving the file could not be observed outside a
//    real drag.)
//
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdarg.h>
#include <stdio.h>

static int failures;
static void expect(BOOL ok, const char *format, ...) __attribute__((format(printf, 2, 3)));
static void expect(BOOL ok, const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    printf("%s ", ok ? "PASS" : "FAIL");
    vprintf(format, ap);
    printf("\n");
    va_end(ap);
    if (!ok)
        failures++;
}

static const char *rectString(NSRect rect)
{
    return [NSStringFromRect(rect) UTF8String];
}

@interface Source : NSObject <NSDraggingSource>
@end
@implementation Source
- (NSDragOperation) draggingSession: (NSDraggingSession *) session
    sourceOperationMaskForDraggingContext: (NSDraggingContext) context
{
    return NSDragOperationCopy;
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

static void test_dragging_item_frame_and_components(void)
{
    NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(10, 20)] autorelease];
    NSDraggingItem *item = [[[NSDraggingItem alloc] initWithPasteboardWriter: @"hello"] autorelease];
    expect([[item item] isEqual: @"hello"], "the item is the writer");
    expect(NSEqualRects([item draggingFrame], NSZeroRect), "a new item's frame is zero (%s)", rectString([item draggingFrame]));
    expect([item imageComponentsProvider] == nil && [[item imageComponents] count] == 0,
           "a new item has no provider and no components (%lu)", (unsigned long) [[item imageComponents] count]);

    [item setDraggingFrame: NSMakeRect(5, 6, 30, 40) contents: image];
    expect(NSEqualRects([item draggingFrame], NSMakeRect(5, 6, 30, 40)), "setDraggingFrame:contents: sets the frame (%s)",
           rectString([item draggingFrame]));
    expect([item imageComponentsProvider] != nil, "and a provider");
    NSArray *components = [item imageComponents];
    NSDraggingImageComponent *icon = [components firstObject];
    expect([components count] == 1 && [[icon key] isEqual: NSDraggingImageComponentIconKey] &&
               [icon contents] == image && NSEqualRects([icon frame], NSMakeRect(0, 0, 30, 40)),
           "whose one component is the icon, the contents, at the origin with the frame's size (%lu, %s, %s)",
           (unsigned long) [components count], [[icon key] UTF8String], rectString([icon frame]));
    expect([[item imageComponents] firstObject] == icon, "the provider gives the same component each time");

    NSDraggingItem *provided = [[[NSDraggingItem alloc] initWithPasteboardWriter: @"other"] autorelease];
    __block int calls = 0;
    [provided setImageComponentsProvider: ^NSArray * {
        calls++;
        return [NSArray arrayWithObject: [NSDraggingImageComponent
                                             draggingImageComponentWithKey: NSDraggingImageComponentLabelKey]];
    }];
    components = [provided imageComponents];
    expect(calls == 1 && [components count] == 1 &&
               [[[components firstObject] key] isEqual: NSDraggingImageComponentLabelKey],
           "imageComponents asks a provider (%d calls, %lu components)", calls, (unsigned long) [components count]);

    NSDraggingImageComponent *component = [NSDraggingImageComponent draggingImageComponentWithKey: @"k"];
    expect([[component key] isEqual: @"k"] && [component contents] == nil && NSEqualRects([component frame], NSZeroRect),
           "a new component has its key, no contents and a zero frame");
    expect([NSDraggingImageComponentIconKey isEqual: @"icon"] && [NSDraggingImageComponentLabelKey isEqual: @"label"],
           "the component keys are icon and label");
}

static NSArray *draggingItems(NSArray *writers)
{
    NSImage *image = [[[NSImage alloc] initWithSize: NSMakeSize(32, 32)] autorelease];
    NSMutableArray *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < [writers count]; i++) {
        NSDraggingItem *item = [[[NSDraggingItem alloc] initWithPasteboardWriter: [writers objectAtIndex: i]] autorelease];
        [item setDraggingFrame: NSMakeRect(10 + 40 * i, 10, 32, 32) contents: image];
        [items addObject: item];
    }
    return items;
}

static void test_begin_returns_session_with_pasteboard_items(NSView *view, NSEvent *down)
{
    NSArray *writers = [NSArray arrayWithObjects: [NSURL fileURLWithPath: @"/etc/hosts"], @"text",
                                                  [NSURL URLWithString: @"https://example.com/"], nil];
    Source *source = [[[Source alloc] init] autorelease];
    NSDraggingSession *session = [view beginDraggingSessionWithItems: draggingItems(writers) event: down source: source];
    expect(session != nil, "beginDraggingSessionWithItems: returns a session at once");
    expect([session draggingFormation] == NSDraggingFormationNone, "its formation is none (%ld)",
           (long) [session draggingFormation]);
    expect([session animatesToStartingPositionsOnCancelOrFail], "it animates back on cancel or failure");
    expect([session draggingSequenceNumber] != 0, "it has a sequence number");
    NSPasteboard *drag = [NSPasteboard pasteboardWithName: NSPasteboardNameDrag];
    expect([session draggingPasteboard] == drag, "its pasteboard is the drag pasteboard");
    NSArray *items = [drag pasteboardItems];
    BOOL inOrder = [items count] == 3 && [[[items objectAtIndex: 0] types] containsObject: NSPasteboardTypeFileURL] &&
                   [[[items objectAtIndex: 1] types] containsObject: NSPasteboardTypeString] &&
                   [[[items objectAtIndex: 2] types] containsObject: NSPasteboardTypeURL] &&
                   ![[[items objectAtIndex: 2] types] containsObject: NSPasteboardTypeFileURL];
    expect(inOrder, "each writer is its own pasteboard item, in order (%lu items)", (unsigned long) [items count]);

    NSMutableArray *seen = [NSMutableArray array];
    [session enumerateDraggingItemsWithOptions: 0
                                       forView: view
                                       classes: [NSArray arrayWithObject: [NSPasteboardItem class]]
                                 searchOptions: [NSDictionary dictionary]
                                    usingBlock: ^(NSDraggingItem *item, NSInteger index, BOOL *stop) {
                                        if ([[item item] isKindOfClass: [NSPasteboardItem class]] &&
                                            NSEqualSizes([item draggingFrame].size, NSMakeSize(32, 32)) &&
                                            [[item imageComponents] count] == 1)
                                            [seen addObject: [NSNumber numberWithInteger: index]];
                                    }];
    expect([[seen componentsJoinedByString: @","] isEqual: @"0,1,2"],
           "enumerating as pasteboard items gives every item with its frame's size and image (%s)",
           [[seen componentsJoinedByString: @","] UTF8String]);

    [seen removeAllObjects];
    [session enumerateDraggingItemsWithOptions: 0
                                       forView: view
                                       classes: [NSArray arrayWithObject: [NSURL class]]
                                 searchOptions: [NSDictionary dictionary]
                                    usingBlock: ^(NSDraggingItem *item, NSInteger index, BOOL *stop) {
                                        [seen addObject: [NSString stringWithFormat: @"%ld %@", (long) index, [item item]]];
                                    }];
    NSString *urls = [seen componentsJoinedByString: @", "];
    expect([urls isEqual: @"0 file:///etc/hosts, 2 https://example.com/"],
           "enumerating as URLs gives the items that are URLs, as URLs (%s)", [urls UTF8String]);

    [seen removeAllObjects];
    [session enumerateDraggingItemsWithOptions: 0
                                       forView: nil
                                       classes: [NSArray arrayWithObject: [NSString class]]
                                 searchOptions: [NSDictionary dictionary]
                                    usingBlock: ^(NSDraggingItem *item, NSInteger index, BOOL *stop) {
                                        [seen addObject: [NSString stringWithFormat: @"%ld %@", (long) index, [item item]]];
                                    }];
    NSString *strings = [seen componentsJoinedByString: @", "];
    expect([strings isEqual: @"1 text"], "enumerating as strings gives the string (%s)", [strings UTF8String]);

    [session setDraggingFormation: NSDraggingFormationList];
    [session setAnimatesToStartingPositionsOnCancelOrFail: NO];
    [session setDraggingLeaderIndex: 2];
    expect([session draggingFormation] == NSDraggingFormationList && ![session animatesToStartingPositionsOnCancelOrFail] &&
               [session draggingLeaderIndex] == 2,
           "the formation, animation and leader can be set");

    NSDraggingSession *another = [view beginDraggingSessionWithItems: draggingItems([NSArray arrayWithObject: @"x"])
                                                               event: down
                                                              source: source];
    expect(another == nil, "quirk: a second session waits for none, it is not begun");

    BOOL raised = NO;
    @try {
        [view beginDraggingSessionWithItems:
                  [NSArray arrayWithObject: [[[NSDraggingItem alloc] initWithPasteboardWriter: @"x"] autorelease]]
                                      event: down
                                     source: source];
    } @catch (NSException *exception) {
        raised = [[exception name] isEqual: NSRangeException];
    }
    expect(raised, "an item without a frame raises NSRangeException");
}

static void test_file_promises(void)
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
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    test_dragging_item_frame_and_components();
    test_file_promises();

    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease];
    [[window contentView] addSubview: view];
    [window makeKeyAndOrderFront: nil];
    NSEvent *down = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown
                                       location: NSMakePoint(50, 50)
                                  modifierFlags: 0
                                      timestamp: [[NSProcessInfo processInfo] systemUptime]
                                   windowNumber: [window windowNumber]
                                        context: nil
                                    eventNumber: 0
                                     clickCount: 1
                                       pressure: 1];
    test_begin_returns_session_with_pasteboard_items(view, down);

    [pool release];
    if (failures)
        printf("FAILED %d\n", failures);
    else
        printf("ALL PASSED\n");
    return failures != 0;
}
