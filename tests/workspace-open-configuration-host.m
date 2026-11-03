// SPDX-License-Identifier: GPL-3.0-only
// Ancillary test tooling, GPL-3.0; the patched cocotron sources keep their own licence.
/* Runs the real NSWorkspaceOpenConfiguration of AppKit/NSWorkspace.m against a minimal mock root class.
 *
 * tests/workspace-open-configuration-host.sh extracts the class interface from NSWorkspace.h and the
 * implementation from NSWorkspace.m. Apple documents NSWorkspaceOpenConfiguration as an object the caller creates
 * and customizes before each open or launch, lists a default for every property, and the class adopts NSCopying.
 * So each +configuration is a separate object with those defaults, and -copy keeps every property. */
#include <objc/runtime.h>
#include <objc/objc-arc.h>
#include <stdio.h>
#include <stdlib.h>

typedef unsigned long NSUInteger;
typedef struct _NSZone NSZone;
typedef int cpu_type_t;
#define CPU_TYPE_ANY ((cpu_type_t)-1)
typedef long dispatch_once_t;
static void dispatch_once(dispatch_once_t *once, void (^block)(void))
{
    if (!*once) { *once = 1; block(); }
}

static int liveObjects;
static id pool[64];
static int pooled;

@protocol NSCopying
- (id)copyWithZone:(NSZone *)zone;
@end

__attribute__((objc_root_class))
@interface NSObject {
    Class isa;
    int _retainCount;
}
+ (id)alloc;
+ (id)allocWithZone:(NSZone *)zone;
+ (Class)class;
- (id)init;
- (Class)class;
- (id)retain;
- (void)release;
- (id)autorelease;
- (id)copy;
- (void)dealloc;
@end

@implementation NSObject
+ (id)alloc { return [self allocWithZone:NULL]; }
+ (id)allocWithZone:(NSZone *)zone
{
    (void)zone;
    NSObject *object = class_createInstance(self, 0);
    object->_retainCount = 1;
    liveObjects++;
    return object;
}
+ (Class)class { return self; }
- (id)init { return self; }
- (Class)class { return object_getClass(self); }
- (id)retain { _retainCount++; return self; }
- (void)release { if (--_retainCount == 0) [self dealloc]; }
- (id)autorelease { pool[pooled++] = self; return self; }
- (id)copy { return [(id)self copyWithZone:NULL]; }
- (void)dealloc { liveObjects--; object_dispose(self); }
@end

static void drain(void)
{
    while (pooled > 0) [pool[--pooled] release];
}

// Immutable collections: a copy is the same object, as with Foundation's immutable classes.
@interface NSString : NSObject @end
@implementation NSString @end
@interface NSArray<ObjectType> : NSObject <NSCopying>
- (NSUInteger)count;
@end
@implementation NSArray
- (NSUInteger)count { return 0; }
- (id)copyWithZone:(NSZone *)zone { (void)zone; return [self retain]; }
@end
@interface NSDictionary<KeyType, ObjectType> : NSObject <NSCopying>
- (NSUInteger)count;
@end
@implementation NSDictionary
- (NSUInteger)count { return 0; }
- (id)copyWithZone:(NSZone *)zone { (void)zone; return [self retain]; }
@end
// A copy that is a new object, to tell a copied property from a retained one.
@interface NSMutableArray : NSArray @end
@implementation NSMutableArray
- (id)copyWithZone:(NSZone *)zone { (void)zone; return [[NSArray alloc] init]; }
@end
@interface NSAppleEventDescriptor : NSObject @end
@implementation NSAppleEventDescriptor @end

#include INTERFACE_INC
#include IMPLEMENTATION_INC

