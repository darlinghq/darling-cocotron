/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSPasteboard and CoreFoundation's pasteboard are two views of the same boards: what NSPasteboard writes
 * can be read with CFPasteboard (the layer the Pasteboard Manager sits on too) and the other way round, change
 * counts are shared, promises made through NSPasteboard are kept for readers of either kind, and a second
 * process sees the same data and gets promises kept by the first one. Only private (unique) boards are used,
 * and no window server is needed: the test must not create an NSApplication, since a process that has one
 * answers promise requests of other processes on its main thread, which this test blocks while the child runs.
 * Darling only: the CFPasteboard functions used here are Darling's private interface.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/wait.h>

extern char **environ;

// CoreFoundation's private pasteboard interface (CoreFoundation/CFPasteboard_Private.h), the part this test uses.
typedef struct __CFPasteboard *CFPasteboardRef;
typedef uint64_t CFPasteboardItemID;
typedef int32_t CFPasteboardStatus;
enum { kPBSuccess = 0, kPBNotOwner = 4 };
extern CFPasteboardRef CFPasteboardCreate(CFAllocatorRef allocator, CFStringRef name);
extern CFPasteboardRef CFPasteboardCreateUnique(CFAllocatorRef allocator);
extern CFStringRef CFPasteboardCopyName(CFPasteboardRef pasteboard);
extern CFIndex CFPasteboardGetChangeCount(CFPasteboardRef pasteboard);
extern CFIndex CFPasteboardBeginGeneration(CFPasteboardRef pasteboard);
extern CFPasteboardStatus CFPasteboardGetItemCount(CFPasteboardRef pasteboard, CFIndex *count);
extern CFPasteboardStatus CFPasteboardGetItemAtIndex(CFPasteboardRef pasteboard, CFIndex index, CFPasteboardItemID *item);
extern CFPasteboardStatus CFPasteboardAddItem(CFPasteboardRef pasteboard, CFPasteboardItemID *item);
extern CFPasteboardStatus CFPasteboardCopyFlavorsForItem(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFArrayRef *flavors);
extern CFPasteboardStatus CFPasteboardGetDataFlags(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, uint32_t *flags);
extern Boolean CFPasteboardIsDataPromised(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor);
extern CFPasteboardStatus CFPasteboardCopyData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFDataRef *data);
extern CFPasteboardStatus CFPasteboardSetData(CFPasteboardRef pasteboard, CFPasteboardItemID item, CFStringRef flavor, CFDataRef data, uint32_t flags);

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s (line %d)\n", msg, __LINE__); failures++; } } while (0)

@interface Owner : NSObject <NSPasteboardTypeOwner> {
@public
    int provided;
    int changedOwner;
    NSString *text;
}
@end

@implementation Owner
- (void) pasteboard: (NSPasteboard *) sender provideDataForType: (NSPasteboardType) type {
    provided++;
    [sender setData: [text dataUsingEncoding: NSUTF8StringEncoding] forType: type];
}
- (void) pasteboardChangedOwner: (NSPasteboard *) sender {
    changedOwner++;
}
@end

// The data of the first item's flavor read with CFPasteboard.
static NSData *cfData(CFPasteboardRef cf, CFIndex index, NSString *type) {
    CFPasteboardItemID item;
    CFDataRef data = NULL;
    if (CFPasteboardGetItemAtIndex(cf, index, &item) != kPBSuccess)
        return nil;
    if (CFPasteboardCopyData(cf, item, (CFStringRef) type, &data) != kPBSuccess || data == NULL)
        return nil;
    return [(NSData *) data autorelease];
}

static NSArray *cfFlavors(CFPasteboardRef cf, CFIndex index) {
    CFPasteboardItemID item;
    CFArrayRef flavors = NULL;
    if (CFPasteboardGetItemAtIndex(cf, index, &item) != kPBSuccess ||
        CFPasteboardCopyFlavorsForItem(cf, item, &flavors) != kPBSuccess)
        return nil;
    return [(NSArray *) flavors autorelease];
}

// An application's subclass of NSPasteboard declares ivars of its own. On the legacy ABI (i386) they sit right
// after Apple's instance size, so NSPasteboard's own state must not be stored beyond it: the subclass's ivars
// and the pasteboard have to survive each other.
@interface NSPasteboard (CFBacked)
- (id) _initWithCFPasteboard: (CFPasteboardRef) cf unique: (BOOL) unique;
@end

