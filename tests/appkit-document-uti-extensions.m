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
        expect([[controller typeFromFileExtension:@"txt"] isEqual:@"public.plain-text"], @"UTI-only txt is named by its UTI");
        expect([[controller typeFromFileExtension:@"TEXT"] isEqual:@"public.plain-text"], @"case and alias");
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
        expect([[controller typeForContentsOfURL:(NSURL *)url error:&reported] isEqual:@"public.rtf"], @"resource UTI wins over extension");
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
        // An entry declaring several UTIs is named by the one that matched, not by its first.
        NSDictionary *image = @{@"CFBundleTypeName": @"Image document", @"LSItemContentTypes": @[@"public.jpeg", @"public.png"]};
        [controller setTypes:@[image]];
        expect([[controller typeFromFileExtension:@"png"] isEqual:@"public.png"], @"registry match names the entry's second UTI");
        BOOL savedSuccess = resourceSuccess; NSString *savedType = resourceType;
        resourceSuccess = YES; resourceType = @"public.png";
        expect([[controller typeForContentsOfURL:(NSURL *)url error:NULL] isEqual:@"public.png"], @"resource UTI names the entry's second UTI");
        resourceType = @"public.jpeg";
        expect([[controller typeForContentsOfURL:(NSURL *)url error:NULL] isEqual:@"public.jpeg"], @"resource UTI that is the first UTI still matches");
        resourceSuccess = savedSuccess; resourceType = savedType;
        [controller setTypes:@[plain]];
        NSString *fallback = [controller typeForContentsOfURL:(NSURL *)url error:&reported];
        expect([fallback isEqual:@"public.plain-text"], @"URL lookup reaches UTI-only extension declaration");
        expect(reported == nil, @"no stale error after metadata fallback");
        [url release];
        [controller release];
        NSLog(@"PASS: document extension lookup");
    }
    return 0;
}
