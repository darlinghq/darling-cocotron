// Copyright (C) 2026 Lubos Dolezel
//
// NSDocument (NSDocument.h): -fileNameExtensionForType:saveOperation: (the preferred extension of a
// content type identifier, else the first extension of the legacy document type), -duplicateAndReturnError:
// (an unsaved copy of the same class, named "<name> copy" and added to the document controller),
// -duplicateDocument: / -duplicateDocumentWithDelegate:didDuplicateSelector:contextInfo:,
// -checkAutosavingSafetyAndReturnError: and -performSynchronousFileAccessUsingBlock:.
// The names and the unsaved state of duplicates match black-box observation on macOS 26.7.3.
// Build with candidate AppKit; no windows are needed.
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface TextDocument : NSDocument {
@public
    NSString *text;
    BOOL failWrites;
    BOOL richCopies;
}
@end
@implementation TextDocument
- (NSData *)dataOfType:(NSString *)type error:(NSError **)error {
    if (failWrites) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteOutOfSpaceError userInfo:nil];
        return nil;
    }
    return [text ? text : @"" dataUsingEncoding:NSUTF8StringEncoding];
}
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error {
    [text release];
    text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return YES;
}
// A document that cannot be saved in its own type may pick another one for its copies.
- (NSString *)autosavingFileType {
    return richCopies ? @"public.plain-text" : [super autosavingFileType];
}
@end

@interface TypedController : NSDocumentController
@end
@implementation TypedController
- (id)init {
    self = [super init];
    [_fileTypes release];
    _fileTypes = [[NSArray arrayWithObjects:
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"Plain Text", @"CFBundleTypeName", @"Editor", @"CFBundleTypeRole",
            [NSArray arrayWithObject:@"public.plain-text"], @"LSItemContentTypes",
            @"TextDocument", @"NSDocumentClass", nil],
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"Legacy Foo", @"CFBundleTypeName", @"Viewer", @"CFBundleTypeRole",
            [NSArray arrayWithObjects:@"foo", @"bar", nil], @"CFBundleTypeExtensions",
            @"TextDocument", @"NSDocumentClass", nil],
        nil] retain];
    return self;
}
@end

@interface DuplicateWatcher : NSObject {
@public
    NSDocument *seen;
    BOOL didDuplicate;
    int calls;
}
@end
@implementation DuplicateWatcher
- (void)document:(NSDocument *)document didDuplicate:(BOOL)duplicated contextInfo:(void *)info {
    seen = document; didDuplicate = duplicated; calls++;
    expect(info == (void *)0x1234, @"the context info is passed back");
}
@end

