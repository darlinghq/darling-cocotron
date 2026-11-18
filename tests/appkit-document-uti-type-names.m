// Link with candidate AppKit; no windows are needed.
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#import <objc/runtime.h>
#include <stdlib.h>

@interface TypeController : NSDocumentController
- (void)setTypes:(NSArray *)types;
@end
@implementation TypeController
- (void)setTypes:(NSArray *)types {
    [_fileTypes release];
    _fileTypes = [types copy];
}
@end

static NSDictionary *fixtureInfo;
static id fakeInfoDictionary(id self, SEL _cmd) { return fixtureInfo; }

@interface TypeDocument : NSDocument
@end
@implementation TypeDocument
@end

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

// A CFBundleDocumentTypes entry that declares LSItemContentTypes is named by its uniform type identifier;
// an entry without them is named by its CFBundleTypeName (Document-Based App Programming Guide).
int main(void) {
    @autoreleasepool {
        TypeController *controller = [TypeController new];
        // A legacy name plus the UTI.
        NSDictionary *rtf = @{@"CFBundleTypeName": @"NSRTFPboardType", @"CFBundleTypeRole": @"Editor",
            @"LSItemContentTypes": @[@"public.rtf"], @"NSDocumentClass": @"TypeDocument"};
        NSDictionary *legacy = @{@"CFBundleTypeName": @"Legacy document", @"CFBundleTypeExtensions": @[@"leg"], @"CFBundleTypeRole": @"Editor",
            @"NSDocumentClass": @"TypeDocument"};
        // One entry declaring several UTIs: the type of an extension is the UTI that matched, not the first one.
        NSDictionary *markup = @{@"CFBundleTypeName": @"Markup", @"CFBundleTypeRole": @"Editor",
            @"LSItemContentTypes": @[@"public.html", @"public.xml"], @"NSDocumentClass": @"TypeDocument"};
        [controller setTypes:@[rtf, legacy, markup]];

        expect([[controller defaultType] isEqual:@"public.rtf"], @"the default type is the UTI");
        expect([[controller typeFromFileExtension:@"rtf"] isEqual:@"public.rtf"], @"rtf is named by its UTI");
        expect([[controller typeFromFileExtension:@"leg"] isEqual:@"Legacy document"], @"an entry without UTIs keeps its CFBundleTypeName");
        expect([[controller typeFromFileExtension:@"xml"] isEqual:@"public.xml"], @"the extension names the matched UTI, not the entry's first");
        expect([[controller typeFromFileExtension:@"html"] isEqual:@"public.html"], @"the first UTI still matches itself");
        expect([controller documentClassForType:@"public.xml"] == [TypeDocument class], @"every UTI of an entry finds the document class");
        expect([controller documentClassForType:@"public.rtf"] == [TypeDocument class], @"the UTI finds the document class");
        expect([controller documentClassForType:@"Legacy document"] == [TypeDocument class], @"the legacy name finds the document class");
        expect([controller documentClassForType:@"NSRTFPboardType"] == nil, @"the legacy name of a UTI entry is not a type name");
        expect([[controller displayNameForType:@"public.rtf"] isEqual:@"NSRTFPboardType"], @"the display name stays the CFBundleTypeName");
        expect([[[controller documentClassNames] sortedArrayUsingSelector:@selector(compare:)][0] isEqual:@"TypeDocument"], @"class names");

        // The class methods of NSDocument read the main bundle's declared types.
        fixtureInfo = @{@"CFBundleDocumentTypes": @[rtf, legacy, markup]};
        method_setImplementation(class_getInstanceMethod([NSBundle class], @selector(infoDictionary)), (IMP)fakeInfoDictionary);
        NSArray *readable = [TypeDocument readableTypes], *writable = [TypeDocument writableTypes];
        for (NSString *name in @[@"public.rtf", @"public.html", @"public.xml", @"Legacy document"]) {
            expect([readable containsObject:name], [NSString stringWithFormat:@"%@ is readable", name]);
            expect([writable containsObject:name], [NSString stringWithFormat:@"%@ is writable", name]);
        }
        expect(![writable containsObject:@"NSRTFPboardType"], @"the legacy name of a UTI entry is not listed");
        expect([TypeDocument isNativeType:@"public.xml"], @"every UTI of an entry is native");
        expect(![TypeDocument isNativeType:@"NSRTFPboardType"], @"the legacy name of a UTI entry is not native");
        expect(![TypeDocument isNativeType:@"public.pdf"], @"an undeclared type is not native");
        NSLog(@"PASS: document type names");
    }
    return 0;
}
