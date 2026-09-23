// Standalone AppKit regression. No display connection or application init needed.
#import <AppKit/AppKit.h>
#include <pthread.h>
#include <stdio.h>

@interface NSApplication (RelaunchOnLoginState)
- (BOOL) _relaunchesOnLogin;
@end

enum { threadCount = 8, iterations = 20000 };
static NSApplication *app;
static int failures;

static void expect(const char *step, BOOL expected) {
    BOOL actual = [app _relaunchesOnLogin];
    if (actual != expected) {
        printf("FAIL %s: relaunches=%d expected %d\n", step, actual, expected);
        failures++;
    }
}

static void *disableThenEnable(void *unused) {
    for (int i = 0; i < iterations; i++) {
        [app disableRelaunchOnLogin];
        [app enableRelaunchOnLogin];
    }
    return NULL;
}

static void *disableOnly(void *unused) {
    for (int i = 0; i < iterations; i++)
        [app disableRelaunchOnLogin];
    return NULL;
}

static void *enableOnly(void *unused) {
    for (int i = 0; i < iterations; i++)
        [app enableRelaunchOnLogin];
    return NULL;
}

static void runThreads(void *(*body)(void *)) {
    pthread_t threads[threadCount];
    for (int i = 0; i < threadCount; i++)
        pthread_create(&threads[i], NULL, body, NULL);
    for (int i = 0; i < threadCount; i++)
        pthread_join(threads[i], NULL);
}

int main(void) {
    @autoreleasepool {
        app = [NSApplication alloc];
        if (![app respondsToSelector: @selector(disableRelaunchOnLogin)] ||
            ![app respondsToSelector: @selector(enableRelaunchOnLogin)]) {
            puts("FAIL: missing relaunch-on-login selectors");
            return 1;
        }
        expect("initial", YES);
        [app disableRelaunchOnLogin];
        expect("disable", NO);
        [app disableRelaunchOnLogin];
        [app enableRelaunchOnLogin];
        expect("nested disable, one enable", NO);
        [app enableRelaunchOnLogin];
        expect("balanced", YES);
        [app enableRelaunchOnLogin];
        expect("extra enable", YES);
        [app disableRelaunchOnLogin];
        expect("disable after extra enable", NO);
        [app enableRelaunchOnLogin];
        expect("balanced again", YES);

        runThreads(disableThenEnable);
        expect("concurrent balanced pairs", YES);
        runThreads(disableOnly);
        expect("concurrent disables", NO);
        [app disableRelaunchOnLogin];
        runThreads(enableOnly);
        expect("concurrent enables leave one disable", NO);
        [app enableRelaunchOnLogin];
        expect("last enable", YES);

        printf("relaunch on login checks=11 failures=%d\n", failures);
        return failures != 0;
    }
}