@interface SubPasteboard : NSPasteboard {
    int ownCounter;
    id ownObject;
    double ownValue;
}
- (void) setOwn;
- (BOOL) ownIntact;
@end

@implementation SubPasteboard
- (void) setOwn {
    ownCounter = 0x5a5a;
    ownObject = [@"own" retain];
    ownValue = 2.5;
}
- (BOOL) ownIntact {
    return ownCounter == 0x5a5a && [ownObject isEqual: @"own"] && ownValue == 2.5;
}
- (void) dealloc {
    [ownObject release];
    [super dealloc];
}
@end

static void testSubclass(void) {
    CFPasteboardRef cf = CFPasteboardCreateUnique(NULL);
    CHECK(cf != NULL, "unique CF pasteboard");
    SubPasteboard *sub = [[SubPasteboard alloc] _initWithCFPasteboard: cf unique: NO];
    [sub setOwn];
    CHECK([sub ownIntact], "own ivars set");
    CHECK([sub setString: @"in subclass" forType: NSPasteboardTypeString], "subclass writes");
    CHECK([[sub stringForType: NSPasteboardTypeString] isEqualToString: @"in subclass"], "subclass reads");
    CHECK([sub changeCount] == CFPasteboardGetChangeCount(cf), "subclass sees the change count");
    CHECK([sub ownIntact], "own ivars survive the pasteboard state");
    [sub setOwn];
    CHECK([[sub stringForType: NSPasteboardTypeString] isEqualToString: @"in subclass"], "the pasteboard survives own ivars");
    [sub release];
    CFRelease(cf);
}

static void testNSToCF(void) {
    NSPasteboard *ns = [NSPasteboard pasteboardWithUniqueName];
    CHECK(ns != nil, "unique pasteboard");
    CFPasteboardRef cf = CFPasteboardCreate(NULL, (CFStringRef) [ns name]);
    CHECK(cf != NULL, "CF reaches the pasteboard by its name");

    [ns declareTypes: @[ NSPasteboardTypeString ] owner: nil];
    [ns setString: @"héllo" forType: NSPasteboardTypeString];
    CFIndex count = 0;
    CHECK(CFPasteboardGetItemCount(cf, &count) == kPBSuccess && count == 1, "one item");
    CHECK([cfFlavors(cf, 0) containsObject: @"public.utf8-plain-text"], "flavor is the UTI");
    CHECK([[[[NSString alloc] initWithData: cfData(cf, 0, @"public.utf8-plain-text") encoding: NSUTF8StringEncoding] autorelease]
            isEqualToString: @"héllo"], "CF reads what NSPasteboard wrote");
    CHECK([ns changeCount] == CFPasteboardGetChangeCount(cf), "one change count");

    NSInteger before = [ns changeCount];
    [ns setString: @"again" forType: NSPasteboardTypeString];
    CHECK([ns changeCount] == before, "setting data again does not change the count");
    CHECK([ns clearContents] == before + 1 && CFPasteboardGetChangeCount(cf) == before + 1, "clearing counts once for both");
    CFIndex empty = -1;
    CHECK(CFPasteboardGetItemCount(cf, &empty) == kPBSuccess && empty == 0, "cleared for CF too");

    // The process that began a generation adds to it without a change of its own.
    before = [ns changeCount];
    CHECK([ns setString: @"implicit" forType: NSPasteboardTypeString], "a write after the clear");
    CHECK([ns changeCount] == before, "a write by the owner of the generation is no change");
    CHECK([[ns stringForType: NSStringPboardType] isEqualToString: @"implicit"], "the 10.0 name reaches the UTI flavor");

    CFRelease(cf);
    [ns releaseGlobally];
}

