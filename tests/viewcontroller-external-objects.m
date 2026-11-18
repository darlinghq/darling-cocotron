// Standalone AppKit regression: a view controller loads its view nib with the objects it archived in
// NSExternalObjectsTableForViewLoading, the way a storyboard scene's controller does.
// usage: viewcontroller-external-objects DIRECTORY_CONTAINING_ViewObjectsController.archive_AND_ViewObjects-view.nib
#import <AppKit/AppKit.h>
#include <stdio.h>

static NSBundle *fixtureBundle;
static int deallocations;

@interface ViewObjectsController : NSViewController
@end
@implementation ViewObjectsController
- (NSBundle *) nibBundle {
    return fixtureBundle;
}
- (void) dealloc {
    deallocations++;
    [super dealloc];
}
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
            puts("usage: viewcontroller-external-objects DIRECTORY");
            return 2;
        }
        NSString *directory = [NSString stringWithUTF8String: argv[1]];
        fixtureBundle = [NSBundle bundleWithPath: directory];
        NSData *archive = [NSData dataWithContentsOfFile: [directory stringByAppendingPathComponent: @"ViewObjectsController.archive"]];
        // A table that kept its owner would be a retain cycle. Loading a nib leaks its owner by itself in
        // this runtime, so the cycle is checked on a controller that is only decoded.
        @autoreleasepool {
            [NSKeyedUnarchiver unarchiveObjectWithData: archive];
        }
        expect(deallocations == 1, "a decoded controller is deallocated, so its table does not retain it");

        @autoreleasepool {
            ViewObjectsController *controller = [NSKeyedUnarchiver unarchiveObjectWithData: archive];
            expect([controller isMemberOfClass: [ViewObjectsController class]], "the archive decodes as its archived class");
            expect([[controller nibName] isEqual: @"ViewObjects-view"], "the controller keeps its archived nib name");

            NSString *raised = nil;
            NSView *view = nil;
            @try {
                view = [controller view];
            } @catch (NSException *exception) {
                raised = [exception reason];
            }
            expect(raised == nil, "the view nib loads although it holds external object placeholders");
            if (raised != nil)
                printf("reason: %s\n", [raised UTF8String]);
            expect(view != nil && NSEqualSizes([view frame].size, NSMakeSize(240, 120)),
                   "UpstreamPlaceholder-1 is the controller, so its view outlet gets the nib's view");
            expect([[controller representedObject] isKindOfClass: [NSArray class]] &&
                           [[[controller representedObject] objectAtIndex: 0] isEqual: @"shared object"],
                   "UpstreamPlaceholder-2 is the other object archived in the table");
        }

        printf("view controller external objects checks=%d failures=%d\n", checks, failures);
    }
    return failures != 0;
}
