// A custom object in a nib is instantiated once, however the NSKeyedUnarchiver behaves.
//
// The nib loader replaces each NSCustomObject placeholder by an instance while it decodes, and must
// forget the placeholder afterwards. It used to learn of the replacement only from the unarchiver
// delegate message unarchiver:willReplaceObject:withObject:, which the system NSKeyedUnarchiver does
// not send for replaceObject:withObject:. The loader then made a second instance for every
// placeholder, and the duplicates died with the NSNib. TextEdit's DocumentPropertiesPanelController
// removes its key-value observer in dealloc and registers it only in windowDidLoad, so the dead
// duplicate raised NSRangeException at launch. Terminal's nib has a placeholder of an NSApplication
// subclass; the second instance is refused by NSApplication's singleton check ("NSApplication is a
// singleton"). The test makes File's Owner that placeholder.
//
// Run with no argument (the platform's unarchiver) and with "silent-replace" (the unarchiver sends no
// delegate message from replaceObject:withObject:, as the system one). The nib is built with
// NSKeyedArchiver from stand-in classes whose class names are then rewritten to the nib classes.
//
// "silent-replace" keeps the platform unarchiver's remapping: after replaceObject:withObject: every
// later decode of the placeholder yields the replacement. The fix assumes the system unarchiver
// remaps too (a named custom object is decoded again from NSObjectsKeys after the name table loop;
// without the remap that loop would make a second instance). That was checked on the arm64e stage
// by counting instances created for TextEdit's nib, not by this test.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSString *const KeyPath = @"mainWindow.windowController.document";
static int created, deallocated, unregisteredRemovals;

// Same shape as TextEdit's panel controller: it starts observing only on demand, and always removes
// the observer on dealloc.
@interface PanelController : NSObject
- (void)startObserving;
@end

@implementation PanelController {
    BOOL _observing;
}
- (id)init
{
    if ((self = [super init])) created++;
    return self;
}
- (void)startObserving
{
    [NSApp addObserver:self forKeyPath:KeyPath options:0 context:NULL];
    _observing = YES;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {}
- (void)dealloc
{
    deallocated++;
    @try
    {
        [NSApp removeObserver:self forKeyPath:KeyPath];
        if (!_observing)
            unregisteredRemovals++;
    }
    @catch (NSException *e)
    {
        if (_observing)
            NSLog(@"FAIL: removing a registered observer raised %@", e.reason);
        else
            unregisteredRemovals++;
    }
    [super dealloc];
}
@end

static int applicationsAllocated;

@interface TestApplication : NSApplication
@end
@implementation TestApplication
+ (id)allocWithZone:(NSZone *)zone
{
    applicationsAllocated++;
    return [super allocWithZone:zone];
}
@end

@interface TestCustomPlaceholder : NSObject <NSCoding>
@property (copy) NSString *className;
@end
@implementation TestCustomPlaceholder
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:self.className forKey:@"NSClassName"]; }
- (id)initWithCoder:(NSCoder *)coder { return [self init]; }
@end

@interface TestObjectData : NSObject <NSCoding>
@property (retain) id root;
@property (retain) NSArray *objects;
@property (retain) NSArray *names;        // NSNamesValues
@property (retain) NSArray *namedObjects; // NSNamesKeys
@end
@implementation TestObjectData
- (void)encodeWithCoder:(NSCoder *)coder
{
    NSMutableArray *parents = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.objects.count; i++)
        [parents addObject:self.root];
    [coder encodeObject:self.root forKey:@"NSRoot"];
    [coder encodeObject:self.objects forKey:@"NSObjectsKeys"];
    [coder encodeObject:parents forKey:@"NSObjectsValues"];
    if (self.names.count > 0)
    {
        [coder encodeObject:self.namedObjects forKey:@"NSNamesKeys"];
        [coder encodeObject:self.names forKey:@"NSNamesValues"];
    }
}
- (id)initWithCoder:(NSCoder *)coder { return [self init]; }
@end

static TestCustomPlaceholder *placeholder(NSString *className)
{
    TestCustomPlaceholder *result = [[TestCustomPlaceholder new] autorelease];
    result.className = className;
    return result;
}

