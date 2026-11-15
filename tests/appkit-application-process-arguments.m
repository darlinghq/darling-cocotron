// Copyright (C) 2026 Lubos Dolezel
//
// Which documents NSApplication opens at launch, and where it takes them from.
//
// Documented: NSApplicationMain ignores the argc and argv it is handed, and
// the "-key value" arguments of the process form the NSArgumentDomain of
// NSUserDefaults. Observed on macOS 26.7.3 (x86_64) and 10.14.4 (i386), the
// same on both, with a delegate that implements -application:openFiles: and
// documents given as arguments of the executable:
//   - every argument that is not a switch is opened, in order, before
//     applicationDidFinishLaunching: ("a b" opens a then b);
//   - every switch takes the next argument as its value, so the value is
//     not a document ("-NSDocumentRevisionsDebugMode YES a" opens a; "-Foo -x a"
//     opens a; "-psn_0_12345 a" opens nothing; a lone "-" also takes a value);
//   - "-NSOpen" is a switch whose value is itself opened ("-NSOpen a b"
//     opens a and b; "-NSOpen -Foo a" opens "-Foo" and a);
//   - "--" ends the list: "a -- b" opens a, "-- a" opens nothing;
//   - the result is the same whether the program calls NSApplicationMain with
//     its own argv, with argv advanced to the last argument and the original
//     argc, or with argc 0.
//   - an empty argument is a document like any other ("" a opens "" then a;
//     "-NSOpen ''" opens ""; a switch's empty value is not one);
//   - documents are delivered one call per file, in order: -application:openFiles:
//     with a one-element array when the delegate implements it (also when it
//     implements -application:openFile: as well), otherwise -application:openFile:.
// The test starts itself once per argument list and per way of calling
// NSApplicationMain (and per delegate shape for the plain call), collects what the delegate is asked to open, and prints
// PASS when every child agrees. It also checks that a "-key value" pair
// reaches the argument domain. Needs a display connection.
// On macOS 10.14 NSApplicationMain wants an Info.plist with NSPrincipalClass
// NSApplication in the executable: link with
// -Wl,-sectcreate,__TEXT,__info_plist,<plist>.
#import <AppKit/AppKit.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#define MAX_ARGS 8

static const struct {
    const char *arguments[MAX_ARGS];
    const char *documents[MAX_ARGS];
} cases[] = {
    {{"-NSDocumentRevisionsDebugMode", "YES", "a"}, {"a"}},
    {{"a", "b"}, {"a", "b"}},
    {{"-psn_0_12345", "a"}, {NULL}},
    {{"-NSOpen", "a", "b"}, {"a", "b"}},
    {{"-NSOpen", "-Foo", "a"}, {"-Foo", "a"}},
    {{"-Foo", "-x", "a"}, {"a"}},
    {{"-", "a"}, {NULL}},
    {{"a", "--", "b"}, {"a"}},
    {{"--", "a"}, {NULL}},
    {{"-Foo"}, {NULL}},
    {{"-Foo", "bar", "-NSOpen", "a"}, {"a"}},
    {{"", "a"}, {"", "a"}},
    {{"a", ""}, {"a", ""}},
    {{"-NSOpen", "", "a"}, {"", "a"}},
    {{"-Foo", "", "a"}, {"a"}},
    {{"-NSOpen", ""}, {""}},
};
#define CASE_COUNT (sizeof(cases) / sizeof(cases[0]))

// Every delegate call is recorded as one array: the files of an
// -application:openFiles: call, or {"openFile:", file} for -application:openFile:.
static NSMutableArray *calls;
static int caseIndex;
static const char *shape;
static id gDelegate;

@interface Delegate : NSObject <NSApplicationDelegate>
@end

@interface SingleDelegate : Delegate
@end

@interface MultiDelegate : Delegate
@end

@interface BothDelegate : Delegate
@end

@implementation SingleDelegate
- (BOOL) application: (NSApplication *) app openFile: (NSString *) filename {
    [calls addObject: [NSArray arrayWithObjects: @"openFile:", filename, nil]];
    return YES;
}
@end

@implementation MultiDelegate
- (void) application: (NSApplication *) app openFiles: (NSArray *) filenames {
    [calls addObject: filenames];
    [app replyToOpenOrPrint: NSApplicationDelegateReplySuccess];
}
@end

@implementation BothDelegate
- (BOOL) application: (NSApplication *) app openFile: (NSString *) filename {
    [calls addObject: [NSArray arrayWithObjects: @"openFile:", filename, nil]];
    return YES;
}

