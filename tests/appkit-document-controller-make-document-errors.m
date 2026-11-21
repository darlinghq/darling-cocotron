// Link with candidate AppKit; no windows are needed.
// https://developer.apple.com/documentation/appkit/nsdocumentcontroller/makedocument(withcontentsof:oftype:)
// The default implementation finds the document class for the type, allocates it and sends it the
// error-reporting initialiser (init(contentsOf:ofType:)); when the document cannot be made it returns nil
// after setting the error.
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#include <stdlib.h>

@interface MakeController : NSDocumentController
- (void)setTypes:(NSArray *)types;
@end
@implementation MakeController
- (void)setTypes:(NSArray *)types {
    [_fileTypes release];
    _fileTypes = [types copy];
}
@end

static NSURL *lastURL;
static NSString *lastType;
static NSInteger errorInitCalls;

// Overrides only the error-reporting initialiser.
@interface ErrorInitDocument : NSDocument
@end
@implementation ErrorInitDocument
- (instancetype)initWithContentsOfURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
    errorInitCalls++;
    lastURL = [url retain];
    lastType = [type copy];
    return [super init];
}
@end

// Fails reading and says why.
@interface FailingDocument : NSDocument
@end
@implementation FailingDocument
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
    if (error != NULL)
        *error = [NSError errorWithDomain:@"FixtureDomain" code:42 userInfo:nil];
    return NO;
}
@end

// Fails reading and sets no error.
@interface SilentDocument : NSDocument
@end
@implementation SilentDocument
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
    return NO;
}
@end

// Overrides the legacy initialiser the error-reporting one defers to, and fails without an alert or an error.
@interface LegacyDocument : NSDocument
@end
@implementation LegacyDocument
- (instancetype)initWithContentsOfFile:(NSString *)path ofType:(NSString *)type {
    return nil;
}
@end

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        MakeController *controller = [MakeController new];
        [controller setTypes:@[
            @{@"CFBundleTypeName": @"Initialised", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"ErrorInitDocument"},
            @{@"CFBundleTypeName": @"Failing", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"FailingDocument"},
            @{@"CFBundleTypeName": @"Silent", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"SilentDocument"},
            @{@"CFBundleTypeName": @"Legacy", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"LegacyDocument"},
            @{@"CFBundleTypeName": @"Classless", @"CFBundleTypeRole": @"Viewer"},
        ]];
        NSURL *url = [NSURL fileURLWithPath:@"/nonexistent/document.fixture"];
        NSError *error = nil;

        // A class that overrides only the error-reporting initialiser is the one that gets called.
        NSDocument *document = [controller makeDocumentWithContentsOfURL:url ofType:@"Initialised" error:&error];
        expect(document != nil && errorInitCalls == 1, @"the error-reporting initialiser makes the document");
        expect([lastURL isEqual:url] && [lastType isEqual:@"Initialised"], @"the initialiser receives the URL and the type");
        expect(error == nil, @"success sets no error");

        // The document's own error comes back.
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"Failing" error:&error];
        expect(document == nil, @"a failing read makes no document");
        expect([[error domain] isEqual:@"FixtureDomain"] && [error code] == 42, @"the reader's error is returned");

        // nil is never returned without an error (GUESS: the code is not documented).
        error = nil;
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"Silent" error:&error];
        expect(document == nil && error != nil, @"a failing read that sets no error still reports one");
        // A class that overrides the legacy initialiser and returns nil on its own sets no error either.
        error = nil;
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"Legacy" error:&error];
        expect(document == nil && [[error domain] isEqual:NSCocoaErrorDomain] && [error code] == NSFileReadUnknownError,
               @"a failure of the legacy initialiser reports the generic error");
        error = nil;
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"Classless" error:&error];
        expect(document == nil && error != nil, @"a type with no document class reports an error");
        error = nil;
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"Unknown" error:&error];
        expect(document == nil && error != nil, @"an undeclared type reports an error");

        // A NULL error pointer is allowed.
        expect([controller makeDocumentWithContentsOfURL:url ofType:@"Failing" error:NULL] == nil, @"NULL error pointer");
        NSLog(@"PASS: makeDocumentWithContentsOfURL:ofType:error: reports errors");
    }
    return 0;
}
