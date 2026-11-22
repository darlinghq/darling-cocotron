// Link with candidate AppKit; no windows are needed.
// https://developer.apple.com/documentation/appkit/nsdocumentcontroller/documentclassnames
// The names are those of the document classes the application's property list declares; a document type
// that declares no class contributes no name.
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#include <stdlib.h>

@interface NamesController : NSDocumentController
- (void)setTypes:(NSArray *)types;
@end
@implementation NamesController
- (void)setTypes:(NSArray *)types {
    [_fileTypes release];
    _fileTypes = [types copy];
}
@end

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        NamesController *controller = [NamesController new];
        NSDictionary *first = @{@"CFBundleTypeName": @"First", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"FirstDocument"};
        NSDictionary *second = @{@"CFBundleTypeName": @"Second", @"CFBundleTypeRole": @"Editor", @"NSDocumentClass": @"SecondDocument"};
        NSDictionary *again = @{@"CFBundleTypeName": @"Again", @"CFBundleTypeRole": @"Viewer", @"NSDocumentClass": @"FirstDocument"};
        NSDictionary *undeclared = @{@"CFBundleTypeName": @"Plain", @"CFBundleTypeRole": @"Viewer"};

        [controller setTypes:@[first, undeclared, second, again]];
        NSArray *names = nil;
        @try {
            names = [controller documentClassNames];
        } @catch (NSException *exception) {
            expect(NO, [NSString stringWithFormat:@"a type without a document class raised %@", exception.name]);
        }
        expect([names count] == 2, @"one name per distinct class, none for the undeclared entry");
        expect([names containsObject:@"FirstDocument"] && [names containsObject:@"SecondDocument"], @"the declared names are listed");

        [controller setTypes:@[undeclared]];
        expect([[controller documentClassNames] count] == 0, @"only undeclared types: no names");

        [controller setTypes:@[]];
        expect([[controller documentClassNames] count] == 0, @"no types: no names");
        NSLog(@"PASS: documentClassNames skips undeclared types");
    }
    return 0;
}
