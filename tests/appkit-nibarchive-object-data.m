// Authored from the archive layout in NSNibArchive.m and the fields consumed by
// NSIBObjectData.m. No imported application archive is used by this test.
#import <AppKit/AppKit.h>
#import "../AppKit/nib.subproj/NSNibArchive.h"
#include <stdint.h>
#include <stdio.h>

@interface AuthoredNibObject : NSObject <NSCoding>
@end
@implementation AuthoredNibObject
- (id)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}
@end

static void varint(NSMutableData *data, uint32_t value) {
    do {
        uint8_t byte = value & 0x7f;
        value >>= 7;
        if (!value) byte |= 0x80;
        [data appendBytes:&byte length:1];
    } while (value);
}
static void word(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = {value, value >> 8, value >> 16, value >> 24};
    [data appendBytes:bytes length:4];
}
static void object(NSMutableData *data, uint32_t cls, uint32_t first, uint32_t count) {
    varint(data, cls); varint(data, first); varint(data, count);
}
static void reference(NSMutableData *data, uint32_t key, uint32_t target) {
    varint(data, key);
    uint8_t type = 10; [data appendBytes:&type length:1]; word(data, target);
}
static NSData *fixture(void) {
    NSMutableData *objects = [NSMutableData data];
    object(objects, 0, 0, 1); // root: IB.objectdata
    object(objects, 1, 1, 5); // NSIBObjectData: named fields
    object(objects, 0, 6, 0); // File's Owner
    object(objects, 2, 6, 1); // top-level objects
    object(objects, 2, 7, 1); // corresponding parents
    object(objects, 2, 8, 0); // connections
    object(objects, 0, 8, 0); // top-level NSObject
    NSArray *names = @[@"IB.objectdata", @"NSRoot", @"NSObjectsKeys",
                       @"NSObjectsValues", @"NSConnections", @"NSNextOid",
                       @"UINibEncoderEmptyKey"];
    NSMutableData *keys = [NSMutableData data];
    for (NSString *name in names) {
        NSData *bytes = [name dataUsingEncoding:NSUTF8StringEncoding];
        varint(keys, [bytes length]); [keys appendData:bytes];
    }
    NSMutableData *values = [NSMutableData data];
    reference(values, 0, 1); reference(values, 1, 2); reference(values, 2, 3);
    reference(values, 3, 4); reference(values, 4, 5);
    varint(values, 5); uint8_t type = 2;
    [values appendBytes:&type length:1]; word(values, 17);
    reference(values, 6, 6); reference(values, 6, 2);
    NSMutableData *classes = [NSMutableData data];
    for (NSString *name in @[@"AuthoredNibObject", @"NSIBObjectData", @"NSArray"]) {
        NSData *bytes = [name dataUsingEncoding:NSUTF8StringEncoding];
        varint(classes, [bytes length] + 1); varint(classes, 0);
        [classes appendData:bytes]; uint8_t zero = 0;
        [classes appendBytes:&zero length:1];
    }
    NSMutableData *archive = [NSMutableData dataWithBytes:"NIBArchive" length:10];
    word(archive, 1); word(archive, 1);
    word(archive, 7); word(archive, 50);
    word(archive, [names count]); word(archive, 50 + [objects length]);
    word(archive, 8); word(archive, 50 + [objects length] + [keys length]);
    word(archive, 3); word(archive, 50 + [objects length] + [keys length] + [values length]);
    [archive appendData:objects]; [archive appendData:keys];
    [archive appendData:values]; [archive appendData:classes];
    return archive;
}

int main(void) {
    @autoreleasepool {
        NSData *input = fixture();
        NSData *converted = NSKeyedArchiveDataFromNibArchiveData(input);
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:converted
                options:0 format:NULL error:NULL];
        NSDictionary *metadata = [plist[@"$objects"] objectAtIndex:2];
        if (metadata[@"NSRoot"] == nil || metadata[@"NSObjectsKeys"] == nil ||
                metadata[@"NSConnections"] == nil || [metadata[@"NSNextOid"] intValue] != 17 ||
                metadata[@"NS.keys"] != nil) {
            fprintf(stderr, "FAIL: NSIBObjectData lost its named coder fields\n");
            return 1;
        }
        [NSApplication sharedApplication];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"authored-object-data-%d.nib", getpid()]];
        if (![input writeToFile:path atomically:NO]) return 1;
        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        NSArray *top = nil;
        BOOL loaded = [nib instantiateNibWithOwner:nil topLevelObjects:&top];
        if (!loaded || [top count] != 1 || [top[0] class] != [AuthoredNibObject class]) {
            fprintf(stderr, "FAIL: authored NIBArchive did not instantiate its top-level object\n");
            return 1;
        }
        puts("PASS: NIBArchive metadata retains named fields and instantiates top-level objects");
    }
    return 0;
}
