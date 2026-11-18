// Copyright (C) 2026 Lubos Dolezel
//
// A secure text field keeps the typed text in its value but shows a bullet (U+2022) for every character, in the field
// and in the field editor while editing, and refuses to copy the text out. -echosBullets defaults to YES. A
// secure field decoded from a keyed archive in which its cell is a plain NSTextFieldCell (as nib compilers write it)
// still gets a secure cell. Black-box behavior of macOS 10.14.4 (cell class and -echosBullets of a field loaded
// from such a nib; bullet U+2022 as in the NSSecureTextFieldCell documentation).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSData *render(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    return [NSData dataWithBytes: [rep bitmapData] length: [rep bytesPerRow] * [rep pixelsHigh]];
}

// The number of separate groups of columns holding dark pixels, which is the number of glyphs drawn when they do
// not touch.
static int glyphs(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    int runs = 0;
    BOOL inRun = NO;
    for (NSInteger x = 3; x < [rep pixelsWide] - 3; x++) {
        BOOL dark = NO;
        for (NSInteger y = 3; y < [rep pixelsHigh] - 3; y++) {
            NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedWhiteColorSpace];
            if ([c whiteComponent] < 0.5)
                dark = YES;
        }
        if (dark && !inRun)
            runs++;
        inRun = dark;
    }
    return runs;
}

static NSTextField *plainField(NSString *s) {
    NSTextField *f = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 140, 22)];
    [f setStringValue: s];
    return f;
}

// An archive of a secure field with its cell written as a plain text field cell.
static NSSecureTextField *fieldFromPlainCellArchive(void) {
    NSSecureTextField *src = [[NSSecureTextField alloc] initWithFrame: NSMakeRect(0, 0, 140, 22)];
    [src setStringValue: @"secret"];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: src];
    NSMutableDictionary *plist = CFBridgingRelease(CFPropertyListCreateWithData(NULL, (__bridge CFDataRef) data,
                                                                                kCFPropertyListMutableContainers, NULL, NULL));
    for (NSMutableDictionary *o in plist[@"$objects"]) {
        if (![o isKindOfClass: [NSMutableDictionary class]])
            continue;
        if ([o[@"$classname"] isEqual: @"NSSecureTextFieldCell"]) {
            o[@"$classname"] = @"NSTextFieldCell";
            o[@"$classes"] = @[@"NSTextFieldCell", @"NSActionCell", @"NSCell", @"NSObject"];
        }
    }
    data = CFBridgingRelease(CFPropertyListCreateData(NULL, (__bridge CFPropertyListRef) plist,
                                                      kCFPropertyListBinaryFormat_v1_0, 0, NULL));
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingWithData: data];
    NSSecureTextField *field = [u decodeObjectForKey: NSKeyedArchiveRootObjectKey];
    [field setStringValue: @"secret"];  // a secure field's text is not part of its archive
    return field;
}

static void checkSecure(NSSecureTextField *secure, const char *what) {
    fprintf(stderr, "-- %s\n", what);
    CHECK([secure isKindOfClass: [NSSecureTextField class]]);
    CHECK([[secure cell] isKindOfClass: [NSSecureTextFieldCell class]]);
    CHECK([[secure cell] echosBullets] == YES);
    CHECK([[secure stringValue] isEqualToString: @"secret"]);

    // drawn as six bullets, not as the text, and independent of which characters they hide
    NSData *drawn = render(secure);
    NSTextField *plain = plainField(@"secret");
    CHECK(glyphs(secure) == 6);
    CHECK(![drawn isEqual: render(plain)]);
    [secure setStringValue: @"abc"];
    CHECK(glyphs(secure) == 3);
    [secure setStringValue: @"abcdef"];
    CHECK([render(secure) isEqual: drawn]);
    [secure setStringValue: @"secret"];
    CHECK([[secure stringValue] isEqualToString: @"secret"]);

    // echosBullets off hides the length too
    [[secure cell] setEchosBullets: NO];
    CHECK(![render(secure) isEqual: drawn]);
    [[secure cell] setEchosBullets: YES];

    // while editing, the field editor hides the text and does not hand it out
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 60)
                                                   styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: NO];
    [[window contentView] addSubview: secure];
    [secure setFrame: NSMakeRect(10, 10, 140, 22)];
    [window makeFirstResponder: secure];
    NSTextView *editor = (NSTextView *) [secure currentEditor];
    CHECK(editor != nil);
    CHECK([[editor string] isEqualToString: @"secret"]);
    [editor setSelectedRange: NSMakeRange(0, 6)];

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString: @"before" forType: NSPasteboardTypeString];
    [editor copy: nil];
    CHECK([[pb stringForType: NSPasteboardTypeString] isEqualToString: @"before"]);
    [editor cut: nil];
    CHECK([[pb stringForType: NSPasteboardTypeString] isEqualToString: @"before"]);
    CHECK([editor isKindOfClass: NSClassFromString(@"NSSecureTextView")]);

    [editor setString: @"secret"];
    [editor setSelectedRange: NSMakeRange(6, 0)];
    CHECK(glyphs(secure) == 6);
}

@interface AuthoredNibObject : NSObject <NSCoding>
@end
@implementation AuthoredNibObject
- (id) initWithCoder: (NSCoder *) coder { return [self init]; }
- (void) encodeWithCoder: (NSCoder *) coder {}
@end

