// Copyright (C) 2026 Lubos Dolezel
//
// NSSavePanel's allowedFileTypes may name filename extensions or uniform type
// identifiers. A name typed without an allowed extension gets the extension of
// the first allowed type, which for a type identifier is its preferred filename
// extension ("public.plain-text" gives "txt"), not the identifier itself. An
// extension whose type conforms to an allowed type identifier is kept.
// The panel is run modally and confirmed with -ok:. Needs a display. No ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;

static void expectSaved(NSString *directory, NSArray *types, BOOL allowsOther, NSString *typed, NSString *expected) {
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setDirectoryURL: [NSURL fileURLWithPath: directory]];
    [panel setAllowedFileTypes: types];
    [panel setAllowsOtherFileTypes: allowsOther];
    [panel setNameFieldStringValue: typed];
    [panel performSelector: @selector(ok:) withObject: nil afterDelay: 0.5
                   inModes: @[NSModalPanelRunLoopMode, NSDefaultRunLoopMode]];
    NSInteger result = [panel runModal];
    NSString *name = [[panel URL] lastPathComponent];
    BOOL ok = result == NSModalResponseOK && [name isEqualToString: expected];
    printf("%s \"%s\" with %s%s: saved as \"%s\", expected \"%s\"\n", ok ? "PASS" : "FAIL", [typed UTF8String],
           [[types componentsJoinedByString: @", "] UTF8String], allowsOther ? " (other types allowed)" : "",
           name ? [name UTF8String] : "(none)", [expected UTF8String]);
    failures += !ok;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        char temp[] = "/tmp/darling-save-panel-XXXXXX";
        if (!mkdtemp(temp))
            return 2;
        NSString *directory = [NSString stringWithUTF8String: temp];

        expectSaved(directory, @[@"public.plain-text"], NO, @"name", @"name.txt");
        expectSaved(directory, @[@"public.plain-text", @"md"], YES, @"notes", @"notes.txt");
        expectSaved(directory, @[@"public.html"], NO, @"page", @"page.html");
        expectSaved(directory, @[@"public.plain-text"], NO, @"readme.txt", @"readme.txt");
        expectSaved(directory, @[@"public.plain-text"], NO, @"readme.text", @"readme.text");
        expectSaved(directory, @[@"public.plain-text", @"md"], NO, @"doc.md", @"doc.md");
        expectSaved(directory, @[@"public.plain-text"], NO, @"image.png", @"image.png.txt");
        expectSaved(directory, @[@"rtf"], NO, @"letter", @"letter.rtf");

        [[NSFileManager defaultManager] removeItemAtPath: directory error: NULL];
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
