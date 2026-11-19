/* SPDX-License-Identifier: GPL-3.0-or-later */
/* R6-OWN-01 — ownership of NSTextFieldCell _placeholder and _allowedInputSourceLocales across
 * -copyWithZone: (issue #16). Manual retain/release; i386 (fragile ABI) and x86_64.
 *
 *   own01 FIELD ORDER
 *     FIELD  placeholder | locales      tracked value (TStr), never really freed (tombstone)
 *            real                        NSString + NSArray values; run with NSZombieEnabled=YES
 *     ORDER  orig-first | copy-first     which cell is released first
 *
 * A tracked value counts its own references. When the count reaches 0 it is marked dead instead of
 * being freed; any retain/release/copy/length on a dead value counts as a zombie operation, so a
 * double release is detected deterministically instead of corrupting the heap.
 * PASS: every tracked value dies exactly once, no zombie operation, and the surviving cell's value
 * is still alive and usable after the other cell is gone.
 */
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static int g_created, g_deaths, g_zombie;

@interface TStr : NSString {
@public
    int rc, dead, deaths, serial;
}
+ (TStr *) make;
@end

#define MAXOBJ 64
static TStr *g_all[MAXOBJ];

@implementation TStr
+ (TStr *) make {
    TStr *t = [[TStr alloc] init];
    t->rc = 1;
    t->serial = g_created;
    if (g_created < MAXOBJ) g_all[g_created] = t;
    g_created++;
    return t;
}
- (id) retain { if (dead) { g_zombie++; return self; } rc++; return self; }
- (oneway void) release {
    if (dead) { g_zombie++; return; }
    if (--rc == 0) { dead = 1; deaths++; g_deaths++; }   /* tombstone: never [super dealloc] */
}
- (NSUInteger) retainCount { return dead ? 0 : (NSUInteger) rc; }
- (id) copyWithZone: (NSZone *) zone { if (dead) g_zombie++; return [TStr make]; }
- (NSUInteger) length { if (dead) g_zombie++; return 1; }
- (unichar) characterAtIndex: (NSUInteger) i { if (dead) g_zombie++; return 'p'; }
- (void) dealloc { g_zombie++; }   /* never reached through release */
@end

static int fail;
#define CHECK(c, what) do { if (c) printf("OWN_CHECK PASS %s\n", what); \
    else { fail++; printf("OWN_CHECK FAIL %s\n", what); } } while (0)

static void setField(NSTextFieldCell *c, const char *field, id v) {
    if (!strcmp(field, "placeholder")) [c setPlaceholderString: v];
    else [c setAllowedInputSourceLocales: v];
}
static id getField(NSTextFieldCell *c, const char *field) {
    if (!strcmp(field, "placeholder")) return [c placeholderString];
    return [c allowedInputSourceLocales];
}

static int tracked(const char *field, int origFirst) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    TStr *v = [TStr make];
    NSTextFieldCell *a = [[NSTextFieldCell alloc] initTextCell: @"own01"];
    setField(a, field, v);
    [v release];                                     /* the cell keeps its own copy */
    id va = getField(a, field);
    CHECK(va != nil && [va isKindOfClass: [TStr class]] && !((TStr *) va)->dead, "original holds a live value");
    NSTextFieldCell *b = [a copy];
    id vb = getField(b, field);
    printf("OWN_INFO field=%s order=%s same_object_after_copy=%d\n", field, origFirst ? "orig-first" : "copy-first", va == vb);
    [pool drain]; pool = [NSAutoreleasePool new];

    NSTextFieldCell *first = origFirst ? a : b, *survivor = origFirst ? b : a;
    [first release];
    [pool drain]; pool = [NSAutoreleasePool new];
    id vs = getField(survivor, field);
    CHECK(vs != nil && [vs isKindOfClass: [TStr class]] && !((TStr *) vs)->dead, "survivor value alive after the other cell is released");
    CHECK([vs length] == 1, "survivor value usable");
    [pool drain]; pool = [NSAutoreleasePool new];
    [survivor release];
    [pool drain];

    int once = 1;
    for (int i = 0; i < g_created && i < MAXOBJ; i++) {
        printf("OWN_OBJ serial=%d deaths=%d rc=%d\n", i, g_all[i]->deaths, g_all[i]->dead ? 0 : g_all[i]->rc);
        if (g_all[i]->deaths != 1) once = 0;
    }
    CHECK(once, "every tracked value destroyed exactly once");
    CHECK(g_zombie == 0, "no operation on a destroyed value");
    printf("OWN_SUMMARY created=%d deaths=%d zombie_ops=%d\n", g_created, g_deaths, g_zombie);
    return fail;
}

static int real(int origFirst) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSTextFieldCell *a = [[NSTextFieldCell alloc] initTextCell: @"own01"];
    [a setPlaceholderString: [NSMutableString stringWithFormat: @"placeholder-%d", 42]];
    [a setAllowedInputSourceLocales: [NSMutableArray arrayWithObjects: @"fr_FR", [NSString stringWithFormat: @"en_%s", "US"], nil]];
    NSTextFieldCell *b = [a copy];
    [pool drain]; pool = [NSAutoreleasePool new];
    NSTextFieldCell *first = origFirst ? a : b, *survivor = origFirst ? b : a;
    [first release];
    [pool drain]; pool = [NSAutoreleasePool new];
    CHECK([[survivor placeholderString] isEqualToString: @"placeholder-42"], "survivor placeholder intact");
    CHECK([[survivor allowedInputSourceLocales] count] == 2 &&
          [[[survivor allowedInputSourceLocales] objectAtIndex: 1] isEqualToString: @"en_US"], "survivor locales intact");
    [pool drain]; pool = [NSAutoreleasePool new];
    [survivor release];
    [pool drain];
    return fail;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 3) { printf("usage: own01 placeholder|locales|real orig-first|copy-first\n"); return 2; }
    Dl_info di;
    if (dladdr((void *) [NSTextFieldCell class], &di)) printf("OWN_IMAGE appkit=%s\n", di.dli_fname);
    printf("OWN_ARCH %s\n", sizeof(void *) == 4 ? "i386" : "x86_64");
    int origFirst = !strcmp(argv[2], "orig-first");
    int r = !strcmp(argv[1], "real") ? real(origFirst) : tracked(argv[1], origFirst);
    printf("OWN_RESULT field=%s order=%s %s failures=%d\n", argv[1], argv[2], r ? "FAIL" : "PASS", r);
    return r ? 1 : 0;
}
