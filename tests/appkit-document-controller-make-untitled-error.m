// Link with candidate AppKit; no windows are needed.
// https://developer.apple.com/documentation/appkit/nsdocumentcontroller/makeuntitleddocument(oftype:)
// When the document cannot be made, the method returns nil after setting the error; a type with no
// document class (or no type at all) is such a case.
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#include <stdlib.h>

@interface NSDocumentController (Untitled)
- (id)makeUntitledDocumentOfType:(NSString *)type error:(NSError **)error;
- (id)makeUntitledDocumentOfType:(NSString *)type;
@end

// The ivar and @synthesize are explicit: the i386 slice uses the legacy runtime, which does not synthesize properties.
@interface UntitledController : NSDocumentController {
    NSInteger _presented;
}
@property(assign) NSInteger presented;
- (void)setTypes:(NSArray *)types;
@end
@implementation UntitledController
@synthesize presented = _presented;
- (void)setTypes:(NSArray *)types {
    [_fileTypes release];
    _fileTypes = [types copy];
}
- (BOOL)presentError:(NSError *)error {
    self.presented++;
    NSAssert(error != nil, @"a nil error is presented");
    return NO;
}
@end

@interface KnownDocument : NSDocument
@end
@implementation KnownDocument
@end

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        UntitledController *controller = [UntitledController new];
        [controller setTypes:@[
            @{@"CFBundleTypeName": @"Known", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"KnownDocument"},
            @{@"CFBundleTypeName": @"Classless", @"CFBundleTypeRole": @"Viewer"},
        ]];
        NSError *error = nil;

        expect([controller makeUntitledDocumentOfType:@"Known" error:&error] != nil && error == nil, @"a type with a class makes a document");

        expect([controller makeUntitledDocumentOfType:@"Classless" error:&error] == nil && error != nil, @"a type with no class reports an error");
        error = nil;
        expect([controller makeUntitledDocumentOfType:nil error:&error] == nil && error != nil, @"no type reports an error");

        // With no error pointer the controller presents it, and never presents a nil one.
        expect([controller makeUntitledDocumentOfType:@"Classless" error:NULL] == nil, @"NULL error pointer");
        expect(controller.presented == 1, @"the error was presented once");
        expect([controller makeUntitledDocumentOfType:@"Classless"] == nil && controller.presented == 2, @"the legacy method presents one too");
        NSLog(@"PASS: makeUntitledDocumentOfType:error: reports an error");
    }
    return 0;
}
