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

// A controlled URL interface, not actual filesystem/resource-provider behavior.
static BOOL resourceSuccess, fileURL = YES;
static NSString *resourceType;
static NSError *resourceError;
@interface ResourceURL : NSObject
- (BOOL)isFileURL;
- (NSString *)path;
- (BOOL)getResourceValue:(id *)value forKey:(NSString *)key error:(NSError **)error;
@end
@implementation ResourceURL
- (BOOL)isFileURL { return fileURL; }
- (NSString *)path { return @"/fixture/test.txt"; }
- (BOOL)getResourceValue:(id *)value forKey:(NSString *)key error:(NSError **)error {
    *value = resourceType;
    if (error) *error = resourceError;
    return resourceSuccess;
}
@end

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
        ResourceURL *url = [ResourceURL new];
        NSDictionary *rich = @{@"CFBundleTypeName": @"Rich document", @"LSItemContentTypes": @[@"public.rtf"]};
        [controller setTypes:@[plain, rich, explicit]];
        NSError *reported = nil;
        resourceSuccess = YES; resourceType = @"public.rtf";
        expect([[controller typeForContentsOfURL:(NSURL *)url error:&reported] isEqual:@"Rich document"], @"resource UTI wins over extension");
        resourceType = @"public.unknown";
        expect([[controller typeForContentsOfURL:(NSURL *)url error:NULL] isEqual:@"Explicit document"], @"unmatched resource UTI fallback");
        resourceType = nil;
        expect([[controller typeForContentsOfURL:(NSURL *)url error:NULL] isEqual:@"Explicit document"], @"successful empty metadata fallback");
        resourceSuccess = NO;
        expect([[controller typeForContentsOfURL:(NSURL *)url error:NULL] isEqual:@"Explicit document"], @"missing metadata without error fallback");
        resourceError = [NSError errorWithDomain:@"FixtureProvider" code:1 userInfo:nil];
        expect([controller typeForContentsOfURL:(NSURL *)url error:&reported] == nil && reported == resourceError,
               @"explicit provider error is preserved");
        expect([controller typeForContentsOfURL:(NSURL *)url error:NULL] == nil, @"error not suppressed with null output");
        resourceError = nil;
        fileURL = NO;
        expect([controller typeForContentsOfURL:(NSURL *)url error:NULL] == nil, @"non-file URLs stay unsupported");
        fileURL = YES;
        [controller setTypes:@[plain]];
        NSString *fallback = [controller typeForContentsOfURL:(NSURL *)url error:&reported];
#ifdef PROBE_WITHOUT_PROVIDER
        expect(fallback == nil, @"no UTI fallback without provider");
#else
        expect([fallback isEqual:@"Plain document"], @"URL lookup reaches UTI-only extension declaration");
#endif
        expect(reported == nil, @"no stale error after metadata fallback");
        [url release];
        [controller release];
        NSLog(@"PASS: document extension lookup");
    }
    return 0;
}
