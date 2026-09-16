// Standalone AppKit regression. No display connection or application init needed.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
static NSArray *localizations;
static NSArray *selectedLocalizations(id self, SEL cmd) { return localizations; }
@interface LayoutDirectionApplication : NSApplication @end
@implementation LayoutDirectionApplication @end
int main(void) {
    @autoreleasepool {
        NSApplication *app = [LayoutDirectionApplication alloc];
        if (![app respondsToSelector:@selector(userInterfaceLayoutDirection)]) {
            puts("FAIL: missing application layout direction selector"); return 1;
        }
        Method method = class_getInstanceMethod([NSBundle class], @selector(preferredLocalizations));
        IMP original = method_setImplementation(method, (IMP)selectedLocalizations);
        NSArray *cases = @[@[@"en"], @[@"ar"], @[@"he"], @[@"fa"], @[@"ro"],
                           @[@"en", @"ar"], @[@"ar", @"en"], @[]];
        NSInteger expected[] = {0, 1, 1, 1, 0, 0, 1, 0};
        int failures = 0;
        for (NSUInteger i = 0; i < [cases count]; i++) {
            localizations = [cases objectAtIndex:i];
            NSInteger actual = [app userInterfaceLayoutDirection];
            if (actual != expected[i]) { printf("FAIL case %lu: got %ld expected %ld\n", (unsigned long)i, (long)actual, (long)expected[i]); failures++; }
        }
        method_setImplementation(method, original);
        printf("layout direction checks=8 failures=%d\n", failures);
        return failures != 0;
    }
}
