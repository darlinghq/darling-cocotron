// Copyright (C) 2026 Lubos Dolezel
//
// CTFontManagerRegisterFontsForURL and ATSApplicationFontsPath.
// Usage: coretext-font-manager-register-url FIXTURE_DIRECTORY SCRATCH_DIRECTORY
// FIXTURE_DIRECTORY holds DarlingVerticalTest.ttf (generate-vertical-font.py), a font no system
// has installed. Error codes: black-box observation on macOS 26.7.3.
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL fontResolves(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("DarlingVerticalTest-Regular"), 20, NULL);
    CFStringRef name = CTFontCopyPostScriptName(font);
    BOOL found = name != NULL && CFEqual(name, CFSTR("DarlingVerticalTest-Regular"));
    if (name != NULL) CFRelease(name);
    CFRelease(font);
    return found;
}

static bool registerPath(NSString *path, CFErrorRef *error) {
    return CTFontManagerRegisterFontsForURL((CFURLRef) [NSURL fileURLWithPath: path],
                                            kCTFontManagerScopeProcess, error);
}

static void expectError(CFErrorRef error, CFIndex code, const char *what) {
    expect(error != NULL, what);
    if (error == NULL) return;
    expect(CFEqual(CFErrorGetDomain(error), kCTFontManagerErrorDomain), what);
    expect(CFErrorGetCode(error) == code, what);
    NSDictionary *info = (NSDictionary *) CFErrorCopyUserInfo(error);
    expect([[info objectForKey: (NSString *) kCTFontManagerErrorFontURLsKey] count] == 1, what);
    [info release];
    CFRelease(error);
}

// The test re-runs itself inside a bundle whose Info.plist names the font in ATSApplicationFontsPath.
static int bundleCase(NSString *fixture, NSString *scratch, const char *self) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *app = [scratch stringByAppendingPathComponent: @"Fonts.app"];
    NSString *macos = [app stringByAppendingPathComponent: @"Contents/MacOS"];
    NSString *resources = [app stringByAppendingPathComponent: @"Contents/Resources/AppFonts"];
    [fm createDirectoryAtPath: macos withIntermediateDirectories: YES attributes: nil error: NULL];
    [fm createDirectoryAtPath: resources withIntermediateDirectories: YES attributes: nil error: NULL];
    NSString *exe = [macos stringByAppendingPathComponent: @"probe"];
    [fm removeItemAtPath: exe error: NULL];
    expect([fm copyItemAtPath: [NSString stringWithUTF8String: self] toPath: exe error: NULL], "copy executable");
    [fm removeItemAtPath: [resources stringByAppendingPathComponent: @"DarlingVerticalTest.ttf"] error: NULL];
    expect([fm copyItemAtPath: [fixture stringByAppendingPathComponent: @"DarlingVerticalTest.ttf"]
                       toPath: [resources stringByAppendingPathComponent: @"DarlingVerticalTest.ttf"]
                        error: NULL], "copy font");
    NSDictionary *info = @{ @"CFBundleExecutable": @"probe", @"CFBundleIdentifier": @"test.fonts",
                            @"CFBundlePackageType": @"APPL",
                            @"ATSApplicationFontsPath": @"AppFonts" };
    expect([info writeToFile: [app stringByAppendingPathComponent: @"Contents/Info.plist"] atomically: NO],
           "write Info.plist");
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath: exe];
    [task setArguments: @[ @"bundle-child" ]];
    [task launch];
    [task waitUntilExit];
    expect([task terminationStatus] == 0, "a font in ATSApplicationFontsPath is registered at launch");
    [task release];
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "bundle-child") == 0)
            return fontResolves() ? 0 : 1;
        if (argc != 3) return 2;
        NSString *fixture = [NSString stringWithUTF8String: argv[1]];
        NSString *scratch = [NSString stringWithUTF8String: argv[2]];
        NSString *font = [fixture stringByAppendingPathComponent: @"DarlingVerticalTest.ttf"];
        NSString *junk = [scratch stringByAppendingPathComponent: @"junk.ttf"];
        [@"not a font" writeToFile: junk atomically: NO encoding: NSUTF8StringEncoding error: NULL];

        expect(!fontResolves(), "the fixture font is not installed");

        CFErrorRef error = NULL;
        expect(!registerPath([scratch stringByAppendingPathComponent: @"missing.ttf"], &error), "missing file fails");
        expectError(error, kCTFontManagerErrorFileNotFound, "missing file: file-not-found");
        error = NULL;
        expect(!registerPath(junk, &error), "a file that is not a font fails");
        expectError(error, kCTFontManagerErrorUnrecognizedFormat, "junk: unrecognized-format");
        expect(!fontResolves(), "failed registrations register nothing");

        error = NULL;
        expect(registerPath(font, &error), "a font file registers");
        expect(error == NULL, "success leaves the error NULL");
        expect(fontResolves(), "the registered font is found by its PostScript name");

        error = NULL;
        expect(!registerPath(font, &error), "registering twice fails");
        expectError(error, kCTFontManagerErrorAlreadyRegistered, "twice: already-registered");

        expect(!CTFontManagerRegisterFontsForURL((CFURLRef) [NSURL URLWithString: @"http://example.invalid/a.ttf"],
                                                 kCTFontManagerScopeProcess, NULL), "NULL error is allowed");
        bundleCase(fixture, scratch, argv[0]);
    }
    if (failures == 0) puts("PASS");
    return failures ? 1 : 0;
}
