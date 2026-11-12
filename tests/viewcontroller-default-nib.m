// Standalone AppKit regression: a view controller with a nil nibName loads the nib named after its class.
// usage: viewcontroller-default-nib DIRECTORY_CONTAINING_DefaultNibViewController.nib
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface DefaultNibViewController : NSViewController
@end
@implementation DefaultNibViewController
@end

@interface NoNibViewController : NSViewController
@end
@implementation NoNibViewController
@end

static int checks, failures;

static void expect(BOOL ok, const char *what) {
    checks++;
    if (!ok) {
        printf("FAIL %s\n", what);
        failures++;
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) {
            puts("usage: viewcontroller-default-nib DIRECTORY");
            return 2;
        }
        NSBundle *bundle = [NSBundle bundleWithPath: [NSString stringWithUTF8String: argv[1]]];

        DefaultNibViewController *controller =
                [[DefaultNibViewController alloc] initWithNibName: nil bundle: bundle];
        expect([controller nibName] == nil, "nibName stays nil");
        expect([controller view] != nil && NSEqualSizes([[controller view] frame].size, NSMakeSize(320, 200)),
               "view loads from DefaultNibViewController.nib");

        NoNibViewController *missing = [[NoNibViewController alloc] initWithNibName: nil bundle: bundle];
        NSString *raised = nil;
        @try {
            [missing view];
        } @catch (NSException *exception) {
            raised = [exception name];
        }
        expect([raised isEqual: NSInvalidArgumentException], "no class-named nib raises");

        printf("default nib checks=%d failures=%d\n", checks, failures);
        return failures != 0;
    }
}
