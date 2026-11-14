// Link with candidate AppKit; no display is needed.
//
// A nib that cannot be found is a failed load: the loaders return NO and push nothing onto the nib-path
// stack. Darling's own NSMutableArray lets a nil -addObject:
// through, so a plain run only sees a nil push by recording the call; the shared cache's NSMutableArray
// raises "object cannot be nil" and the app dies.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

// Declared by AppKit on macOS; not in this tree's header.
@interface NSBundle (MissingNibProbe)
- (BOOL) loadNibNamed: (NSString *) name owner: (id) owner topLevelObjects: (NSArray **) topLevelObjects;
@end

static NSUInteger nilPushes;
static IMP originalPush;

static void recordPush(id self, SEL _cmd, id path) {
    if (path == nil) nilPushes++;
    ((void (*)(id, SEL, id)) originalPush)(self, _cmd, path);
}

// Runs block, which returns the loader's result; fails if it raises or if it pushed a nil path.
static BOOL loads(NSString *what, BOOL (^block)(void)) {
    nilPushes = 0;
    BOOL result = YES;
    @try {
        result = block();
    } @catch (NSException *exception) {
        expect(NO, [NSString stringWithFormat: @"%@ raised %@: %@", what, [exception name], [exception reason]]);
    }
    expect(nilPushes == 0, [NSString stringWithFormat: @"%@ pushed a nil nib path", what]);
    return result;
}

int main(void) {
    @autoreleasepool {
        Method push = class_getClassMethod([NSBundle class], @selector(pushNibPath:));
        expect(push != NULL, @"NSBundle has +pushNibPath:");
        originalPush = method_setImplementation(push, (IMP) recordPush);

        id owner = [[NSObject new] autorelease];

        expect(!loads(@"+loadNibNamed:owner: for a missing nib", ^BOOL {
                   return [NSBundle loadNibNamed: @"DoesNotExist" owner: owner];
               }),
               @"+loadNibNamed:owner: returns NO for a missing nib");
        expect(!loads(@"+loadNibNamed:owner: with a nil name", ^BOOL {
                   return [NSBundle loadNibNamed: nil owner: owner];
               }),
               @"+loadNibNamed:owner: returns NO for a nil name");
        expect(!loads(@"-loadNibFile:externalNameTable:withZone: for a missing nib", ^BOOL {
                   return [[NSBundle mainBundle] loadNibFile: @"DoesNotExist"
                                           externalNameTable: nil
                                                    withZone: NSDefaultMallocZone()];
               }),
               @"-loadNibFile:externalNameTable:withZone: returns NO for a missing nib");
        expect(!loads(@"+loadNibFile:externalNameTable:withZone: with a nil path", ^BOOL {
                   return [NSBundle loadNibFile: nil externalNameTable: nil withZone: NSDefaultMallocZone()];
               }),
               @"+loadNibFile:externalNameTable:withZone: returns NO for a nil path");
        expect(!loads(@"-loadNibNamed:owner:topLevelObjects: for a missing nib", ^BOOL {
                   NSArray *objects = nil;
                   return [[NSBundle mainBundle] loadNibNamed: @"DoesNotExist" owner: owner topLevelObjects: &objects];
               }),
               @"-loadNibNamed:owner:topLevelObjects: returns NO for a missing nib");

        // The stack is balanced: nothing was left behind by the failed loads.
        expect([NSBundle currentNibPath] == nil, @"a failed load leaves no nib path on the stack");

        NSLog(@"PASS: a missing nib is a failed load and no nil nib path is pushed");
    }
    return 0;
}
