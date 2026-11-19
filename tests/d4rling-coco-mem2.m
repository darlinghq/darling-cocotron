/* SPDX-License-Identifier: GPL-3.0-or-later */
/* COCOTRON-ABI-DYN-01, T3 (R5 variant: port-aware identifier read): ownership of _identifier across NSCell / NSMenu copies, pinned Cocotron
 * (deef9911), BEFORE any port. Mach-O i386 and x86_64, manual retain/release, one scenario per process.
 *
 *   coco-mem KIND IDENT COPIES ORDER [app]
 *     KIND    cell (NSCell initTextCell:) | menu (NSMenu initWithTitle:)
 *     IDENT   tracked : a TrackedID, a witness object that counts its own retains/releases, is never
 *                       freed (its memory stays as a tombstone), and reports every message received
 *                       after its last release: RELEASE_AFTER_DEALLOC (double release) and
 *                       RETAIN_AFTER_DEALLOC; a surviving object whose _identifier ivar points to a
 *                       dead TrackedID is a dangling reference (read without messaging it)
 *             string  : a real heap NSString (copy of an NSMutableString); the process is left to the
 *                       allocator (run it with the libmalloc diagnostics MallocScribble, ...)
 *             nil     : no identifier (control)
 *     COPIES  number of -copy of the original (0 = control without copy)
 *     ORDER   cf : copies released first (creation order), original last
 *             of : original released first, then the copies
 *   coco-mem selftest        TrackedID over-released on purpose: the detector must count 1 double release
 *   coco-mem strselftest     a heap NSString released twice on purpose: reaction of the allocator
 *
 * Contract checked (verify_t3.py): each object that holds the identifier owns one reference:
 * after N copies the identifier is retained N+1 times (or each copy holds its own object); it is
 * deallocated exactly once, after the last holder, with no release or retain after that.
 */
#import <Foundation/Foundation.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface NSObject (T3API)
+ (id) sharedApplication;
- (id) initTextCell: (NSString *) s;
- (id) initWithTitle: (NSString *) t;
- (void) setIdentifier: (id) ident;
@end

static int gDoubleRelease, gRetainAfterDealloc, gDealloc;

@interface TrackedID : NSObject {
  @public
    int tag, rc, dead, copies;
}
@end

@implementation TrackedID
+ (TrackedID *) trackedWithTag: (int) tag {
    TrackedID *t = [self alloc];
    t->tag = tag;
    t->rc = 1;
    return t;
}
- (id) retain {
    if (dead) {
        gRetainAfterDealloc++;
        printf("T3EV id=%d event=RETAIN_AFTER_DEALLOC\n", tag);
        return self;
    }
    rc++;
    return self;
}
- (oneway void) release {
    if (dead) {
        gDoubleRelease++;
        printf("T3EV id=%d event=RELEASE_AFTER_DEALLOC\n", tag);
        return;
    }
    if (--rc == 0) {
        dead = 1;
        gDealloc++;
        printf("T3EV id=%d event=DEALLOC\n", tag);   /* memory deliberately kept: tombstone */
    }
}
- (NSUInteger) retainCount { return dead ? 0 : (NSUInteger) rc; }
- (id) copyWithZone: (NSZone *) zone { copies++; return [self retain]; }
- (id) copy { return [self copyWithZone: NULL]; }
- (void) dealloc { printf("T3EV id=%d event=UNEXPECTED_DEALLOC_CALL\n", tag); }
@end

/* R5 (18/11/2026): the legacy-ABI port keeps _identifier in side storage on i386, out of the ivar
 * list. Fall back to the public accessor, inside a pool so an atomic getter's autorelease is drained. */
@interface NSObject (T3Ident)
- (id) identifier;
@end
static id identIvar(id obj)
{
    Ivar v = class_getInstanceVariable(object_getClass(obj), "_identifier");
    if (v) return object_getIvar(obj, v);
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    id r = [obj identifier];
    [pool drain];
    return r;
}

static long rcOf(id ident, int tracked)
{
    if (!ident) return -1;
    if (tracked) return ((TrackedID *) ident)->dead ? 0 : ((TrackedID *) ident)->rc;
    return (long) [ident retainCount];   /* only read while the object is known alive */
}

