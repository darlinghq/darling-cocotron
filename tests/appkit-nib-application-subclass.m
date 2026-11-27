// Copyright (C) 2026 Lubos Dolezel
//
// A custom object of a nib whose class is NSApplication or a subclass of it stands for the application
// object: loading the nib does not make a second application, it hands out the shared one, and the shared
// application is an instance of the subclass when the nib is what creates it. The nib is built with
// NSKeyedArchiver from stand-in classes whose class names are then rewritten to the nib classes (the way
// appkit-nib-custom-object-instances does it). Run with "create" to let the nib create the application.
// Interface Builder's "Application" placeholder is such an object: it stands for the shared application,
// whose class the nib may name as a subclass. Only Darling's NSNib can load the hand-made nib (the system one
// wants more keys), so there is no black-box observation of the system for this test.
#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

static int applicationsAllocated;

@interface SubclassApplication : NSApplication
@end
@implementation SubclassApplication
+ (id) allocWithZone: (NSZone *) zone
{
    applicationsAllocated++;
    return [super allocWithZone: zone];
}
@end

@interface StandInPlaceholder : NSObject <NSCoding>
@property (copy) NSString *className;
@end
@implementation StandInPlaceholder
- (void) encodeWithCoder: (NSCoder *) coder { [coder encodeObject: self.className forKey: @"NSClassName"]; }
- (id) initWithCoder: (NSCoder *) coder { return [self init]; }
@end

@interface StandInObjectData : NSObject <NSCoding>
@property (retain) id root;
@property (retain) NSArray *objects;
@end
@implementation StandInObjectData
- (void) encodeWithCoder: (NSCoder *) coder
{
    NSMutableArray *parents = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.objects.count; i++)
        [parents addObject: self.root];
    [coder encodeObject: self.root forKey: @"NSRoot"];
    [coder encodeObject: self.objects forKey: @"NSObjectsKeys"];
    [coder encodeObject: parents forKey: @"NSObjectsValues"];
}
- (id) initWithCoder: (NSCoder *) coder { return [self init]; }
@end

static NSNib *makeNib(NSString *className)
{
    StandInObjectData *data = [[StandInObjectData new] autorelease];
    StandInPlaceholder *item = [[StandInPlaceholder new] autorelease];
    item.className = className;
    data.root = [NSMutableArray array];
    data.objects = @[ item ];
    NSMutableData *archive = [NSMutableData data];
    NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initForWritingWithMutableData: archive] autorelease];
    [archiver encodeObject: data forKey: @"IB.objectdata"];
    [archiver finishEncoding];
    NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData: archive
                                                                           options: NSPropertyListMutableContainersAndLeaves
                                                                            format: NULL error: NULL];
    NSDictionary *renames = @{ @"StandInPlaceholder": @"NSCustomObject", @"StandInObjectData": @"NSIBObjectData" };
    for (id object in plist[@"$objects"]) {
        if (![object isKindOfClass: [NSMutableDictionary class]] || renames[object[@"$classname"]] == nil)
            continue;
        object[@"$classes"] = @[ renames[object[@"$classname"]], @"NSObject" ];
        object[@"$classname"] = renames[object[@"$classname"]];
    }
    NSData *bytes = [NSPropertyListSerialization dataWithPropertyList: plist format: NSPropertyListBinaryFormat_v1_0
                                                              options: 0 error: NULL];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent: [NSString stringWithFormat: @"app-subclass-%d.nib", getpid()]];
    [bytes writeToFile: path atomically: NO];
    NSNib *nib = [[[NSNib alloc] initWithContentsOfURL: [NSURL fileURLWithPath: path]] autorelease];
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    return nib;
}

int main(int argc, char **argv)
{
    BOOL create = argc > 1 && strcmp(argv[1], "create") == 0;
    @autoreleasepool {
        if (!create)
            [NSApplication sharedApplication];
        NSApplication *before = NSApp;
        NSMutableArray *topLevel = [NSMutableArray array];
        NSException *raised = nil;
        BOOL loaded = NO;
        @try {
            loaded = [makeNib(@"SubclassApplication") instantiateNibWithExternalNameTable: @{ NSNibTopLevelObjects: topLevel }];
        } @catch (NSException *e) {
            raised = e;
        }
        expect(raised == nil, [NSString stringWithFormat: @"loading the nib raises nothing (%@)", raised]);
        expect(loaded, @"the nib loads");
        expect(NSApp != nil, @"the shared application exists");
        if (create) {
            expect(before == nil, @"the nib is what creates the application");
            expect([NSApp isKindOfClass: [SubclassApplication class]], @"the application is an instance of the subclass");
        } else {
            expect(NSApp == before, @"the application is the one that exists");
        }
        expect(applicationsAllocated <= 1, [NSString stringWithFormat: @"at most one application object was allocated (%d)", applicationsAllocated]);
        if (loaded && raised == nil) {
            BOOL gotApplication = NO;
            for (id object in topLevel)
                gotApplication |= (object == NSApp);
            expect(gotApplication, @"the nib hands out the shared application as its object");
        }
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
