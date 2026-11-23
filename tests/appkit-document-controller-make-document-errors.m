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
            @{@"CFBundleTypeName": @"MissingClass", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"ClassThatDoesNotExist"},
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

        // A class that returns nil without an error leaves the error nil: pinned by black-box observation on
        // macOS 26.7.3 and 10.14.4 (the open entry points that take a completion handler add a generic error).
        error = nil;
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"Silent" error:&error];
        expect(document == nil && error == nil, @"a failing read that sets no error leaves it unset");
        error = nil;
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"Legacy" error:&error];
        expect(document == nil && error == nil, @"a failure of the legacy initialiser leaves the error unset");
        error = nil;
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"Classless" error:&error];
        expect(document == nil, @"a type with no document class makes no document");
        error = nil;
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"Unknown" error:&error];
        expect(document == nil, @"an undeclared type makes no document");

        // QUIRK (macOS 26.7.3, 10.14.4 and 26.1, probe 669.make "NoClass"): a type whose NSDocumentClass names a class that does not
        // exist gives nil and NSCocoaErrorDomain code 256 (NSFileReadUnknownError), from both make methods.
        error = nil;
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"MissingClass" error:&error];
        expect(document == nil, @"a missing document class makes no document");
        expect([[error domain] isEqual:NSCocoaErrorDomain] && [error code] == NSFileReadUnknownError,
               @"a missing document class sets the generic read error");
        error = nil;
        document = [controller makeDocumentForURL:nil withContentsOfURL:url ofType:@"MissingClass" error:&error];
        expect(document == nil, @"a missing document class makes no document for a URL either");
        expect([[error domain] isEqual:NSCocoaErrorDomain] && [error code] == NSFileReadUnknownError,
               @"makeDocumentForURL sets the generic read error too");
        expect([controller makeDocumentWithContentsOfURL:url ofType:@"MissingClass" error:NULL] == nil, @"NULL error pointer, missing class");

        // The same for a type with no NSDocumentClass entry and for an undeclared type (the documentation's rule:
        // an error comes with every nil; only the missing-class case above was observed)
        error = nil;
        document = [controller makeDocumentWithContentsOfURL:url ofType:@"Classless" error:&error];
        expect(document == nil && [error code] == NSFileReadUnknownError, @"no NSDocumentClass entry sets the generic read error");
        error = nil;
        document = [controller makeDocumentForURL:nil withContentsOfURL:url ofType:@"Unknown" error:&error];
        expect(document == nil && [error code] == NSFileReadUnknownError, @"an undeclared type sets the generic read error");

        // A NULL error pointer is allowed.
        expect([controller makeDocumentWithContentsOfURL:url ofType:@"Failing" error:NULL] == nil, @"NULL error pointer");
        NSLog(@"PASS: makeDocumentWithContentsOfURL:ofType:error: reports errors");
    }
    return 0;
}
