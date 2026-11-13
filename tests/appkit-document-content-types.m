// Copyright (C) 2026 Lubos Dolezel
//
// NSDocument / NSDocumentController / NSSavePanel behaviour for document types that are named by
// content type identifiers, plus the autosaving delay.
#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UTType.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

@interface TypesController : NSDocumentController
- (void)setTypes:(NSArray *)types;
@end
@implementation TypesController
- (void)setTypes:(NSArray *)types {
    [_fileTypes release];
    _fileTypes = [types copy];
}
@end

@interface AutosavingDocument : NSDocument
{
    int _writes;
}
@property(assign) int writes;
@end
@implementation AutosavingDocument
@synthesize writes = _writes;
+ (BOOL)autosavesInPlace {
    return YES;
}
- (NSData *)dataOfType:(NSString *)type error:(NSError **)error {
    self.writes++;
    return [@"x" dataUsingEncoding:NSUTF8StringEncoding];
}
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error {
    return YES;
}
@end

int main(void) {
    @autoreleasepool {
        TypesController *controller = [[TypesController alloc] init];
        NSDictionary *byContentType = @{@"CFBundleTypeName": @"Plain document",
                                        @"LSItemContentTypes": @[@"public.plain-text"]};
        NSDictionary *explicitExt = @{@"CFBundleTypeName": @"Explicit document",
                                      @"CFBundleTypeExtensions": @[@"xyz"],
                                      @"LSItemContentTypes": @[@"public.plain-text"]};
        [controller setTypes:@[byContentType, explicitExt]];

        // A type that lists no extensions gets them from its content types.
        NSArray *ext = [controller fileExtensionsFromType:@"Plain document"];
        CHECK([ext containsObject:@"txt"], "content-type-only type: extension from UTType");
        // Listed extensions win.
        CHECK([[controller fileExtensionsFromType:@"Explicit document"] isEqual:@[@"xyz"]],
              "listed extensions are returned as they are");
        // A content type identifier may itself be the type name.
        CHECK([[controller fileExtensionsFromType:@"public.plain-text"] containsObject:@"txt"],
              "identifier used as type name");
        CHECK([controller fileExtensionsFromType:@"No such type"] == nil, "unknown type gives nil");
        CHECK([controller fileExtensionsFromType:nil] == nil, "nil type gives nil");

        // Types are found by their content type identifier too.
        CHECK([[controller _infoForType:@"public.plain-text"] isEqual:byContentType],
              "_infoForType by content type identifier");

        // NSSavePanel: allowedContentTypes derives allowedFileTypes.
        NSSavePanel *panel = [NSSavePanel savePanel];
        CHECK([[panel allowedContentTypes] count] == 0, "no content types by default");
        [panel setAllowedContentTypes:@[[UTType typeWithIdentifier:@"public.plain-text"]]];
        CHECK([[panel allowedContentTypes] count] == 1, "content types stored");
        CHECK([[panel allowedFileTypes] containsObject:@"txt"], "allowedFileTypes from content types");
        [panel setAllowedContentTypes:@[]];
        CHECK([panel allowedFileTypes] == nil, "empty content types allow any file");

        // Document blocks run, and the save completion handler is called.
        AutosavingDocument *doc = [[AutosavingDocument alloc] init];
        __block int ran = 0;
        [doc performAsynchronousFileAccessUsingBlock:^(void (^done)(void)) { ran++; done(); }];
        [doc performActivityWithSynchronousWaiting:YES usingBlock:^(void (^done)(void)) { ran++; done(); }];
        CHECK(ran == 2, "activity and file access blocks run");
        CHECK(![doc isInViewingMode], "not in viewing mode");

        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"darling-autosave-test.txt"];
        [[@"seed" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES];
        [doc setFileURL:[NSURL fileURLWithPath:path]];
        [doc setFileType:@"public.plain-text"];

        // Autosaving delay: an edit schedules one autosave in place; the default delay of 0 schedules none.
        NSDocumentController *shared = [NSDocumentController sharedDocumentController];
        CHECK([shared autosavingDelay] == 0, "default autosaving delay is 0");
        [doc updateChangeCount:NSChangeDone];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        CHECK(doc.writes == 0, "no autosave with delay 0");

        [shared setAutosavingDelay:0.1];
        CHECK([shared autosavingDelay] == 0.1, "autosaving delay stored");
        [doc updateChangeCount:NSChangeDone];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];
        CHECK(doc.writes >= 1, "edited document autosaved after the delay");

        // Closing cancels a pending autosave.
        int before = doc.writes;
        [doc updateChangeCount:NSChangeDone];
        [doc close];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
        CHECK(doc.writes == before, "close cancels the pending autosave");

        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        [doc release];
        [controller release];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
