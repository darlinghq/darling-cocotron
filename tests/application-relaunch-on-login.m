// Standalone AppKit regression. No display connection or application init needed.
// -disableRelaunchOnLogin and -enableRelaunchOnLogin are documented as paired calls that may nest; the
// state cannot be read back through the public API, so this checks that both exist and that any
// pairing, extra enables and concurrent callers are harmless.
#import <AppKit/AppKit.h>
#include <pthread.h>
#include <stdio.h>

enum { threadCount = 8, iterations = 20000 };
static NSApplication *app;

static void *disableThenEnable(void *unused) {
    for (int i = 0; i < iterations; i++) {
        [app disableRelaunchOnLogin];
        [app enableRelaunchOnLogin];
    }
    return NULL;
}

int main(void) {
    @autoreleasepool {
        app = [NSApplication alloc];
        if (![app respondsToSelector: @selector(disableRelaunchOnLogin)] ||
            ![app respondsToSelector: @selector(enableRelaunchOnLogin)]) {
            puts("FAIL: missing relaunch-on-login selectors");
            return 1;
        }
        [app disableRelaunchOnLogin];
        [app disableRelaunchOnLogin];
        [app enableRelaunchOnLogin];
        [app enableRelaunchOnLogin];
        [app enableRelaunchOnLogin];

        pthread_t threads[threadCount];
        for (int i = 0; i < threadCount; i++)
            pthread_create(&threads[i], NULL, disableThenEnable, NULL);
        for (int i = 0; i < threadCount; i++)
            pthread_join(threads[i], NULL);

        puts("PASS");
        return 0;
    }
}
