// Copyright (C) 2026 Lubos Dolezel
//
// Documents named in the process arguments of an application that has no document types.
//
// Documented: the document controller (NSDocumentController) is the part of a document-based
// application that opens files; an application declares the documents it can open with
// CFBundleDocumentTypes in its Info.plist. Observed on macOS 26.7.3 (x86_64) and 10.14.4
// (x86_64 and i386), the same on both, for an application that is started with a word that is not
// a file, with a file that exists, or with no argument:
//   - an executable without a bundle, a bundled application without CFBundleDocumentTypes, and
//     such a bundle with a delegate that implements neither -application:openFile: nor
//     -application:openFiles: are alike: launching finishes without any use of the document
//     controller (nothing is opened or made, no error is presented, no alert or window appears),
//     whether the program calls -finishLaunching itself or -run does;
//   - an application with CFBundleDocumentTypes opens the argument as a document through the
//     document controller: an existing text file opens as an instance of the document class,
//     and a word that is not a file reaches the document controller too, also after the delegate's
//     -application:openFile: answered NO;
//   - a delegate whose -application:openFile: answers NO changes nothing for the applications
//     without document types: the document controller is still not used.
// The test starts itself once per case (and, for the bundled cases, from a copy of itself placed in
// a temporary application bundle), observes the document controller through the public methods
// it is asked to open and make documents with, and prints PASS when every child agrees. Needs a
// display connection.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <mach-o/dyld.h>

extern char **environ;

static int controllerCalls;  // document controller asked to open or make a document
static int errorsPresented;  // -presentError: of the application or the controller
static int alertsShown;      // alert or modal window run
static int documentsRead;    // ProbeDocument instances that read a file

@interface ProbeDocument : NSDocument
@end

@implementation ProbeDocument
- (BOOL) readFromData: (NSData *) data ofType: (NSString *) type error: (NSError **) error {
    documentsRead++;
    return YES;
}
- (void) makeWindowControllers {
}
@end

@interface RefusingDelegate : NSObject <NSApplicationDelegate>
@end

@implementation RefusingDelegate
- (BOOL) application: (NSApplication *) app openFile: (NSString *) path {
    return NO;
}
- (BOOL) applicationShouldOpenUntitledFile: (NSApplication *) app {
    return NO;
}
@end

@interface NoOpenDelegate : NSObject <NSApplicationDelegate>
@end

@implementation NoOpenDelegate
- (BOOL) applicationShouldOpenUntitledFile: (NSApplication *) app {
    return NO;
}
@end

// Hooks: counters on the public methods that open and make documents, present errors and run
// alerts. The ones that would block (errors, alerts, modal windows) are counted and not run.
static IMP originalOpenURL, originalOpenCompletion, originalMake;

static void replace(Class c, SEL sel, id block) {
    Method m = class_getInstanceMethod(c, sel);
    if (m != NULL)
        class_replaceMethod(c, sel, imp_implementationWithBlock(block), method_getTypeEncoding(m));
}