static int fails, checks;
#define CK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void checkDefaults(NSWorkspaceOpenConfiguration *c, const char *how)
{
    CK(c.activates == YES, "%s: activates defaults to YES", how);
    CK(c.addsToRecentItems == YES, "%s: addsToRecentItems defaults to YES", how);
    CK(c.allowsRunningApplicationSubstitution == YES, "%s: allowsRunningApplicationSubstitution defaults to YES", how);
    CK(c.promptsUserIfNeeded == YES, "%s: promptsUserIfNeeded defaults to YES", how);
    CK(c.createsNewApplicationInstance == NO, "%s: createsNewApplicationInstance defaults to NO", how);
    CK(c.hides == NO && c.hidesOthers == NO, "%s: hides and hidesOthers default to NO", how);
    CK(c.isForPrinting == NO, "%s: forPrinting defaults to NO", how);
    CK(c.requiresUniversalLinks == NO, "%s: requiresUniversalLinks defaults to NO", how);
    CK(c.appleEvent == nil, "%s: appleEvent defaults to nil", how);
    CK(c.arguments != nil && [c.arguments count] == 0, "%s: arguments defaults to an empty array", how);
    CK(c.environment != nil && [c.environment count] == 0, "%s: environment defaults to an empty dictionary", how);
    CK(c.architecture == CPU_TYPE_ANY, "%s: architecture defaults to CPU_TYPE_ANY (got %d)", how, c.architecture);
}

int main(void)
{
    int baseline = liveObjects;
    NSWorkspaceOpenConfiguration *first = [NSWorkspaceOpenConfiguration configuration];
    checkDefaults(first, "+configuration");
    first.activates = NO;
    first.hides = YES;
    NSWorkspaceOpenConfiguration *second = [NSWorkspaceOpenConfiguration configuration];
    CK(second != first, "+configuration returns a new object each time");
    checkDefaults(second, "+configuration after another caller customized one");

    NSWorkspaceOpenConfiguration *plain = [[NSWorkspaceOpenConfiguration alloc] init];
    checkDefaults(plain, "-init");

    if (!class_getInstanceMethod([NSWorkspaceOpenConfiguration class], @selector(copyWithZone:))) {
        CK(0, "implements -copyWithZone: (NSCopying)");
    } else {
        NSAppleEventDescriptor *event = [[NSAppleEventDescriptor alloc] init];
        NSMutableArray *arguments = [[NSMutableArray alloc] init];
        NSDictionary *environment = [[NSDictionary alloc] init];
        plain.requiresUniversalLinks = YES;
        plain.forPrinting = YES;
        plain.activates = NO;
        plain.addsToRecentItems = NO;
        plain.allowsRunningApplicationSubstitution = NO;
        plain.createsNewApplicationInstance = YES;
        plain.hides = YES;
        plain.hidesOthers = YES;
        plain.promptsUserIfNeeded = NO;
        plain.appleEvent = event;
        plain.arguments = (NSArray *)arguments;
        plain.environment = environment;
        plain.architecture = 7;
        CK(plain.arguments != (NSArray *)arguments, "the arguments property copies");

        NSWorkspaceOpenConfiguration *copy = [plain copy];
        CK(copy != plain && [copy class] == [plain class], "-copy returns a new object of the same class");
        CK(copy.requiresUniversalLinks && copy.isForPrinting && !copy.activates && !copy.addsToRecentItems &&
           !copy.allowsRunningApplicationSubstitution && copy.createsNewApplicationInstance && copy.hides &&
           copy.hidesOthers && !copy.promptsUserIfNeeded && copy.architecture == 7,
           "-copy keeps every scalar property");
        CK(copy.appleEvent == event && copy.arguments == plain.arguments && copy.environment == environment,
           "-copy keeps the object properties");
        copy.hides = NO;
        CK(plain.hides == YES, "changing the copy leaves the original alone");
        [copy release];
        [event release];
        [arguments release];
        [environment release];
    }
    [plain release];
    // An atomic getter's result can sit in the runtime's return-value slot until the next one; flush it.
    objc_autoreleaseReturnValue(nil);
    drain();
    CK(liveObjects == baseline, "every configuration and the objects it held are released (%d left)",
       liveObjects - baseline);

    printf("%s: %d checks, %d failed\n", fails ? "FAIL" : "PASS", checks, fails);
    return fails != 0;
}
