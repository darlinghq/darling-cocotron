// Copyright (C) 2026 Lubos Dolezel
//
// NSDocumentController (NSDocumentController.h): -openDocument: invokes
// -beginOpenPanelWithCompletionHandler:, which invokes -beginOpenPanel:forTypes:completionHandler: with
// the content types and extensions of the application's document types (nil, meaning every file, when a
// type accepts any extension). A subclass that overrides only -runModalOpenPanel:forTypes: has that
// method used instead, and one that overrides -fileNamesFromRunningOpenPanel keeps the old path.
// Build with candidate AppKit; no panel is shown.
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#import <AppKit/NSOpenPanel.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface OpenedDocument : NSDocument
@end
@implementation OpenedDocument
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error { return YES; }
@end

static NSArray *gTypes;                  // what the open panel hook was given
static NSOpenPanel *gPanel;
static int gBeginPanelCalls, gBeginCalls, gModalCalls, gNamesCalls;
static NSArray *gURLsToChoose;            // what the stand-in panel "chooses"
static NSInteger gResult;

@interface PanelController : NSDocumentController
- (void)setTypes:(NSArray *)types;
@end
@implementation PanelController
- (void)setTypes:(NSArray *)types {
    [_fileTypes release];
    _fileTypes = [types copy];
}
// Stand-in for the panel: records the request instead of presenting it.
- (void)beginOpenPanel:(NSOpenPanel *)panel forTypes:(NSArray *)types completionHandler:(void (^)(NSInteger))handler {
    gBeginPanelCalls++;
    gPanel = panel;
    gTypes = [types copy];
    handler(gResult);
}
@end

@interface HandlerController : PanelController
@end
@implementation HandlerController
// A subclass hooking the URL-level method gets -openDocument:'s request.
- (void)beginOpenPanelWithCompletionHandler:(void (^)(NSArray *))handler {
    gBeginCalls++;
    handler(gURLsToChoose);
}
@end

static NSArray *types(void) {
    return [NSArray arrayWithObjects:
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"Plain", @"CFBundleTypeName", @"Editor", @"CFBundleTypeRole",
            [NSArray arrayWithObject:@"public.plain-text"], @"LSItemContentTypes",
            [NSArray arrayWithObjects:@"txt", @"text", nil], @"CFBundleTypeExtensions",
            @"OpenedDocument", @"NSDocumentClass", nil],
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"Foo", @"CFBundleTypeName", @"Viewer", @"CFBundleTypeRole",
            [NSArray arrayWithObject:@"foo"], @"CFBundleTypeExtensions",
            @"OpenedDocument", @"NSDocumentClass", nil],
        nil];
}

int main(void) {
    @autoreleasepool {
        PanelController *controller = [[HandlerController alloc] init];
        expect([NSDocumentController sharedDocumentController] == controller, @"the first controller is shared");
        [controller setTypes:types()];

        expect([controller respondsToSelector:@selector(beginOpenPanelWithCompletionHandler:)], @"beginOpenPanelWithCompletionHandler: exists");
        expect([controller respondsToSelector:@selector(beginOpenPanel:forTypes:completionHandler:)], @"beginOpenPanel:forTypes:completionHandler: exists");

        // -openDocument: goes through -beginOpenPanelWithCompletionHandler: and opens what it returns.
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"appkit-open-panel.txt"];
        [@"x" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        gURLsToChoose = [NSArray arrayWithObject:[NSURL fileURLWithPath:path]];
        [controller openDocument:nil];
        expect(gBeginCalls == 1, @"openDocument: invokes beginOpenPanelWithCompletionHandler:");
        expect([[controller documents] count] == 1 && [[[[controller documents] objectAtIndex:0] fileURL] isEqual:gURLsToChoose[0]], @"the chosen file is opened");

        // A cancelled panel opens nothing.
        gURLsToChoose = nil;
        [controller openDocument:nil];
        expect(gBeginCalls == 2 && [[controller documents] count] == 1, @"cancelling opens nothing");

        // The default beginOpenPanelWithCompletionHandler: asks beginOpenPanel:forTypes:completionHandler:.
        PanelController *plain = [[PanelController alloc] init]; // not shared, used directly
        [plain setTypes:types()];
        __block NSArray *urls = (NSArray *)@"unset";
        gResult = NSModalResponseCancel;
        [plain beginOpenPanelWithCompletionHandler:^(NSArray *chosen) { urls = chosen; }];
        expect(gBeginPanelCalls == 1, @"the URL-level method asks for a panel once");
        expect(gPanel != nil && [gPanel isKindOfClass:[NSOpenPanel class]], @"the panel is an open panel");
        expect([gPanel allowsMultipleSelection], @"the panel allows several files");
        NSArray *expected = [NSArray arrayWithObjects:@"public.plain-text", @"txt", @"text", @"foo", nil];
        expect([gTypes isEqualToArray:expected], [NSString stringWithFormat:@"the types are the content types and extensions of every document type (got %@)", gTypes]);
        expect(urls == nil, @"cancelling calls the handler with nil");

        // Types that accept any extension offer every file.
        NSMutableArray *withWildcard = [NSMutableArray arrayWithArray:types()];
        [withWildcard addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            @"Any", @"CFBundleTypeName", @"Viewer", @"CFBundleTypeRole",
            [NSArray arrayWithObject:@"*"], @"CFBundleTypeExtensions", @"OpenedDocument", @"NSDocumentClass", nil]];
        [plain setTypes:withWildcard];
        [plain beginOpenPanelWithCompletionHandler:^(NSArray *chosen) { urls = chosen; }];
        expect(gTypes == nil, @"a wildcard extension means no type restriction");

        // Compatibility: only -runModalOpenPanel:forTypes: overridden.
        // (checked with a subclass defined below)
        extern int RunModalCheck(void);
        expect(RunModalCheck() == 0, @"a modal-only override is used");

        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        printf("PASS\n");
    }
    return 0;
}

@interface ModalOnlyController : NSDocumentController
- (void)setTypes:(NSArray *)types;
@end
@implementation ModalOnlyController
- (void)setTypes:(NSArray *)types {
    [_fileTypes release];
    _fileTypes = [types copy];
}
- (NSInteger)runModalOpenPanel:(NSOpenPanel *)panel forTypes:(NSArray *)types {
    gModalCalls++;
    gTypes = [types copy];
    return NSModalResponseCancel;
}
@end

int RunModalCheck(void) {
    // The shared controller already exists, so make this one directly.
    ModalOnlyController *controller = [[ModalOnlyController alloc] init];
    [controller setTypes:types()];
    __block BOOL called = NO;
    __block NSArray *result = (NSArray *)@"unset";
    [controller beginOpenPanelWithCompletionHandler:^(NSArray *chosen) { called = YES; result = chosen; }];
    if (gModalCalls != 1 || !called || result != nil)
        return 1;
    return [gTypes count] == 4 ? 0 : 2;
}
