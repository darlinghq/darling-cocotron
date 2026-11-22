// Link with candidate AppKit; no windows are needed.
// https://developer.apple.com/documentation/appkit/nsdocumentcontroller/defaulttype
// The default type is the first Editor type declared by CFBundleDocumentTypes, or nil when none is.
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#include <stdlib.h>

@interface DefaultController : NSDocumentController
- (void)setTypes:(NSArray *)types;
@end
@implementation DefaultController
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
        DefaultController *controller = [DefaultController new];
        NSDictionary *viewer = @{@"CFBundleTypeName": @"Viewed", @"CFBundleTypeRole": @"Viewer"};
        NSDictionary *unnamedRole = @{@"CFBundleTypeName": @"NoRole"};
        NSDictionary *editor = @{@"CFBundleTypeName": @"Edited", @"CFBundleTypeRole": @"Editor"};
        NSDictionary *editorUTI = @{@"CFBundleTypeName": @"Legacy", @"CFBundleTypeRole": @"Editor", @"LSItemContentTypes": @[@"public.rtf"]};
        NSDictionary *secondEditor = @{@"CFBundleTypeName": @"Second", @"CFBundleTypeRole": @"Editor"};

        [controller setTypes:@[viewer, unnamedRole, editor, secondEditor]];
        expect([[controller defaultType] isEqual:@"Edited"], @"the first Editor type, not the first type");

        [controller setTypes:@[secondEditor, editor]];
        expect([[controller defaultType] isEqual:@"Second"], @"the first Editor type in declaration order");

        [controller setTypes:@[viewer, editorUTI]];
        expect([[controller defaultType] isEqual:@"public.rtf"], @"the Editor type is named as every other type is");

        // GUESS: an Editor entry with no name is passed over for the next Editor entry.
        NSDictionary *nameless = @{@"CFBundleTypeRole": @"Editor"};
        [controller setTypes:@[nameless, secondEditor]];
        expect([[controller defaultType] isEqual:@"Second"], @"an Editor entry with no name is skipped");

        [controller setTypes:@[viewer, unnamedRole]];
        expect([controller defaultType] == nil, @"no Editor type: nil");

        [controller setTypes:@[]];
        expect([controller defaultType] == nil, @"no types: nil");
        NSLog(@"PASS: defaultType is the first Editor type");
    }
    return 0;
}
