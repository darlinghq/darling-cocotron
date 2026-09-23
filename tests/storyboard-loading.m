// Standalone AppKit regression: loads the compiled storyboard written by storyboard-loading.py.
// usage: storyboard-loading DIRECTORY_CONTAINING_Fixture.storyboardc
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface FixtureViewController : NSViewController
@end
@implementation FixtureViewController
@end

static int checks, failures;

static void expect(BOOL ok, const char *what) {
    checks++;
    if (!ok) {
        printf("FAIL %s\n", what);
        failures++;
    }
}

static NSString *raisedName(void (^block)(void)) {
    @try {
        block();
    } @catch (NSException *exception) {
        return [exception name];
    }
    return nil;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) {
            puts("usage: storyboard-loading DIRECTORY");
            return 2;
        }
        NSBundle *bundle = [NSBundle bundleWithPath: [NSString stringWithUTF8String: argv[1]]];
        NSStoryboard *storyboard = [NSStoryboard storyboardWithName: @"Fixture" bundle: bundle];
        expect(storyboard != nil, "storyboardWithName:bundle: finds Fixture.storyboardc");
        expect([NSStoryboard mainStoryboard] == nil, "no main storyboard without NSMainStoryboardFile");
        expect([raisedName(^{ [NSStoryboard storyboardWithName: @"Missing" bundle: bundle]; })
                       isEqual: NSInvalidArgumentException],
               "a missing storyboard raises NSInvalidArgumentException");

        id initial = [storyboard instantiateInitialController];
        expect([initial isMemberOfClass: [NSWindowController class]], "initial controller is the window controller");
        expect([initial storyboard] == storyboard, "window controller records its storyboard");

        FixtureViewController *detail = [storyboard instantiateControllerWithIdentifier: @"Detail"];
        expect([detail isMemberOfClass: [FixtureViewController class]], "Detail decodes as its archived class");
        expect([[detail title] isEqual: @"Detail"], "Detail keeps its archived title");
        expect([detail storyboard] == storyboard, "view controller records its storyboard");
        expect([detail view] != nil && NSEqualSizes([[detail view] frame].size, NSMakeSize(240, 120)),
               "Detail loads its view from the nib inside the storyboard");
        expect([storyboard instantiateControllerWithIdentifier: @"Detail"] != detail,
               "each instantiation creates a new controller");

        expect([raisedName(^{ [storyboard instantiateControllerWithIdentifier: @"Nope"]; })
                       isEqual: NSInvalidArgumentException],
               "an unknown identifier raises NSInvalidArgumentException");
        expect([raisedName(^{ [storyboard instantiateControllerWithIdentifier: @"Unbuilt"]; })
                       isEqual: NSInternalInconsistencyException],
               "a scene whose nib is missing raises");
        expect([raisedName(^{ [storyboard instantiateControllerWithIdentifier: @"Ambiguous"]; })
                       isEqual: NSInternalInconsistencyException],
               "a scene with two top-level controllers raises");

        printf("storyboard loading checks=%d failures=%d\n", checks, failures);
        return failures != 0;
    }
}
