// Copyright (C) 2026 Lubos Dolezel
//
// Writes NSArchiver (typedstream) archives of controllers, connectors, view templates and a
// small old-style nib into the directory given as argv[1], as decoding fixtures. Build for
// x86_64 and run on the Mac named by the fixture directory. Expected values:
// tests/appkit-nonkeyed-controllers.m.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void put(NSString *dir, NSString *name, id root)
{
    @try {
        NSData *d = [NSArchiver archivedDataWithRootObject: root];
        [d writeToFile: [dir stringByAppendingPathComponent: name] atomically: NO];
        printf("%s %lu bytes\n", [name UTF8String], (unsigned long) [d length]);
    } @catch (NSException *e) {
        printf("%s EXC %s\n", [name UTF8String], [[e reason] UTF8String]);
    }
}

static void setIvar(id o, const char *name, id value)
{
    Ivar iv = class_getInstanceVariable([o class], name);
    if (iv != NULL) {
        object_setIvar(o, iv, [value retain]);
    }
}

static id viewTemplate(NSString *cls, NSView *view, NSString *className)
{
    return [[[NSClassFromString(cls) alloc] performSelector: @selector(initWithView:className:)
                                                 withObject: view
                                                 withObject: className] autorelease];
}

// For the nib: stand-ins for the classes the nib names.
@interface FixtureOwner : NSObject
@end
@implementation FixtureOwner
@end
@interface FixtureThing : NSObject
@end
@implementation FixtureThing
@end

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSString *dir = [NSString stringWithUTF8String: argv[1]];

    [NSApplication sharedApplication];

    NSObjectController *oc = [[[NSObjectController alloc] init] autorelease];
    [oc setObjectClass: [NSString class]];
    [oc setEditable: NO];
    [oc setAutomaticallyPreparesContent: YES];
    put(dir, @"objectcontroller.typedstream", oc);

    NSArrayController *ac = [[[NSArrayController alloc] init] autorelease];
    [ac setAvoidsEmptySelection: NO];
    [ac setPreservesSelection: NO];
    [ac setSelectsInsertedObjects: NO];
    [ac setAlwaysUsesMultipleValuesMarker: YES];
    [ac setClearsFilterPredicateOnInsertion: NO];
    put(dir, @"arraycontroller.typedstream", ac);

    // (NSDictionaryController is not archived: 10.14 does not read back its own NSArchiver archive of it.)

    NSTreeController *tc = [[[NSTreeController alloc] init] autorelease];
    [tc setEditable: NO];
    put(dir, @"treecontroller.typedstream", tc);

    // Connectors.
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObject: @"opt" forKey: @"NSNullPlaceholder"];
    id bc = [[[NSClassFromString(@"NSNibBindingConnector") alloc] init] autorelease];
    id src = [[[NSClassFromString(@"NSCustomObject") alloc] init] autorelease];
    [src setClassName: @"FixtureOwner"];
    id dst = [[[NSClassFromString(@"NSCustomObject") alloc] init] autorelease];
    [dst setClassName: @"FixtureThing"];
    [bc setSource: src];
    [bc setDestination: dst];
    [bc setLabel: @"value"];
    setIvar(bc, "_binding", @"value");
    setIvar(bc, "_keyPath", @"selection.name");
    setIvar(bc, "_options", options);
    put(dir, @"bindingconnector.typedstream", bc);

    id ax = [[[NSClassFromString(@"NSNibAXAttributeConnector") alloc] init] autorelease];
    setIvar(ax, "_destination", @"axdest");
    setIvar(ax, "_attributeType", @"AXTitle");
    setIvar(ax, "_attributeValue", @"axvalue");
    put(dir, @"axattributeconnector.typedstream", ax);

    // View templates: unarchiving yields the real view.
    NSButton *button = [[[NSButton alloc] initWithFrame: NSMakeRect(1, 2, 30, 40)] autorelease];
    [button setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
    put(dir, @"viewtemplate-button.typedstream", viewTemplate(@"NSViewTemplate", button, @"NSButton"));

    NSView *plain = [[[NSView alloc] initWithFrame: NSMakeRect(3, 4, 50, 60)] autorelease];
    [plain addSubview: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 5, 5)] autorelease]];
    put(dir, @"viewtemplate-unknown.typedstream", viewTemplate(@"NSViewTemplate", plain, @"NoSuchViewClassAnywhere"));

    NSTextView *tv = [[[NSTextView alloc] initWithFrame: NSMakeRect(1, 2, 300, 400)] autorelease];
    [tv setString: @"Hello text"];
    [tv setEditable: NO];
    [tv setRichText: NO];
    [tv setBackgroundColor: [NSColor redColor]];
    [tv setDrawsBackground: YES];
    [tv setHorizontallyResizable: YES];
    [tv setVerticallyResizable: NO];
    [tv setMinSize: NSMakeSize(100, 50)];
    [tv setMaxSize: NSMakeSize(800, 900)];
    [[tv textContainer] setContainerSize: NSMakeSize(300, 1000000)];
    [[tv textContainer] setWidthTracksTextView: NO];
    [[tv textContainer] setHeightTracksTextView: YES];
    [tv setUsesFontPanel: NO];
    [tv setAllowsUndo: YES];
    put(dir, @"textviewtemplate.typedstream", viewTemplate(@"NSTextViewTemplate", tv, @"NSTextView"));
    put(dir, @"texttemplate.typedstream", viewTemplate(@"NSTextTemplate", tv, @"NSText"));

    // An old-style nib: File's Owner, a custom object of a known class, one of an unknown class,
    // and outlet connectors from the owner.
    NSString *nibDir = [dir stringByAppendingPathComponent: @"custom.nib"];
    [[NSFileManager defaultManager] createDirectoryAtPath: nibDir withIntermediateDirectories: YES attributes: nil error: NULL];
    id od = [[[NSClassFromString(@"NSIBObjectData") alloc] init] autorelease];
    id owner = [[[NSClassFromString(@"NSCustomObject") alloc] init] autorelease];
    [owner setClassName: @"FixtureOwner"];
    id thing = [[[NSClassFromString(@"NSCustomObject") alloc] init] autorelease];
    [thing setClassName: @"FixtureThing"];
    id missing = [[[NSClassFromString(@"NSCustomObject") alloc] init] autorelease];
    [missing setClassName: @"NoSuchFixtureClass"];
    id c1 = [[[NSClassFromString(@"NSNibOutletConnector") alloc] init] autorelease];
    [c1 setSource: owner]; [c1 setDestination: thing]; [c1 setLabel: @"thing"];
    id c2 = [[[NSClassFromString(@"NSNibOutletConnector") alloc] init] autorelease];
    [c2 setSource: owner]; [c2 setDestination: missing]; [c2 setLabel: @"missing"];
    [od setRootObject: owner];
    [od setConnections: [NSMutableArray arrayWithObjects: c1, c2, nil]];
    [[od objectTable] setObject: owner forKey: thing];
    [[od objectTable] setObject: owner forKey: missing];
    [[od nameTable] setObject: @"File's Owner" forKey: owner];
    [[od nameTable] setObject: @"Thing" forKey: thing];
    [[od nameTable] setObject: @"Missing" forKey: missing];
    @try {
        NSData *nibData = [NSArchiver archivedDataWithRootObject: od];
        [nibData writeToFile: [nibDir stringByAppendingPathComponent: @"objects.nib"] atomically: NO];
        printf("custom.nib/objects.nib %lu bytes\n", (unsigned long) [nibData length]);
    } @catch (NSException *e) {
        printf("custom.nib EXC %s\n", [[e reason] UTF8String]);
    }

    [pool drain];
    return 0;
}