static int scenario(const char *kind, const char *identKind, int ncopies, const char *order)
{
    int tracked = !strcmp(identKind, "tracked"), isString = !strcmp(identKind, "string");
    id obj;
    if (!strcmp(kind, "cell"))
        obj = [[objc_getClass("NSCell") alloc] initTextCell: @"t3"];
    else
        obj = [[objc_getClass("NSMenu") alloc] initWithTitle: @"t3"];
    printf("T3 step=create kind=%s class=%s size=%zu\n", kind, class_getName(object_getClass(obj)), class_getInstanceSize(object_getClass(obj)));
    if (!obj) { printf("T3_FATAL class_not_found kind=%s\n", kind); return 3; }   /* R5: AppKit must be loaded */

    id ident = nil;
    if (tracked) {
        TrackedID *t = [TrackedID trackedWithTag: 1];
        [obj setIdentifier: t];
        [t release];          /* the object now holds the only reference */
        ident = t;
    } else if (isString) {
        NSMutableString *m = [[NSMutableString alloc] initWithFormat: @"t3-%s-identifier-%d", kind, 4242];
        [obj setIdentifier: m];
        [m release];
        ident = identIvar(obj);
    }
    printf("T3 step=set ident=%s ivar_is_ident=%d ident_rc=%ld\n", identKind, identIvar(obj) == ident, rcOf(ident, tracked));

    id copies[8] = { nil };
    for (int i = 0; i < ncopies; i++) {
        copies[i] = [obj copy];
        id ci = identIvar(copies[i]);
        printf("T3 step=copy i=%d copy_ivar_same_ptr=%d copy_ivar_null=%d ident_rc=%ld\n", i, ci == ident, ci == nil, rcOf(ident, tracked));
    }

    /* destruction order */
    id seq[9];
    const char *names[9];
    int n = 0;
    char nb[8][16];
    if (!strcmp(order, "of")) { seq[n] = obj; names[n++] = "original"; }
    for (int i = 0; i < ncopies; i++) { snprintf(nb[i], sizeof nb[i], "copy%d", i); seq[n] = copies[i]; names[n++] = nb[i]; }
    if (strcmp(order, "of")) { seq[n] = obj; names[n++] = "original"; }

    int dangling = 0;
    for (int k = 0; k < n; k++) {
        printf("T3 step=release who=%s begin\n", names[k]);
        [seq[k] release];
        int dead = tracked && ((TrackedID *) ident)->dead;
        printf("T3 step=release who=%s done ident_dead=%d ident_rc=%ld double_release=%d\n", names[k], dead, tracked ? rcOf(ident, 1) : -2L, gDoubleRelease);
        for (int j = k + 1; j < n; j++) {           /* survivors: does their ivar point to a dead identifier? */
            int d = tracked && identIvar(seq[j]) == ident && ((TrackedID *) ident)->dead;
            dangling += d;
            printf("T3 check survivor=%s ivar_is_ident=%d points_to_dead=%d\n", names[j], identIvar(seq[j]) == ident, d);
        }
    }
    printf("T3_RESULT kind=%s ident=%s copies=%d order=%s dealloc_count=%d double_release=%d retain_after_dealloc=%d dangling_seen=%d final_rc=%ld\n",
           kind, identKind, ncopies, order, gDealloc, gDoubleRelease, gRetainAfterDealloc, dangling, tracked ? rcOf(ident, 1) : -2L);
    return 0;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
#if __OBJC2__
    const int objc2 = 1;
#else
    const int objc2 = 0;
#endif
    printf("T3_ABI pointer_bits=%zu objc2=%d scribble_env=%s\n", sizeof(void *) * 8, objc2, getenv("MallocScribble") ? getenv("MallocScribble") : "-");
    int app = argc > 1 && !strcmp(argv[argc - 1], "app");
    if (app)
        argc--;
    int rc = 2;
    @autoreleasepool {
        if (app) {
            printf("T3_STEP sharedApplication begin\n");
            [objc_getClass("NSApplication") sharedApplication];
            printf("T3_STEP sharedApplication done\n");
        }
        if (argc == 2 && !strcmp(argv[1], "selftest")) {
            TrackedID *t = [TrackedID trackedWithTag: 9];
            [t retain];
            [t release];
            [t release];
            [t release];          /* one release too many */
            printf("T3_RESULT kind=selftest ident=tracked copies=0 order=- dealloc_count=%d double_release=%d retain_after_dealloc=%d dangling_seen=0 final_rc=%ld\n",
                   gDealloc, gDoubleRelease, gRetainAfterDealloc, rcOf(t, 1));
            rc = 0;
        } else if (argc == 2 && !strcmp(argv[1], "strselftest")) {
            NSMutableString *m = [[NSMutableString alloc] initWithFormat: @"t3-selftest-%d", 4242];
            NSString *s = [m copy];
            [m release];
            printf("T3 step=strselftest first_release\n");
            [s release];
            printf("T3 step=strselftest second_release\n");
            [s release];          /* one release too many */
            printf("T3_RESULT kind=strselftest survived=1\n");
            rc = 0;
        } else if (argc == 5) {
            int nc = atoi(argv[3]);
            if (nc >= 0 && nc <= 8 && (!strcmp(argv[1], "cell") || !strcmp(argv[1], "menu"))
                && (!strcmp(argv[2], "tracked") || !strcmp(argv[2], "string") || !strcmp(argv[2], "nil"))
                && (!strcmp(argv[4], "cf") || !strcmp(argv[4], "of")))
                rc = scenario(argv[1], argv[2], nc, argv[4]);
        }
        printf("T3_STEP pool_drain\n");
    }
    if (rc == 2) {
        fprintf(stderr, "usage: coco-mem cell|menu tracked|string|nil COPIES cf|of [app] | selftest | strselftest\n");
        return 2;
    }
    printf("T3_END\n");
    return 0;
}
