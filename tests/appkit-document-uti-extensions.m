// Link with candidate AppKit and UniformTypeIdentifiers; no windows are needed.
#import <AppKit/NSDocumentController.h>
#import <UniformTypeIdentifiers/UTType.h>
#include <stdlib.h>

@interface ExtensionController : NSDocumentController
- (void)setTypes:(NSArray *)types;
@end
@implementation ExtensionController
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
        expect([[UTType typeWithFilenameExtension:@"txt"].identifier isEqual:@"public.plain-text"],
               @"built-in plain-text registry is loaded");
        ExtensionController *controller = [ExtensionController new];
        NSDictionary *plain = @{@"CFBundleTypeName": @"Plain document",
            @"LSItemContentTypes": @[@"public.plain-text"]};
        [controller setTypes:@[plain]];
        expect([[controller typeFromFileExtension:@"txt"] isEqual:@"Plain document"], @"UTI-only txt");
        expect([[controller typeFromFileExtension:@"TEXT"] isEqual:@"Plain document"], @"case and alias");
        expect([controller typeFromFileExtension:@"png"] == nil, @"known but undeclared type");
        expect([controller typeFromFileExtension:@"darling-unregistered-extension-123"] == nil,
               @"dynamic UTI is not automatically a supported document type");
        expect([controller typeFromFileExtension:nil] == nil, @"nil without wildcard");
        expect([controller typeFromFileExtension:@""] == nil, @"empty without wildcard");
        NSDictionary *explicit = @{@"CFBundleTypeName": @"Explicit document",
            @"CFBundleTypeExtensions": @[@"TXT"]};
        [controller setTypes:@[plain, explicit]];
        expect([[controller typeFromFileExtension:@"txt"] isEqual:@"Explicit document"], @"explicit wins");
        NSDictionary *wildcard = @{@"CFBundleTypeName": @"Wildcard document",
            @"CFBundleTypeExtensions": @[@"*"]};
        [controller setTypes:@[plain, wildcard]];
        expect([[controller typeFromFileExtension:@"txt"] isEqual:@"Wildcard document"], @"legacy wildcard wins");
        expect([[controller typeFromFileExtension:nil] isEqual:@"Wildcard document"], @"legacy nil wildcard preserved");
        [controller release];
        NSLog(@"PASS: document extension lookup");
    }
    return 0;
}