static void testCFToNS(void) {
    CFPasteboardRef cf = CFPasteboardCreateUnique(NULL);
    NSString *name = [(NSString *) CFPasteboardCopyName(cf) autorelease];
    NSPasteboard *ns = [NSPasteboard pasteboardWithName: name];
    CHECK([[ns name] isEqualToString: name], "same name");
    CHECK([NSPasteboard pasteboardWithName: name] == ns, "one object per name");

    CFIndex count = CFPasteboardBeginGeneration(cf);
    CHECK(count > 0 && [ns changeCount] == count, "NSPasteboard sees the CF change count");
    CFPasteboardItemID item;
    CHECK(CFPasteboardAddItem(cf, &item) == kPBSuccess, "add item");
    CFDataRef data = (CFDataRef) [@"from carbon" dataUsingEncoding: NSUTF8StringEncoding];
    CHECK(CFPasteboardSetData(cf, item, CFSTR("public.utf8-plain-text"), data, 0) == kPBSuccess, "set");
    CHECK([[ns types] containsObject: NSPasteboardTypeString] && [[ns types] containsObject: NSStringPboardType], "types, both spellings");
    CHECK([[ns stringForType: NSPasteboardTypeString] isEqualToString: @"from carbon"], "NSPasteboard reads what CF wrote");
    CHECK([[ns pasteboardItems] count] == 1, "one item");

    // Both layers are one process as far as the generation goes: a write by NSPasteboard adds to it.
    CHECK([ns setString: @"ns" forType: NSPasteboardTypeString], "write over");
    CHECK([ns changeCount] == count, "the generation is the same");
    CFPasteboardItemID first;
    CHECK(CFPasteboardGetItemAtIndex(cf, 0, &first) == kPBSuccess && first == item, "in the same item");
    CHECK([[[[NSString alloc] initWithData: cfData(cf, 0, @"public.utf8-plain-text") encoding: NSUTF8StringEncoding] autorelease]
            isEqualToString: @"ns"], "and CF reads the new data");
    CFRelease(cf);
    [ns releaseGlobally];
}

static void testItems(void) {
    NSPasteboard *ns = [NSPasteboard pasteboardWithUniqueName];
    CFPasteboardRef cf = CFPasteboardCreate(NULL, (CFStringRef) [ns name]);
    NSPasteboardItem *a = [[[NSPasteboardItem alloc] init] autorelease];
    NSPasteboardItem *b = [[[NSPasteboardItem alloc] init] autorelease];
    [a setString: @"first" forType: NSPasteboardTypeString];
    [b setString: @"second" forType: NSPasteboardTypeString];
    [b setString: @"<b>second</b>" forType: NSPasteboardTypeHTML];
    [ns clearContents];
    CHECK(([ns writeObjects: @[ a, b ]]), "write two items");

    CFIndex count = 0;
    CHECK(CFPasteboardGetItemCount(cf, &count) == kPBSuccess && count == 2, "CF has two items");
    CHECK([cfFlavors(cf, 1) containsObject: @"public.html"], "second item's flavors");
    CHECK([[[[NSString alloc] initWithData: cfData(cf, 1, @"public.utf8-plain-text") encoding: NSUTF8StringEncoding] autorelease]
            isEqualToString: @"second"], "second item's data");

    // Another reference of the process sees the items as stored.
    NSPasteboard *other = [NSPasteboard pasteboardWithName: [ns name]];
    CHECK(other == ns, "same object");
    CHECK([[ns pasteboardItems] count] == 2 && [[ns pasteboardItems] objectAtIndex: 0] == a, "the items written are the items read");

    // A pasteboard item made from the stored data (what another process sees).
    NSArray *read = [ns readObjectsForClasses: @[ [NSString class] ] options: nil];
    CHECK([read count] == 2 && [[read objectAtIndex: 1] isEqualToString: @"second"], "objects read from both items");

    // A change leaves the pasteboard with no items.
    [ns clearContents];
    CFIndex none = -1;
    CHECK([[ns pasteboardItems] count] == 0 && CFPasteboardGetItemCount(cf, &none) == kPBSuccess && none == 0, "no items after a clear");
    CFRelease(cf);
    [ns releaseGlobally];
}

