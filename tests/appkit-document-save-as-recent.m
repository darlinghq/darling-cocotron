/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Saving a document that has no file yet runs the save panel for a Save As
// (NSSaveAsOperation), and a successful Save As tells the shared document
// controller with -noteNewRecentDocument:, after the document has its new
// file URL, even when the document writes its contents itself by overriding
// -writeToURL:ofType:forSaveOperation:originalContentsURL:error:. Saving in
// place and Save To do not note a recent document.
// Results as on macOS 26.7.3 and 10.14.4. No display needed. No ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
static NSMutableArray *calls;

static void expect(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

// Records what it is told; does not add to the user's recent documents.
@interface RecordingController : NSDocumentController
@end

@implementation RecordingController
- (void) noteNewRecentDocument: (NSDocument *) document {
    [calls addObject: [@"document " stringByAppendingString: [[document fileURL] lastPathComponent] ?: @"(none)"]];
}
- (void) noteNewRecentDocumentURL: (NSURL *) url {
    [calls addObject: [@"url " stringByAppendingString: [url lastPathComponent]]];
}
@end

@interface WritingDocument : NSDocument {
@public
    NSInteger _panelOperation;
}
@end

@implementation WritingDocument
+ (BOOL) autosavesInPlace {
    return NO;
}
- (BOOL) writeToURL: (NSURL *) url ofType: (NSString *) type forSaveOperation: (NSSaveOperationType) operation
        originalContentsURL: (NSURL *) original error: (NSError **) error {
    return [[@"text" dataUsingEncoding: NSUTF8StringEncoding] writeToURL: url atomically: YES];
}
- (BOOL) readFromData: (NSData *) data ofType: (NSString *) type error: (NSError **) error {
    return YES;
}
- (void) runModalSavePanelForSaveOperation: (NSSaveOperationType) operation delegate: (id) delegate
                           didSaveSelector: (SEL) selector contextInfo: (void *) info {
    _panelOperation = operation;
}
@end

static void save(NSDocument *document, NSString *path, NSSaveOperationType operation) {
    [calls removeAllObjects];
    __block BOOL done = NO;
    [document saveToURL: [NSURL fileURLWithPath: path] ofType: @"public.plain-text" forSaveOperation: operation
      completionHandler: ^(NSError *error) {
          done = YES;
      }];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow: 5];
    while (!done && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        calls = [[NSMutableArray alloc] init];
        [NSApplication sharedApplication];
        [[RecordingController alloc] init];
        char temp[] = "/tmp/darling-save-as-recent-XXXXXX";
        if (!mkdtemp(temp))
            return 2;
        NSString *directory = [NSString stringWithUTF8String: temp];

        WritingDocument *untitled = [[WritingDocument alloc] initWithType: @"public.plain-text" error: NULL];
        untitled->_panelOperation = -1;
        [untitled saveDocument: nil];
        expect(untitled->_panelOperation == NSSaveAsOperation, "saving a document without a file asks for a Save As");
        [untitled release];

        WritingDocument *document = [[WritingDocument alloc] initWithType: @"public.plain-text" error: NULL];
        save(document, [directory stringByAppendingPathComponent: @"a.txt"], NSSaveAsOperation);
        expect([calls isEqualToArray: @[@"document a.txt"]], "Save As notes the document with its new file as recent");
        save(document, [directory stringByAppendingPathComponent: @"a.txt"], NSSaveOperation);
        expect([calls count] == 0, "saving in place notes no recent document");
        save(document, [directory stringByAppendingPathComponent: @"b.txt"], NSSaveAsOperation);
        expect([calls isEqualToArray: @[@"document b.txt"]], "Save As under another name notes the new file");
        save(document, [directory stringByAppendingPathComponent: @"c.txt"], NSSaveToOperation);
        expect([calls count] == 0, "Save To notes no recent document");
        [document release];

        WritingDocument *fresh = [[WritingDocument alloc] initWithType: @"public.plain-text" error: NULL];
        save(fresh, [directory stringByAppendingPathComponent: @"d.txt"], NSSaveOperation);
        expect([calls count] == 0, "a save operation (not Save As) of a document without a file notes nothing");
        [fresh release];

        [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