static void installHooks(void) {
    Class dc = [NSDocumentController class];
    Class app = [NSApplication class];
    Method m;

    if ((m = class_getInstanceMethod(dc, @selector(openDocumentWithContentsOfURL:display:error:))) != NULL) {
        originalOpenURL = method_getImplementation(m);
        replace(dc, @selector(openDocumentWithContentsOfURL:display:error:),
                ^id(id self, NSURL *url, BOOL display, NSError **error) {
            controllerCalls++;
            return ((id(*)(id, SEL, id, BOOL, NSError **)) originalOpenURL)(
                    self, @selector(openDocumentWithContentsOfURL:display:error:), url, display, error);
        });
    }
    if ((m = class_getInstanceMethod(dc, @selector(openDocumentWithContentsOfURL:display:completionHandler:))) != NULL) {
        originalOpenCompletion = method_getImplementation(m);
        replace(dc, @selector(openDocumentWithContentsOfURL:display:completionHandler:),
                ^void(id self, NSURL *url, BOOL display, id handler) {
            controllerCalls++;
            ((void (*)(id, SEL, id, BOOL, id)) originalOpenCompletion)(
                    self, @selector(openDocumentWithContentsOfURL:display:completionHandler:), url, display, handler);
        });
    }
    if ((m = class_getInstanceMethod(dc, @selector(makeDocumentWithContentsOfURL:ofType:error:))) != NULL) {
        originalMake = method_getImplementation(m);
        replace(dc, @selector(makeDocumentWithContentsOfURL:ofType:error:),
                ^id(id self, NSURL *url, NSString *type, NSError **error) {
            controllerCalls++;
            return ((id(*)(id, SEL, id, id, NSError **)) originalMake)(
                    self, @selector(makeDocumentWithContentsOfURL:ofType:error:), url, type, error);
        });
    }
    replace(app, @selector(presentError:), ^BOOL(id self, NSError *error) {
        errorsPresented++;
        return YES;
    });
    replace(dc, @selector(presentError:), ^BOOL(id self, NSError *error) {
        errorsPresented++;
        return YES;
    });
    replace(app, @selector(presentError:modalForWindow:delegate:didPresentSelector:contextInfo:),
            ^void(id self, NSError *error, NSWindow *w, id d, SEL s, void *c) {
        errorsPresented++;
    });
    replace([NSAlert class], @selector(runModal), ^NSInteger(id self) {
        alertsShown++;
        return NSAlertFirstButtonReturn;
    });
    replace(app, @selector(runModalForWindow:), ^NSInteger(id self, NSWindow *w) {
        alertsShown++;
        return NSModalResponseAbort;
    });
}

static int childPassed(void) {
    const char *kind = getenv("ARGDOC_KIND");
    const char *arg = getenv("ARGDOC_ARG");
    int ok = 1;
    if (strcmp(kind, "docs") == 0) {
        // The control: an application with document types uses the document controller.
        if (arg != NULL && strcmp(arg, "file") == 0 && documentsRead != 1) {
            fprintf(stderr, "FAIL: the existing file was not opened as a document (%d)\n", documentsRead);
            ok = 0;
        }
        if (arg != NULL && strcmp(arg, "word") == 0 && controllerCalls == 0) {
            fprintf(stderr, "FAIL: the document controller was not asked to open the word\n");
            ok = 0;
        }
        return ok;
    }
    if (controllerCalls != 0) {
        fprintf(stderr, "FAIL: the document controller was used %d times\n", controllerCalls);
        ok = 0;
    }
    if (errorsPresented != 0 || alertsShown != 0) {
        fprintf(stderr, "FAIL: %d errors presented, %d alerts or modal windows\n", errorsPresented, alertsShown);
        ok = 0;
    }
    if (documentsRead != 0) {
        fprintf(stderr, "FAIL: %d documents were opened\n", documentsRead);
        ok = 0;
    }
    for (NSWindow *w in [NSApp windows])
        if ([w isVisible]) {
            fprintf(stderr, "FAIL: a %s is visible\n", [NSStringFromClass([w class]) UTF8String]);
            ok = 0;
        }
    return ok;
}

static int child(void) {
    alarm(60);
    @autoreleasepool {
        installHooks();
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyAccessory];
        static id delegate;
        const char *kindOfDelegate = getenv("ARGDOC_DELEGATE");
        if (kindOfDelegate != NULL) {
            delegate = strcmp(kindOfDelegate, "refuse") == 0 ? [[RefusingDelegate alloc] init]
                                                             : [[NoOpenDelegate alloc] init];
            [app setDelegate: delegate];
        }
        if (strcmp(getenv("ARGDOC_LAUNCH"), "manual") == 0) {
            [app finishLaunching];
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
            return childPassed() ? 0 : 1;
        }
        [[NSNotificationCenter defaultCenter]
                addObserverForName: NSApplicationDidFinishLaunchingNotification
                            object: nil
                             queue: nil
                        usingBlock: ^(NSNotification *n) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                _exit(childPassed() ? 0 : 1);
            });
        }];
        [app run];
    }
    return 1;
}

