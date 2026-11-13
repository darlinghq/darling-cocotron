// Link with candidate AppKit; no windows are needed.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"urlforimage-%d.bundle", getpid()]];
        NSString *resources = [root stringByAppendingPathComponent:@"Contents/Resources"];
        expect([fm createDirectoryAtPath:resources withIntermediateDirectories:YES attributes:nil error:NULL],
               @"create the scratch bundle");
        expect([[NSData dataWithBytes:"x" length:1] writeToFile:[resources stringByAppendingPathComponent:@"probe.png"]
                                                      atomically:NO], @"write the resource");

        // Written before the bundle is opened: a bundle reads its resource directory once.
        expect([[NSData dataWithBytes:"x" length:1] writeToFile:[resources stringByAppendingPathComponent:@"com.example.icon.png"]
                                                      atomically:NO], @"write the dotted resource");

        NSBundle *bundle = [NSBundle bundleWithPath:root];
        expect(bundle != nil, @"open the scratch bundle");
        expect([bundle respondsToSelector:@selector(URLForImageResource:)], @"NSBundle answers -URLForImageResource:");

        // Darling's own Foundation carries a private -URLForImageResource: that Apple's Foundation lacks, so
        // answering the selector is not enough: AppKit, which declares the method, must be what implements it.
        Method method = class_getInstanceMethod([NSBundle class], @selector(URLForImageResource:));
        Dl_info info;
        expect(dladdr((const void *)method_getImplementation(method), &info) && info.dli_fname &&
                   strstr(info.dli_fname, "AppKit") != NULL,
               @"AppKit implements -URLForImageResource:");

        NSString *path = [bundle pathForImageResource:@"probe"];
        expect(path != nil, @"pathForImageResource: finds probe.png without an extension");

        NSURL *url = [bundle URLForImageResource:@"probe"];
        expect(url != nil && [url isFileURL], @"the URL for a bare name is a file URL");
        expect([[url path] isEqualToString:path], @"the URL names the file pathForImageResource: found");

        NSURL *withExtension = [bundle URLForImageResource:@"probe.png"];
        expect([[withExtension path] isEqualToString:path], @"a name with its extension finds the same file");

        // A dotted name whose last component is not an image type still finds name.png.
        NSURL *dotted = [bundle URLForImageResource:@"com.example.icon"];
        expect(dotted != nil && [[dotted lastPathComponent] isEqualToString:@"com.example.icon.png"],
               @"a dotted name finds the image of that name");
        expect([bundle URLForImageResource:@"absent"] == nil, @"an absent image gives nil");

        [fm removeItemAtPath:root error:NULL];
        NSLog(@"PASS: -URLForImageResource:");
    }
    return 0;
}
