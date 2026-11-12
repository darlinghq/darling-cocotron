// Copyright (C) 2026 Lubos Dolezel
//
// Keyed-archive round trips for the nib decoding paths:
//  - NSView canDrawConcurrently is stored and archived
//  - NSFont archives and unarchives with secure coding
//  - a decoded NSTextStorage keeps a mutable string
//  - NSCustomView decodes as a plain NSView when its class is unknown, not an
//    NSView subclass, or its initWithFrame: returns nil
//  - the base NSNibConnector has nothing to connect and does not raise
//  - NSFontEffectsBox exists at run time as an NSBox subclass
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// Stands in for NSCustomView in an archive: the archive records the class name
// NSCustomView, so decoding runs the real NSCustomView -initWithCoder:.
@interface CustomViewStandIn : NSObject <NSCoding> {
    NSString *_viewClassName;
}
@property(copy) NSString *viewClassName;
@end
@implementation CustomViewStandIn
@synthesize viewClassName = _viewClassName;
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.viewClassName forKey:@"NSClassName"];
    [coder encodeRect:NSMakeRect(1, 2, 30, 40) forKey:@"NSFrame"];
    [coder encodeInt:0x12 forKey:@"NSvFlags"];
}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

// Stands in for NSTextStorage the same way, carrying the string key a nib or
// archive stores it under.
@interface TextStorageStandIn : NSObject <NSCoding>
@end
@implementation TextStorageStandIn
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:@"abc" forKey:@"NSString"]; }
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

@interface NotAViewClass : NSObject
- (id)initWithFrame:(NSRect)frame;
@end
@implementation NotAViewClass
- (id)initWithFrame:(NSRect)frame { return self; }
@end

@interface NilFrameView : NSView
@end
@implementation NilFrameView
- (id)initWithFrame:(NSRect)frame { [self release]; return nil; }
@end

static id decodeCustomView(NSString *className) {
    CustomViewStandIn *standIn = [CustomViewStandIn new];
    standIn.viewClassName = className;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver setClassName:@"NSCustomView" forClass:[CustomViewStandIn class]];
    [archiver encodeObject:standIn forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    return [unarchiver decodeObjectForKey:@"root"];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        CHECK(![view canDrawConcurrently]);
        [view setCanDrawConcurrently:YES];
        CHECK([view canDrawConcurrently]);
        NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:view];
        NSView *decoded = [NSKeyedUnarchiver unarchiveObjectWithData:archived];
        CHECK(decoded != nil && [decoded canDrawConcurrently]);

        NSFont *font = [NSFont userFontOfSize:12];
        NSKeyedArchiver *secure = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
        [secure encodeObject:font forKey:NSKeyedArchiveRootObjectKey];
        [secure finishEncoding];
        NSData *fontData = [secure encodedData];
        CHECK(fontData != nil);
        NSError *error = nil;
        NSFont *roundTrip = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSFont class]
                fromData:fontData error:&error];
        CHECK(roundTrip != nil && error == nil);
        CHECK(roundTrip != nil && [[roundTrip fontName] isEqualToString:[font fontName]]);

        NSMutableData *storageData = [NSMutableData data];
        NSKeyedArchiver *storageArchiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:storageData];
        [storageArchiver setClassName:@"NSTextStorage" forClass:[TextStorageStandIn class]];
        [storageArchiver encodeObject:[TextStorageStandIn new] forKey:@"root"];
        [storageArchiver finishEncoding];
        NSKeyedUnarchiver *storageUnarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:storageData];
        NSTextStorage *storageBack = [storageUnarchiver decodeObjectForKey:@"root"];
        CHECK([[storageBack string] isEqualToString:@"abc"]);
        @try {
            [storageBack replaceCharactersInRange:NSMakeRange(1, 1) withString:@"XY"];
            CHECK([[storageBack string] isEqualToString:@"aXYc"]);
        } @catch (NSException *e) {
            fprintf(stderr, "FAIL: editing a decoded text storage raised %s\n", [[e name] UTF8String]);
            failures++;
        }

        for (NSString *name in @[@"NoSuchViewClass", @"NotAViewClass", @"NilFrameView"]) {
            id custom = decodeCustomView(name);
            CHECK(custom != nil && [custom class] == [NSView class]);
            CHECK(custom != nil && NSEqualRects([custom frame], NSMakeRect(1, 2, 30, 40)));
        }
        id usable = decodeCustomView(@"NSBox");
        CHECK(usable != nil && [usable isKindOfClass:[NSBox class]]);

        @try {
            [[NSNibConnector new] establishConnection];
        } @catch (NSException *e) {
            fprintf(stderr, "FAIL: base NSNibConnector raised %s\n", [[e name] UTF8String]);
            failures++;
        }

        Class effects = NSClassFromString(@"NSFontEffectsBox");
        CHECK(effects != Nil && [effects isSubclassOfClass:[NSBox class]]);

        if (!failures) puts("PASS");
    }
    return failures ? 1 : 0;
}