// A compiled (NIBArchive) nib, authored from the documented layout, whose only top-level object is an
// NSSecureTextField with a plain NSTextFieldCell, as ibtool writes password fields. Nibs are decoded by a
// decoder that is not an NSKeyedUnarchiver.
static void varint(NSMutableData *data, uint32_t value) {
    do {
        uint8_t byte = value & 0x7f;
        value >>= 7;
        if (!value) byte |= 0x80;
        [data appendBytes: &byte length: 1];
    } while (value);
}
static void word(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = {value, value >> 8, value >> 16, value >> 24};
    [data appendBytes: bytes length: 4];
}
static void object(NSMutableData *data, uint32_t cls, uint32_t first, uint32_t count) {
    varint(data, cls); varint(data, first); varint(data, count);
}
static void reference(NSMutableData *data, uint32_t key, uint32_t target) {
    varint(data, key);
    uint8_t type = 10; [data appendBytes: &type length: 1]; word(data, target);
}
static NSData *secureFieldNib(void) {
    NSMutableData *objects = [NSMutableData data];
    object(objects, 0, 0, 1); // root: IB.objectdata
    object(objects, 1, 1, 5); // NSIBObjectData
    object(objects, 0, 6, 0); // File's Owner
    object(objects, 2, 6, 1); // top-level objects
    object(objects, 2, 7, 1); // corresponding parents
    object(objects, 3, 8, 0); // connections
    object(objects, 4, 8, 1); // the secure text field
    object(objects, 5, 9, 0); // its plain cell
    NSArray *names = @[@"IB.objectdata", @"NSRoot", @"NSObjectsKeys", @"NSObjectsValues", @"NSConnections",
                       @"NSNextOid", @"UINibEncoderEmptyKey", @"NSCell"];
    NSMutableData *keys = [NSMutableData data];
    for (NSString *name in names) {
        NSData *bytes = [name dataUsingEncoding: NSUTF8StringEncoding];
        varint(keys, (uint32_t) [bytes length]); [keys appendData: bytes];
    }
    NSMutableData *values = [NSMutableData data];
    reference(values, 0, 1); reference(values, 1, 2); reference(values, 2, 3);
    reference(values, 3, 4); reference(values, 4, 5);
    varint(values, 5); uint8_t type = 2;
    [values appendBytes: &type length: 1]; word(values, 17);
    reference(values, 6, 6); reference(values, 6, 2);
    reference(values, 7, 7);
    NSMutableData *classes = [NSMutableData data];
    for (NSString *name in @[@"AuthoredNibObject", @"NSIBObjectData", @"NSArray", @"NSMutableArray",
                             @"NSSecureTextField", @"NSTextFieldCell"]) {
        NSData *bytes = [name dataUsingEncoding: NSUTF8StringEncoding];
        varint(classes, (uint32_t) [bytes length] + 1); varint(classes, 0);
        [classes appendData: bytes]; uint8_t zero = 0;
        [classes appendBytes: &zero length: 1];
    }
    NSMutableData *archive = [NSMutableData dataWithBytes: "NIBArchive" length: 10];
    uint32_t objectsAt = 50, keysAt = objectsAt + (uint32_t) [objects length],
             valuesAt = keysAt + (uint32_t) [keys length], classesAt = valuesAt + (uint32_t) [values length];
    word(archive, 1); word(archive, 1);
    word(archive, 8); word(archive, objectsAt);
    word(archive, (uint32_t) [names count]); word(archive, keysAt);
    word(archive, 9); word(archive, valuesAt);
    word(archive, 6); word(archive, classesAt);
    [archive appendData: objects]; [archive appendData: keys];
    [archive appendData: values]; [archive appendData: classes];
    return archive;
}

static NSSecureTextField *fieldFromCompiledNib(void) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat: @"secure-field-nib-%d", getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES
                                               attributes: nil error: NULL];
    [secureFieldNib() writeToFile: [dir stringByAppendingPathComponent: @"Secure.nib"] atomically: NO];
    NSNib *nib = [[NSNib alloc] initWithNibNamed: @"Secure" bundle: [NSBundle bundleWithPath: dir]];
    [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
    NSArray *top = nil;
    BOOL loaded = [nib instantiateNibWithOwner: nil topLevelObjects: &top];
    CHECK(loaded && [top count] == 1);
    return loaded && [top count] == 1 ? top[0] : nil;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSSecureTextField *secure = [[NSSecureTextField alloc] initWithFrame: NSMakeRect(0, 0, 140, 22)];
        [secure setStringValue: @"secret"];
        checkSecure(secure, "programmatic");

        NSSecureTextField *decoded = fieldFromPlainCellArchive();
        CHECK(decoded != nil);
        checkSecure(decoded, "keyed archive with a plain cell");

        NSSecureTextField *fromNib = fieldFromCompiledNib();
        CHECK([fromNib isKindOfClass: [NSSecureTextField class]]);
        CHECK([[fromNib cell] isKindOfClass: [NSSecureTextFieldCell class]]);
        CHECK([[fromNib cell] echosBullets]);
    }
    if (failures)
        printf("FAIL secure-text-field (%d)\n", failures);
    else
        printf("PASS secure-text-field\n");
    return failures != 0;
}
