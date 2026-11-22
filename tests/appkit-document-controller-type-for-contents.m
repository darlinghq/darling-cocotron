// Link with candidate AppKit; no windows are needed.
// https://developer.apple.com/documentation/appkit/nsdocumentcontroller/typeforcontents(of:)
// A type is returned for a URL whose contents the application declares. The failure behaviour is pinned by
// black-box observation on macOS 26.7.3 and 10.14.4: a file or directory that exists always has a type
// (the application's declared type when the extension is declared, otherwise a type identifier, public.data
// at the least, public.folder for a directory), and only a missing file gives nil with an error,
// NSCocoaErrorDomain code 260 (NSFileReadNoSuchFileError).
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
        NSURL *bare = makeFile(@"type-for-contents-noext");
        NSURL *missing = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"type-for-contents-missing.dcfixture"]];
        NSURL *folder = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
        NSError *error = nil;

        NSString *type = [controller typeForContentsOfURL:known error:&error];
        expect([type isEqual:@"Fixture"] && error == nil, @"a declared extension gives its type and no error");

        // An existing file with an extension the application does not declare still has a type, and no error.
        error = nil;
        type = [controller typeForContentsOfURL:unknown error:&error];
        expect([type length] > 0 && error == nil, @"an undeclared file has a type and no error");

        error = nil;
        type = [controller typeForContentsOfURL:bare error:&error];
        expect([type length] > 0 && error == nil, @"a file without an extension has a type and no error");

        error = nil;
        type = [controller typeForContentsOfURL:folder error:&error];
        expect([type isEqual:@"public.folder"] && error == nil, @"a directory is public.folder");

        // A missing file gives no type and NSFileReadNoSuchFileError (260), whether or not its extension is declared.
        error = nil;
        type = [controller typeForContentsOfURL:missing error:&error];
        expect(type == nil && error != nil, @"a missing file has no type and an error");
        expect([[error domain] isEqual:NSCocoaErrorDomain] && [error code] == NSFileReadNoSuchFileError,
               @"the error is NSCocoaErrorDomain 260");

        // A stale error from an earlier call is replaced on success.
        error = [NSError errorWithDomain:@"Stale" code:1 userInfo:nil];
        type = [controller typeForContentsOfURL:known error:&error];
        expect(type != nil && error == nil, @"a success clears the error");

        // A URL that is not a file URL has no type (the error code is not observed, only that one is set).
        error = nil;
        type = [controller typeForContentsOfURL:[NSURL URLWithString:@"https://example.invalid/a.dcfixture"] error:&error];
        expect(type == nil && error != nil, @"a non-file URL reports an error");

        // NULL error pointer.
        expect([controller typeForContentsOfURL:missing error:NULL] == nil, @"NULL error pointer");
        expect([controller typeForContentsOfURL:unknown error:NULL] != nil, @"NULL error pointer, existing file");

        [[NSFileManager defaultManager] removeItemAtURL:known error:NULL];
        [[NSFileManager defaultManager] removeItemAtURL:unknown error:NULL];
        [[NSFileManager defaultManager] removeItemAtURL:bare error:NULL];
        NSLog(@"PASS: typeForContentsOfURL:error: types existing items and reports a missing file");
    }
    return 0;
}
