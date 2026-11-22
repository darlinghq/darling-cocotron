// Link with candidate AppKit; no windows are needed.
// https://developer.apple.com/documentation/appkit/nsdocumentcontroller/typeforcontents(of:)
// A type is returned for a URL whose contents the application declares; otherwise the method returns nil
// after setting an error that says the type is unrecognised.
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#include <stdlib.h>

@interface ContentsController : NSDocumentController
- (void)setTypes:(NSArray *)types;
@end
@implementation ContentsController
- (void)setTypes:(NSArray *)types {
    [_fileTypes release];
    _fileTypes = [types copy];
}
@end

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

static NSURL *makeFile(NSString *name) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSData data] writeToFile:path atomically:NO];
    return [NSURL fileURLWithPath:path];
}

int main(void) {
    @autoreleasepool {
        ContentsController *controller = [ContentsController new];
        [controller setTypes:@[@{@"CFBundleTypeName": @"Fixture", @"CFBundleTypeRole": @"Editor",
                                 @"CFBundleTypeExtensions": @[@"dcfixture"], @"NSDocumentClass": @"NSDocument"}]];
        NSURL *known = makeFile(@"type-for-contents.dcfixture");
        NSURL *unknown = makeFile(@"type-for-contents.dcunlisted");
        NSError *error = nil;

        NSString *type = [controller typeForContentsOfURL:known error:&error];
        expect([type isEqual:@"Fixture"] && error == nil, @"a declared extension gives its type and no error");

        error = nil;
        type = [controller typeForContentsOfURL:unknown error:&error];
        expect(type == nil, @"an unrecognised file has no type");
        expect(error != nil, @"an unrecognised file reports an error");
        expect([[error domain] isEqual:NSCocoaErrorDomain], @"the error is in the Cocoa domain");

        // A stale error from an earlier call is replaced on success.
        error = [NSError errorWithDomain:@"Stale" code:1 userInfo:nil];
        type = [controller typeForContentsOfURL:known error:&error];
        expect(type != nil && error == nil, @"a success clears the error");

        // A URL that is not a file is not recognised either.
        error = nil;
        type = [controller typeForContentsOfURL:[NSURL URLWithString:@"https://example.invalid/a.dcfixture"] error:&error];
        expect(type == nil && error != nil, @"a non-file URL reports an error");

        // NULL error pointer.
        expect([controller typeForContentsOfURL:unknown error:NULL] == nil, @"NULL error pointer");

        [[NSFileManager defaultManager] removeItemAtURL:known error:NULL];
        [[NSFileManager defaultManager] removeItemAtURL:unknown error:NULL];
        NSLog(@"PASS: typeForContentsOfURL:error: reports an unrecognised type");
    }
    return 0;
}