static void testPromises(void) {
    NSPasteboard *ns = [NSPasteboard pasteboardWithUniqueName];
    CFPasteboardRef cf = CFPasteboardCreate(NULL, (CFStringRef) [ns name]);
    Owner *owner = [[[Owner alloc] init] autorelease];
    owner->text = @"promised";
    [ns declareTypes: @[ NSPasteboardTypeString ] owner: owner];
    CHECK(owner->provided == 0, "nothing provided yet");

    CFPasteboardItemID item;
    CHECK(CFPasteboardGetItemAtIndex(cf, 0, &item) == kPBSuccess, "item");
    CHECK(CFPasteboardIsDataPromised(cf, item, CFSTR("public.utf8-plain-text")), "CF sees the promise");
    uint32_t flags = 99;
    CHECK(CFPasteboardGetDataFlags(cf, item, CFSTR("public.utf8-plain-text"), &flags) == kPBSuccess && flags == 0,
          "an NSPasteboard promise is not flagged Promised (macOS reads 0)");
    CHECK([[cfFlavors(cf, 0) firstObject] isEqualToString: @"public.utf8-plain-text"], "flavor listed while promised");

    CHECK([cfData(cf, 0, @"public.utf8-plain-text") length] == 8 && owner->provided == 1, "a CF read asks the owner once");
    CHECK([[ns stringForType: NSPasteboardTypeString] isEqualToString: @"promised"] && owner->provided == 1, "NSPasteboard reads the kept promise");
    CHECK(!CFPasteboardIsDataPromised(cf, item, CFSTR("public.utf8-plain-text")), "no longer promised");

    CHECK(owner->changedOwner == 0, "owner still current");
    [ns clearContents];
    CHECK(owner->changedOwner == 1, "owner is told when the pasteboard gets other contents");

    // Declared without an owner: listed, no data.
    [ns declareTypes: @[ NSPasteboardTypeString, NSPasteboardTypePNG ] owner: nil];
    CHECK([[ns types] containsObject: NSPasteboardTypePNG] && [ns dataForType: NSPasteboardTypePNG] == nil, "declared without owner");
    CHECK([ns setData: [NSData dataWithBytes: "x" length: 1] forType: NSPasteboardTypePNG] && [[ns dataForType: NSPasteboardTypePNG] length] == 1, "then set");
    CFRelease(cf);
    [ns releaseGlobally];
}

static int runChild(const char *name) {
    @autoreleasepool {
        NSPasteboard *ns = [NSPasteboard pasteboardWithName: [NSString stringWithUTF8String: name]];
        int failed = 0;
        // data the parent wrote, and a promise the parent keeps
        if (![[ns stringForType: NSPasteboardTypeString] isEqualToString: @"promised"]) {
            printf("child: promise not kept (%s)\n", [[ns stringForType: NSPasteboardTypeString] UTF8String]);
            failed = 1;
        }
        if (![[ns types] containsObject: NSPasteboardTypeRTF] || [[ns dataForType: NSPasteboardTypeRTF] length] != 3) {
            printf("child: plain data not seen\n");
            failed = 1;
        }
        // and a write of its own
        [ns declareTypes: @[ NSPasteboardTypeString ] owner: nil];
        [ns setString: @"from child" forType: NSPasteboardTypeString];
        return failed;
    }
}

static void testAnotherProcess(const char *self) {
    NSPasteboard *ns = [NSPasteboard pasteboardWithUniqueName];
    Owner *owner = [[[Owner alloc] init] autorelease];
    owner->text = @"promised";
    [ns declareTypes: @[ NSPasteboardTypeString, NSPasteboardTypeRTF ] owner: owner];
    CHECK([ns setData: [NSData dataWithBytes: "rtf" length: 3] forType: NSPasteboardTypeRTF], "plain data");
    NSInteger count = [ns changeCount];

    char *argv[] = { (char *) self, "child", (char *) [[ns name] UTF8String], NULL };
    pid_t pid;
    int status = -1;
    if (posix_spawn(&pid, self, NULL, NULL, argv, environ) != 0) {
        CHECK(0, "spawn the child");
        return;
    }
    waitpid(pid, &status, 0);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0, "the other process read the data and the promise");
    CHECK(owner->provided == 1, "the promise was kept once, for the other process");
    CHECK([ns changeCount] == count + 1, "the other process's write is a change here");
    CHECK([[ns stringForType: NSPasteboardTypeString] isEqualToString: @"from child"], "and its data is read here");
    CHECK(owner->changedOwner == 1, "the owner is told that another process took the pasteboard");
    [ns releaseGlobally];
}

int main(int argc, char **argv) {
    if (argc == 3 && strcmp(argv[1], "child") == 0)
        return runChild(argv[2]);
    @autoreleasepool {
        testNSToCF();
        testSubclass();
        testCFToNS();
        testItems();
        testPromises();
        testAnotherProcess(argv[0]);
    }
    if (failures)
        return 1;
    puts("pasteboard over cfpasteboard: PASS");
    return 0;
}