- (void) application: (NSApplication *) app openFiles: (NSArray *) filenames {
    [calls addObject: filenames];
    [app replyToOpenOrPrint: NSApplicationDelegateReplySuccess];
}
@end

@implementation Delegate
- (BOOL) applicationShouldOpenUntitledFile: (NSApplication *) app {
    return NO;
}

- (void) applicationDidFinishLaunching: (NSNotification *) note {
    NSMutableArray *expected = [NSMutableArray array];
    for (int i = 0; i < MAX_ARGS && cases[caseIndex].documents[i] != NULL; i++)
        [expected addObject: [NSString stringWithUTF8String: cases[caseIndex].documents[i]]];

    // "multi": only -application:openFiles:; "both": it and -application:openFile:
    // (openFiles: wins); "single": only -application:openFile:.
    NSMutableArray *expectedCalls = [NSMutableArray array];
    for (NSString *file in expected)
        [expectedCalls addObject: strcmp(shape, "single") == 0
                                          ? [NSArray arrayWithObjects: @"openFile:", file, nil]
                                          : [NSArray arrayWithObject: file]];

    int ok = [calls isEqual: expectedCalls];
    if (!ok)
        fprintf(stderr, "FAIL: case %d (%s) calls %s, expected %s\n", caseIndex, shape,
                [[calls description] UTF8String], [[expectedCalls description] UTF8String]);
    if (caseIndex == 0) {
        id value = [[NSUserDefaults standardUserDefaults] objectForKey: @"NSDocumentRevisionsDebugMode"];
        if (![value isEqual: @"YES"]) {
            fprintf(stderr, "FAIL: argument domain value is %s\n", [[value description] UTF8String]);
            ok = 0;
        }
    }
    fflush(stderr);
    _exit(ok ? 0 : 1);
}
@end

int main(int argc, char **argv) {
    const char *how = getenv("PROCESS_ARGUMENTS_CALL");
    if (how == NULL) {
        static const char *hows[] = {"own", "advanced", "none", "own-single", "own-both"};
        int failures = 0;
        for (size_t c = 0; c < CASE_COUNT; c++) {
            for (size_t h = 0; h < 5; h++) {
                char *childArgv[MAX_ARGS + 2] = {argv[0]};
                for (int i = 0; i < MAX_ARGS && cases[c].arguments[i] != NULL; i++)
                    childArgv[i + 1] = (char *) cases[c].arguments[i];
                char number[16];
                snprintf(number, sizeof number, "%zu", c);
                setenv("PROCESS_ARGUMENTS_CASE", number, 1);
                setenv("PROCESS_ARGUMENTS_CALL", h < 3 ? hows[h] : "own", 1);
                setenv("PROCESS_ARGUMENTS_SHAPE", h == 3 ? "single" : h == 4 ? "both" : "multi", 1);
                pid_t pid;
                if (posix_spawn(&pid, argv[0], NULL, NULL, childArgv, environ) != 0) {
                    fprintf(stderr, "FAIL: cannot start the child\n");
                    return 1;
                }
                int status = 0;
                waitpid(pid, &status, 0);
                if (WIFSIGNALED(status))
                    fprintf(stderr, "FAIL: case %zu (%s): child died on signal %d\n", c, hows[h],
                            WTERMSIG(status));
                else if (WEXITSTATUS(status) != 0)
                    fprintf(stderr, "FAIL: case %zu (%s): child exited with %d\n", c, hows[h],
                            WEXITSTATUS(status));
                else
                    continue;
                failures++;
            }
        }
        if (failures == 0)
            printf("PASS\n");
        return failures != 0;
    }

    alarm(60);
    shape = getenv("PROCESS_ARGUMENTS_SHAPE");
    if (shape == NULL)
        shape = "multi";
    caseIndex = atoi(getenv("PROCESS_ARGUMENTS_CASE"));
    @autoreleasepool {
        calls = [[NSMutableArray alloc] init];
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyAccessory];
        Class delegateClass = strcmp(shape, "single") == 0 ? [SingleDelegate class]
                              : strcmp(shape, "both") == 0 ? [BothDelegate class]
                                                           : [MultiDelegate class];
        // NSApplication keeps its delegate unretained: hold it strongly here
        // (required when compiled with ARC, harmless without).
        gDelegate = [[delegateClass alloc] init];
        [app setDelegate: gDelegate];
    }
    if (strcmp(how, "advanced") == 0)
        return NSApplicationMain(argc, (const char **) (argv + argc - 1));
    if (strcmp(how, "none") == 0) {
        const char *empty[] = {NULL};
        return NSApplicationMain(0, empty);
    }
    return NSApplicationMain(argc, (const char **) argv);
}
