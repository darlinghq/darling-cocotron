// NSNibExternalObjectPlaceholder: a nib placeholder is replaced, everywhere it is referenced, by
// the object the loader passes in the external name table under the placeholder's identifier.
// The nib file is built with NSKeyedArchiver from stand-in classes whose class names are then
// rewritten to the nib classes.
#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

@interface TestPlaceholder : NSObject <NSCoding>
@property (copy) NSString *identifier;
@end
@implementation TestPlaceholder
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:self.identifier forKey:@"NSExternalObjectPlaceholderIdentifier"]; }
- (id)initWithCoder:(NSCoder *)coder { return [self init]; }
@end

// Encodes the NSIBObjectData keys the loader needs for top-level objects.
@interface TestObjectData : NSObject <NSCoding>
@property (retain) id root;
@property (retain) NSArray *objects;
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
}
- (id)initWithCoder:(NSCoder *)coder { return [self init]; }
@end

static NSData *nibData(NSString *identifier)
{
    TestPlaceholder *placeholder = [[TestPlaceholder new] autorelease];
    placeholder.identifier = identifier;
    TestObjectData *data = [[TestObjectData new] autorelease];
    data.root = [NSMutableArray array];
    data.objects = @[placeholder, @[placeholder, placeholder]];

    NSMutableData *archive = [NSMutableData data];
    NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initForWritingWithMutableData:archive] autorelease];
    [archiver encodeObject:data forKey:@"IB.objectdata"];
    [archiver finishEncoding];

    NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:archive
        options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
    NSDictionary *renames = @{@"TestPlaceholder": @"NSNibExternalObjectPlaceholder", @"TestObjectData": @"NSIBObjectData"};
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

static NSNib *nibWithPlaceholder(NSString *identifier)
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"external-%@-%d.nib", identifier, getpid()]];
    expect([nibData(identifier) writeToFile:path atomically:NO], @"nib written");
    NSNib *nib = [[[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]] autorelease];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    return nib;
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSObject *external = [[NSObject new] autorelease];

        NSNib *nib = nibWithPlaceholder(@"TestExternal");
        NSMutableArray *topLevel = [NSMutableArray array];
        BOOL loaded = [nib instantiateNibWithExternalNameTable:@{@"TestExternal": external, NSNibTopLevelObjects: topLevel}];
        expect(loaded, @"nib with a placeholder loads");
        expect([topLevel indexOfObjectIdenticalTo:external] == NSNotFound, @"an external object is not a top-level object of the nib");

        NSArray *holder = nil;
        for (id object in topLevel)
            if ([object isKindOfClass:[NSArray class]])
                holder = object;
        expect(holder.count == 2 && holder[0] == external && holder[1] == external,
               @"every reference to the placeholder gets the external object");

        NSNib *missing = nibWithPlaceholder(@"NotInTable");
        BOOL raised = NO;
        @try
        {
            [missing instantiateNibWithExternalNameTable:@{@"TestExternal": external}];
        }
        @catch (NSException *e)
        {
            raised = [e.name isEqualToString:NSInternalInconsistencyException] && [e.reason containsString:@"NotInTable"];
        }
        expect(raised, @"a placeholder missing from the name table raises");
        NSMutableArray *again = [NSMutableArray array];
        expect([missing instantiateNibWithExternalNameTable:@{@"NotInTable": external, NSNibTopLevelObjects: again}] && again.count == 1,
               @"the nib loads again after a failed load");

        NSLog(@"PASS: NSNibExternalObjectPlaceholder");
    }
    return 0;
}
