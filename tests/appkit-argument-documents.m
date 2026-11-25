// Copyright (C) 2026 Lubos Dolezel
//
// What a launch does with the words of its process arguments that are not switches. Observed on macOS 26.7.3 with a
// document-based application started from its executable (QUIRK: undocumented; this test pins it):
//  - each word is offered to the application delegate, one call per word: -application:openFiles: with a
//    one-element array when the delegate implements it, otherwise -application:openFile:;
//  - with -application:openFiles: nothing else happens; otherwise the document controller then tries to open the
//    word as a document, and when it cannot (a word that is no file, such as a mode or a number) it presents an
//    error (NSCocoaErrorDomain 256), also after -application:openFile: answered NO;
//  - a switch and its value (-mode runtime) are not documents.
// So a program that takes a mode or a number on its command line gives its application a delegate with
// -application:openFiles:, or takes the value after a switch.
// Usage: appkit-argument-documents -delegate none|openFile|openFiles [word ...]; prints PASS or FAIL. The alert is
// counted by replacing -[NSDocumentController presentError:], so no window is needed. Build without ARC.
// The program stands for a document-based application, so run it from an application bundle whose Info.plist
// has a CFBundleDocumentTypes entry (e.g. a public.plain-text type with NSDocumentClass NSDocument): an
// application without document types never reaches the document controller (see
// appkit-argument-documents-non-document-apps).
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>

static int presented, openFileCalls, openFilesCalls;

static BOOL countPresent(id self, SEL _cmd, NSError *error) {
    presented++;
    return YES;
}

@interface FileDelegate : NSObject <NSApplicationDelegate>
@end
@implementation FileDelegate
- (BOOL) application: (NSApplication *) application openFile: (NSString *) file {
    openFileCalls++;
    return NO;
}
@end

@interface FilesDelegate : NSObject <NSApplicationDelegate>
@end
@implementation FilesDelegate
- (void) application: (NSApplication *) application openFiles: (NSArray *) files {
    openFilesCalls++;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey: @"delegate"];
        int words = 0;
        for (int i = 1; i < argc; i++) {
            if (argv[i][0] == '-')
                i++; // a switch takes the next argument as its value
            else
                words++;
        }
        if (mode == nil) {
            printf("FAIL: usage: appkit-argument-documents -delegate none|openFile|openFiles [word ...]\n");
            return 2;
        }
        if ([mode isEqualToString: @"openFile"])
            [NSApp setDelegate: [[FileDelegate alloc] init]];
        else if ([mode isEqualToString: @"openFiles"])
            [NSApp setDelegate: [[FilesDelegate alloc] init]];
        class_replaceMethod([NSDocumentController class], @selector(presentError:), (IMP) countPresent, "c@:@");
        [NSApp finishLaunching];
        // macOS opens the documents asynchronously: let the run loop deliver the errors.
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];

        int wantPresented = [mode isEqualToString: @"openFiles"] ? 0 : words;
        int wantOpenFile = [mode isEqualToString: @"openFile"] ? words : 0;
        int wantOpenFiles = [mode isEqualToString: @"openFiles"] ? words : 0;
        BOOL ok = presented == wantPresented && openFileCalls == wantOpenFile && openFilesCalls == wantOpenFiles;
        printf("%s delegate %s, %d word(s): %d error(s) presented (want %d), %d openFile (want %d), %d openFiles (want %d)\n",
               ok ? "PASS" : "FAIL", [mode UTF8String], words, presented, wantPresented, openFileCalls, wantOpenFile,
               openFilesCalls, wantOpenFiles);
        return ok ? 0 : 1;
    }
}