int main(void) {
    @autoreleasepool {
        TypedController *controller = [[TypedController alloc] init];
        expect([NSDocumentController sharedDocumentController] == controller, @"the first controller is the shared one");

        TextDocument *plain = [[[TextDocument alloc] init] autorelease];

        // -fileNameExtensionForType:saveOperation:
        expect([plain respondsToSelector:@selector(fileNameExtensionForType:saveOperation:)], @"NSDocument answers fileNameExtensionForType:saveOperation:");
        expect([[plain fileNameExtensionForType:@"public.plain-text" saveOperation:NSSaveOperation] isEqualToString:@"txt"], @"plain text -> txt");
        expect([[plain fileNameExtensionForType:@"public.rtf" saveOperation:NSSaveAsOperation] isEqualToString:@"rtf"], @"rtf -> rtf");
        expect([[plain fileNameExtensionForType:@"public.html" saveOperation:NSSaveToOperation] isEqualToString:@"html"], @"html -> html (any save operation)");
        expect([[plain fileNameExtensionForType:@"Legacy Foo" saveOperation:NSSaveOperation] isEqualToString:@"foo"], @"a legacy type name gives the first extension of its type");
        expect([plain fileNameExtensionForType:@"com.example.no-such-type" saveOperation:NSSaveOperation] == nil, @"an unknown type has no extension");
        expect([plain fileNameExtensionForType:@"public.data" saveOperation:NSSaveOperation] == nil, @"a type without a preferred extension has none");
        expect([plain fileNameExtensionForType:@"" saveOperation:NSSaveOperation] == nil, @"an empty type has none");

        // -performSynchronousFileAccessUsingBlock:
        __block int ran = 0;
        __block BOOL sameThread = NO;
        NSThread *caller = [NSThread currentThread];
        [plain performSynchronousFileAccessUsingBlock:^{
            ran++;
            sameThread = ([NSThread currentThread] == caller);
            [plain performSynchronousFileAccessUsingBlock:^{ ran += 10; }]; // nested access is fine
        }];
        expect(ran == 11, @"the block ran once, the nested one too, before the call returned");
        expect(sameThread, @"the block ran on the calling thread");

        // -checkAutosavingSafetyAndReturnError:
        NSError *error = [NSError errorWithDomain:@"keep" code:7 userInfo:nil];
        NSError *original = error;
        expect([plain checkAutosavingSafetyAndReturnError:&error], @"a plain document is safe to autosave");
        expect(error == original, @"no error is signalled for a safe document");
        expect([plain checkAutosavingSafetyAndReturnError:NULL], @"a NULL error pointer is accepted");

        // -duplicateAndReturnError:
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"appkit-duplicate-source.txt"];
        [@"original text" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        error = nil;
        TextDocument *source = [[[TextDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] ofType:@"public.plain-text" error:&error] autorelease];
        expect(source != nil, @"the source document opens");
        [controller addDocument:source];
        NSUInteger documents = [[controller documents] count];

        TextDocument *copy = (TextDocument *)[source duplicateAndReturnError:&error];
        expect(copy != nil && error == nil, @"duplicating gives a document");
        expect([copy class] == [TextDocument class], @"the copy has the class of the original");
        expect([copy->text isEqualToString:@"original text"], @"the copy has the contents");
        expect([copy fileURL] == nil, @"a copy has no file URL");
        expect([[copy fileType] isEqualToString:@"public.plain-text"], @"the copy keeps the type");
        expect([[copy displayName] isEqualToString:@"appkit-duplicate-source copy"], @"the copy is named after the original without its extension");
        expect([copy isDocumentEdited], @"a copy has changes to save");
        expect([copy isDraft], @"a copy is a draft");
        expect([[controller documents] containsObject:copy] && [[controller documents] count] == documents + 1, @"the copy is added to the controller");

        // A change of the original after copying does not reach the copy.
        source->text = @"changed";
        expect([copy->text isEqualToString:@"original text"], @"the copy is independent");

        TextDocument *second = (TextDocument *)[source duplicateAndReturnError:&error];
        expect([[second displayName] isEqualToString:@"appkit-duplicate-source copy 2"], @"the next copy is numbered");
        TextDocument *ofCopy = (TextDocument *)[copy duplicateAndReturnError:&error];
        expect([[ofCopy displayName] isEqualToString:@"appkit-duplicate-source copy 3"], @"a copy of a copy is named from the original's name");

        // An unsaved document is copied too, named after its own name.
        TextDocument *untitled = [[[TextDocument alloc] init] autorelease];
        untitled->text = @"unsaved";
        [untitled setFileType:@"public.plain-text"];
        TextDocument *untitledCopy = (TextDocument *)[untitled duplicateAndReturnError:&error];
        expect(untitledCopy != nil && [untitledCopy->text isEqualToString:@"unsaved"], [NSString stringWithFormat:@"an untitled document is duplicated (%@)", error]);
        expect([[untitledCopy displayName] isEqualToString:[[untitled displayName] stringByAppendingString:@" copy"]], @"the copy of an untitled document is named from its name");

        // The type a document picks for its copies is used.
        source->richCopies = YES;
        TextDocument *picked = (TextDocument *)[source duplicateAndReturnError:&error];
        expect(picked != nil && [[picked fileType] isEqualToString:@"public.plain-text"], @"the autosaving type is the copy's type");

        // A document that cannot write gives no copy, an error, and adds nothing.
        source->failWrites = YES;
        documents = [[controller documents] count];
        error = nil;
        expect([source duplicateAndReturnError:&error] == nil, @"a failing write gives no copy");
        expect(error != nil && [error code] == NSFileWriteOutOfSpaceError, @"the write error is returned");
        expect([[controller documents] count] == documents, @"nothing is added by a failed duplicate");
        source->failWrites = NO;

        // -duplicateDocumentWithDelegate:didDuplicateSelector:contextInfo:, and the action
        DuplicateWatcher *watcher = [[DuplicateWatcher alloc] init];
        documents = [[controller documents] count];
        [source duplicateDocumentWithDelegate:watcher didDuplicateSelector:@selector(document:didDuplicate:contextInfo:) contextInfo:(void *)0x1234];
        expect(watcher->calls == 1 && watcher->seen == source && watcher->didDuplicate, @"the delegate hears about the duplicate");
        expect([[controller documents] count] == documents + 1, @"the delegate call follows a copy");
        [source duplicateDocument:nil];
        expect([[controller documents] count] == documents + 2, @"the action makes a copy");
        source->failWrites = YES;
        [source duplicateDocumentWithDelegate:watcher didDuplicateSelector:@selector(document:didDuplicate:contextInfo:) contextInfo:(void *)0x1234];
        expect(watcher->calls == 2 && !watcher->didDuplicate, @"a failed duplicate is reported as such");
        source->failWrites = NO;

        // Closing a copy removes it from the controller.
        [copy close];
        expect(![[controller documents] containsObject:copy], @"closing removes the copy");

        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        printf("PASS\n");
    }
    return 0;
}