static int spawnChild(const char *exe, const char *kind, const char *launch, const char *delegate,
                      const char *argName, const char *arg) {
    setenv("ARGDOC_KIND", kind, 1);
    setenv("ARGDOC_LAUNCH", launch, 1);
    if (delegate != NULL)
        setenv("ARGDOC_DELEGATE", delegate, 1);
    else
        unsetenv("ARGDOC_DELEGATE");
    setenv("ARGDOC_ARG", argName, 1);
    char *childArgv[3] = {(char *) exe, arg[0] != 0 ? (char *) arg : NULL, NULL};
    pid_t pid;
    if (posix_spawn(&pid, exe, NULL, NULL, childArgv, environ) != 0) {
        fprintf(stderr, "FAIL: cannot start %s\n", exe);
        return 1;
    }
    int status = 0;
    waitpid(pid, &status, 0);
    if (WIFSIGNALED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "FAIL: %s (%s, %s, delegate %s, argument %s) status %d\n", exe, kind, launch,
                delegate ? "yes" : "no", argName, status);
        return 1;
    }
    return 0;
}

static NSString *makeBundle(NSString *dir, NSString *name, NSString *exe, BOOL withTypes) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *macos = [dir stringByAppendingFormat: @"/%@.app/Contents/MacOS", name];
    [fm createDirectoryAtPath: macos withIntermediateDirectories: YES attributes: nil error: NULL];
    NSString *copy = [macos stringByAppendingPathComponent: @"probe"];
    [fm copyItemAtPath: exe toPath: copy error: NULL];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"probe", @"CFBundleExecutable",
            [@"test.argdoc." stringByAppendingString: name], @"CFBundleIdentifier",
            @"probe", @"CFBundleName", @"APPL", @"CFBundlePackageType", @"1", @"CFBundleVersion",
            @"NSApplication", @"NSPrincipalClass", nil];
    if (withTypes)
        [info setObject: [NSArray arrayWithObject: [NSDictionary dictionaryWithObjectsAndKeys:
                    @"Probe Text", @"CFBundleTypeName", @"Editor", @"CFBundleTypeRole",
                    [NSArray arrayWithObject: @"public.plain-text"], @"LSItemContentTypes",
                    @"ProbeDocument", @"NSDocumentClass", nil]]
                 forKey: @"CFBundleDocumentTypes"];
    [info writeToFile: [dir stringByAppendingFormat: @"/%@.app/Contents/Info.plist", name] atomically: NO];
    return copy;
}

int main(int argc, char **argv) {
    if (getenv("ARGDOC_KIND") != NULL)
        return child();

    int failures = 0;
    @autoreleasepool {
        char path[4096];
        uint32_t size = sizeof path;
        if (_NSGetExecutablePath(path, &size) != 0)
            return 1;
        NSString *exe = [NSString stringWithUTF8String: path];
        char tmpl[] = "/tmp/argdoc.XXXXXX";
        if (mkdtemp(tmpl) == NULL)
            return 1;
        NSString *dir = [NSString stringWithUTF8String: tmpl];
        NSString *file = [dir stringByAppendingPathComponent: @"exist.txt"];
        [@"hello" writeToFile: file atomically: NO encoding: NSUTF8StringEncoding error: NULL];

        // Bare executable: no bundle, no Info.plist.
        NSString *bare = [dir stringByAppendingPathComponent: @"bare"];
        [[NSFileManager defaultManager] copyItemAtPath: exe toPath: bare error: NULL];
        NSString *plain = makeBundle(dir, @"plain", exe, NO);
        NSString *docs = makeBundle(dir, @"docs", exe, YES);

        struct { const char *name; const char *value; } args[] = {
            {"word", "Public"}, {"file", [file UTF8String]}};
        const char *launches[] = {"manual", "run"};
        for (int a = 0; a < 2; a++)
            for (int l = 0; l < 2; l++) {
                for (int d = 0; d < 3; d++) {
                    const char *delegate = d == 0 ? NULL : d == 1 ? "noopen" : "refuse";
                    failures += spawnChild([bare UTF8String], "bare", launches[l], delegate, args[a].name, args[a].value);
                    failures += spawnChild([plain UTF8String], "plain", launches[l], delegate, args[a].name, args[a].value);
                }
                failures += spawnChild([docs UTF8String], "docs", launches[l], NULL, args[a].name, args[a].value);
                // The documented-type control with a delegate that refuses the argument.
                failures += spawnChild([docs UTF8String], "docs", launches[l], "refuse", args[a].name, args[a].value);
            }
        failures += spawnChild([bare UTF8String], "bare", "run", NULL, "none", "");
        [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