// A nib with that many PanelController placeholders, a named PanelController placeholder for each of
// names, and File's Owner a placeholder of ownerClass when that is given.
static NSData *nibData(NSUInteger placeholders, NSString *ownerClass, NSArray *names)
{
    TestObjectData *data = [[TestObjectData new] autorelease];
    NSMutableArray *objects = [NSMutableArray array];
    data.root = ownerClass != nil ? placeholder(ownerClass) : [NSMutableArray array];
    if (ownerClass != nil)
        [objects addObject:data.root];
    for (NSUInteger i = 0; i < placeholders; i++)
        [objects addObject:placeholder(@"PanelController")];
    NSMutableArray *named = [NSMutableArray array];
    for (NSString *name in names)
    {
        TestCustomPlaceholder *item = placeholder(@"PanelController");
        [objects addObject:item];
        [named addObject:item];
    }
    data.objects = objects;
    data.names = names;
    data.namedObjects = named;

    NSMutableData *archive = [NSMutableData data];
    NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initForWritingWithMutableData:archive] autorelease];
    [archiver encodeObject:data forKey:@"IB.objectdata"];
    [archiver finishEncoding];

    NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:archive
        options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
    NSDictionary *renames = @{@"TestCustomPlaceholder": @"NSCustomObject", @"TestObjectData": @"NSIBObjectData"};
    NSUInteger renamed = 0;
    for (id object in plist[@"$objects"])
    {
        if (![object isKindOfClass:[NSMutableDictionary class]] || renames[object[@"$classname"]] == nil)
            continue;
        object[@"$classes"] = @[renames[object[@"$classname"]], @"NSObject"];
        object[@"$classname"] = renames[object[@"$classname"]];
        renamed++;
    }
    expect(renamed == 2, @"archive has both stand-in classes");
    return [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}

static NSNib *makeNib(NSUInteger placeholders, NSString *ownerClass, NSArray *names)
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"custom-objects-%d.nib", getpid()]];
    expect([nibData(placeholders, ownerClass, names) writeToFile:path atomically:NO], @"nib written");
    NSNib *nib = [[[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]] autorelease];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    return nib;
}

// Makes -[NSKeyedUnarchiver replaceObject:withObject:] leave the delegate out, as the system one does.
static void silenceReplaceObjectDelegateMessage(void)
{
    Method method = class_getInstanceMethod([NSKeyedUnarchiver class], @selector(replaceObject:withObject:));
    expect(method != NULL, @"NSKeyedUnarchiver implements replaceObject:withObject:");
    IMP original = method_getImplementation(method);
    SEL selector = @selector(replaceObject:withObject:);
    method_setImplementation(method, imp_implementationWithBlock(^(NSKeyedUnarchiver *self_, id object, id replacement) {
        id delegate = [self_ delegate];
        [self_ setDelegate:nil];
        ((void (*)(id, SEL, id, id))original)(self_, selector, object, replacement);
        [self_ setDelegate:delegate];
    }));
}

int main(int argc, char **argv)
{
    BOOL silent = argc > 1 && strcmp(argv[1], "silent-replace") == 0;
    expect(argc == 1 || silent, @"usage: [silent-replace]");
    if (silent)
        silenceReplaceObjectDelegateMessage();

    @autoreleasepool
    {
        [NSApplication sharedApplication];

        // The key path itself works: a controller that registered can remove itself.
        PanelController *observer = [PanelController new];
        [observer startObserving];
        [observer release];
        expect(created == 1 && deallocated == 1 && unregisteredRemovals == 0, @"observer registered through NSApp removes cleanly");
        created = deallocated = 0;

        @autoreleasepool
        {
            NSMutableArray *topLevel = [NSMutableArray array];
            NSObject *owner = [[NSObject new] autorelease];
            NSObject *external = [[NSObject new] autorelease];
            // Two anonymous placeholders, one named (instantiated by the loader), one named
            // and supplied by the caller (replaced by `external`, never instantiated).
            NSNib *nib = makeNib(2, nil, @[@"Named Panel", @"Named External"]);
            expect([nib instantiateNibWithExternalNameTable:@{NSNibOwner: owner, @"Named External": external,
                                                              NSNibTopLevelObjects: topLevel}], @"nib loads");
            [topLevel retain];
            expect(topLevel.count == 3, [NSString stringWithFormat:@"the three custom objects are top-level objects, %lu are: %@", (unsigned long)topLevel.count, topLevel]);
            expect([topLevel indexOfObjectIdenticalTo:external] == NSNotFound, @"the external object is not a top-level object");
        }
        // The nib and its decoder are gone; the objects it handed out are still alive.
        expect(created == 3, [NSString stringWithFormat:@"each placeholder makes one instance, %d made", created]);
        expect(deallocated == 0, [NSString stringWithFormat:@"no instance of the nib dies with the nib, %d did", deallocated]);
        expect(unregisteredRemovals == 0, @"no never-registered controller was torn down");

        // File's Owner of an NSApplication subclass: the owner stands in, nothing is instantiated for it.
        @autoreleasepool
        {
            NSMutableArray *topLevel = [NSMutableArray array];
            NSNib *nib = makeNib(1, @"TestApplication", nil);
            NSException *raised = nil;
            @try
            {
                [nib instantiateNibWithExternalNameTable:@{NSNibOwner: NSApp, NSNibTopLevelObjects: topLevel}];
            }
            @catch (NSException *e)
            {
                raised = e;
            }
            expect(raised == nil, [NSString stringWithFormat:@"a nib whose File's Owner is an NSApplication subclass loads, raised %@", raised]);
            [topLevel retain];
        }
        expect(applicationsAllocated == 0, [NSString stringWithFormat:@"File's Owner is not instantiated, %d allocated", applicationsAllocated]);

        NSLog(@"PASS: NSNib custom object instances%@", silent ? @" (silent replaceObject:withObject:)" : @"");
    }
    return 0;
}
