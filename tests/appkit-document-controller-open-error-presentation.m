// Link with candidate AppKit; no windows are needed.
// https://developer.apple.com/documentation/appkit/nsdocumentcontroller/makedocument(withcontentsof:oftype:)
// A document that cannot be made reports its error (see appkit-document-controller-make-document-errors.m).
// The controller's entry points that open a file for the user tell the user, and not for an error
// that says the user cancelled. GUESS: the documentation does not say who presents the error.
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#include <stdlib.h>

@interface NSDocumentController (OpenFile)
- (BOOL)application:(id)sender openFile:(NSString *)path;
@end

// The ivar and @synthesize are explicit: the i386 slice uses the legacy runtime, which does not synthesize properties.
@interface OpenController : NSDocumentController {
    NSInteger _presented;
}
@property(assign) NSInteger presented;
- (void)setTypes:(NSArray *)types;
@end
@implementation OpenController
@synthesize presented = _presented;
- (void)setTypes:(NSArray *)types {
    [_fileTypes release];
    _fileTypes = [types copy];
}
// The file name is the type, so no file or type lookup is involved.
- (NSString *)typeForContentsOfURL:(NSURL *)url error:(NSError **)error {
    return [url lastPathComponent];
}
- (BOOL)presentError:(NSError *)error {
    self.presented++;
    return NO;
}
@end

@interface SilentDocument : NSDocument
@end
@implementation SilentDocument
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error { return NO; }
@end

@interface CancelledDocument : NSDocument
@end
@implementation CancelledDocument
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
    if (error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
    return NO;
}
@end

@interface LegacyDocument : NSDocument
@end
@implementation LegacyDocument
- (instancetype)initWithContentsOfFile:(NSString *)path ofType:(NSString *)type { return nil; }
@end

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        OpenController *controller = [OpenController new];
        [controller setTypes:@[
            @{@"CFBundleTypeName": @"Silent", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"SilentDocument"},
            @{@"CFBundleTypeName": @"Cancelled", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"CancelledDocument"},
            @{@"CFBundleTypeName": @"Legacy", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"LegacyDocument"},
        ]];
        NSError *error = nil;

        // -application:openFile: (launch and Finder opens) tells the user once about a failure.
        expect(![controller application:nil openFile:@"/nonexistent/Silent"], @"a failing read does not open");
        expect(controller.presented == 1, @"the generic error is presented once");

        // Not for a user-cancelled error.
        expect(![controller application:nil openFile:@"/nonexistent/Cancelled"], @"a cancelled read does not open");
        expect(controller.presented == 1, @"a cancelled error is not presented");

        // A class that overrides the legacy initialiser and fails silently is told to the user too. (One
        // that calls super and fails on the read has already shown NSDocument's own alert, and gets this
        // one as well: a known double alert, see the PR's open questions.)
        expect(![controller application:nil openFile:@"/nonexistent/Legacy"], @"a failing legacy initialiser does not open");
        expect(controller.presented == 2, @"its generic error is presented");

        // The error is still returned to a caller that asks for it.
        expect([controller openDocumentWithContentsOfURL:[NSURL fileURLWithPath:@"/nonexistent/Silent"] display:NO error:&error] == nil,
               @"the caller gets no document");
        expect(controller.presented == 2, @"the programmatic entry point presents nothing");
        NSLog(@"PASS: open failures are presented, cancelled ones are not");
    }
    return 0;
}
