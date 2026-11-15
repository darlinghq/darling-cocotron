// Copyright (C) 2026 Lubos Dolezel
//
// Loads nibs that ibtool compiled (fixtures/nibarchive, sources in fixtures/nibarchive/src)
// through NSNib and checks what they instantiate: objects, outlet and action connections,
// awakeFromNib, menus, table columns and custom classes. The same checks run on the
// NIBArchive files (a flat file, or a directory with keyedobjects-<version>.nib files) and on
// the old keyed archive (keyedobjects.nib alone). Damaged nibs must fail to instantiate
// without raising and without crashing.
//
// Usage: appkit-nibarchive-compiled <fixtures/nibarchive directory>
// Build: clang -fobjc-arc -framework AppKit appkit-nibarchive-compiled.m
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s (%s)\n", __LINE__, #c, [currentCase UTF8String]); failures++; } } while (0)
static NSString *currentCase;

@interface TableOwner : NSObject { NSWindow *_window; NSTableView *_table; int awakened; }
@property (strong) IBOutlet NSWindow *window; @property (strong) IBOutlet NSTableView *table;
@property int awakened;
@end
@implementation TableOwner
@synthesize window = _window, table = _table, awakened;
- (void)awakeFromNib { awakened++; }
@end

@interface MenuOwner : NSObject { NSMenu *_menu; NSMenuItem *_item; }
@property (strong) IBOutlet NSMenu *menu; @property (strong) IBOutlet NSMenuItem *item;
- (IBAction)openIt:(id)sender;
@end
@implementation MenuOwner
@synthesize menu = _menu, item = _item;
- (IBAction)openIt:(id)sender {}
@end

@class CustomOwner, CustomPanelView;
@interface CustomHelper : NSObject { id _owner; int awakened; BOOL ownerWasSet; }
@property (strong) IBOutlet id owner; @property int awakened; @property BOOL ownerWasSet;
- (IBAction)go:(id)sender;
@end
@implementation CustomHelper
@synthesize owner = _owner, awakened, ownerWasSet;
- (void)awakeFromNib { awakened++; ownerWasSet = _owner != nil; }
- (IBAction)go:(id)sender {}
@end
@interface CustomPanelView : NSView { int awakened; }
@property int awakened;
@end
@implementation CustomPanelView
@synthesize awakened;
- (void)awakeFromNib { awakened++; }
@end
@interface CustomOwner : NSObject { CustomHelper *_helper; CustomPanelView *_panelView; }
@property (strong) IBOutlet CustomHelper *helper; @property (strong) IBOutlet CustomPanelView *panelView;
@end
@implementation CustomOwner
@synthesize helper = _helper, panelView = _panelView;
@end

static NSFileManager *fm(void) { return [NSFileManager defaultManager]; }

// Copies `source` into a fresh directory as <name>.nib (keeping only `only` of a directory nib
// when given) and returns the directory, which serves as the bundle.
static NSString *stage(NSString *source, NSString *name, NSString *only) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"nibarchive-%d-%@", getpid(), [[NSUUID UUID] UUIDString]]];
    [fm() createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *dest = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".nib"]];
    if (only) {
        [fm() createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm() copyItemAtPath:[source stringByAppendingPathComponent:only]
                      toPath:[dest stringByAppendingPathComponent:only] error:NULL];
    } else {
        [fm() copyItemAtPath:source toPath:dest error:NULL];
    }
    return dir;
}

static NSArray *loadNib(NSString *bundleDir, NSString *name, id owner) {
    NSNib *nib = [[NSNib alloc] initWithNibNamed:name bundle:[NSBundle bundleWithPath:bundleDir]];
    CHECK(nib != nil);
    NSArray *top = nil;
    BOOL ok = [nib instantiateWithOwner:owner topLevelObjects:&top];
    CHECK(ok);
    return ok ? top : nil;
}

static id first(NSArray *top, Class c) {
    for (id o in top) if ([o isKindOfClass:c]) return o;
    return nil;
}

static void checkTable(NSString *dir) {
    TableOwner *owner = [TableOwner new];
    NSArray *top = loadNib(dir, @"Table", owner);
    NSWindow *window = first(top, [NSWindow class]);
    CHECK(window != nil && owner.window == window && [window.title isEqualToString:@"Table Window"]);
    NSTableView *table = owner.table;
    CHECK(table != nil && [table numberOfColumns] == 2);
    NSArray *columns = [table tableColumns];
    CHECK([columns count] == 2);
    if ([columns count] == 2) {
        CHECK([[columns[0] identifier] isEqualToString:@"name"] && [[columns[1] identifier] isEqualToString:@"size"]);
        CHECK([[[columns[0] headerCell] stringValue] isEqualToString:@"Name"]);
        CHECK([[[columns[1] headerCell] stringValue] isEqualToString:@"Size"]);
        CHECK([columns[0] minWidth] == 40 && [columns[0] maxWidth] == 1000);
    }
    CHECK([table headerView] != nil);
    // The nib stores a corner view object (class _NSCornerView, which NSNib maps to this
    // framework's own class); loading must cope with it, whether or not the table keeps it.
    CHECK([table cornerView] == nil || [[table cornerView] isKindOfClass:[NSView class]]);
    CHECK([[[table enclosingScrollView] documentView] isEqual:table]);
    CHECK([[window contentView] subviews].count == 1 && [[[window contentView] subviews][0] isKindOfClass:[NSScrollView class]]);
    CHECK(owner.awakened == 1);
}

static void checkMenu(NSString *dir) {
    MenuOwner *owner = [MenuOwner new];
    NSArray *top = loadNib(dir, @"Menu", owner);
    NSMenu *menu = owner.menu;
    CHECK(menu != nil && [top containsObject:menu]);
    CHECK([menu numberOfItems] == 2);
    if ([menu numberOfItems] != 2) return;
    NSMenu *file = [[menu itemAtIndex:0] submenu], *edit = [[menu itemAtIndex:1] submenu];
    CHECK([[[menu itemAtIndex:0] title] isEqualToString:@"File"] && [[[menu itemAtIndex:1] title] isEqualToString:@"Edit"]);
    CHECK([file numberOfItems] == 4 && [edit numberOfItems] == 1);
    if ([file numberOfItems] != 4 || [edit numberOfItems] != 1) return;
    NSMenuItem *open = [file itemAtIndex:0];
    CHECK(open == owner.item && [open.title isEqualToString:@"Open"] && [open.keyEquivalent isEqualToString:@"o"]);
    CHECK(open.action == @selector(openIt:) && open.target == owner);
    CHECK([[file itemAtIndex:1] isSeparatorItem]);
    NSMenuItem *close = [file itemAtIndex:2];
    CHECK([close.title isEqualToString:@"Close"] && close.action == @selector(performClose:) && close.target == nil);
    NSMenuItem *checked = [file itemAtIndex:3];
    CHECK(checked.state == NSControlStateValueOn && checked.tag == 3 && checked.indentationLevel == 1);
    CHECK([[edit itemAtIndex:0] action] == @selector(copy:) && [[[edit itemAtIndex:0] keyEquivalent] isEqualToString:@"c"]);
}

static void checkCustom(NSString *dir) {
    CustomOwner *owner = [CustomOwner new];
    NSArray *top = loadNib(dir, @"Custom", owner);
    CustomHelper *helper = owner.helper;
    CustomPanelView *panel = owner.panelView;
    CHECK(helper != nil && [helper isMemberOfClass:[CustomHelper class]]);
    CHECK(panel != nil && [panel isMemberOfClass:[CustomPanelView class]]);
    CHECK(helper.owner == owner);                       // an outlet to File's Owner
    CHECK([top containsObject:helper] && [top containsObject:panel]);
    CHECK(helper.awakened == 1 && helper.ownerWasSet);  // outlets are connected before awakeFromNib
    CHECK(panel.awakened == 1);
    CHECK(NSWidth(panel.frame) == 120 && NSHeight(panel.frame) == 80);
    NSButton *button = [[panel subviews] count] == 1 ? [panel subviews][0] : nil;
    CHECK([button isKindOfClass:[NSButton class]] && [button.title isEqualToString:@"Go"]);
    CHECK(button.action == @selector(go:) && button.target == helper);
}

static void checkDamaged(NSString *flatMenuNib) {
    NSData *good = [NSData dataWithContentsOfFile:flatMenuNib];
    CHECK([good length] > 100);
    NSMutableArray *variants = [NSMutableArray array];
    for (NSNumber *cut in @[@0, @5, @10, @49, @50, @100, @(good.length / 2), @(good.length - 1)])
        [variants addObject:@[[NSString stringWithFormat:@"truncated to %@", cut], [good subdataWithRange:NSMakeRange(0, [cut unsignedIntegerValue])]]];
    NSMutableData *ff = [good mutableCopy];
    memset((uint8_t *)[ff mutableBytes] + 50, 0xff, [ff length] - 50);
    [variants addObject:@[@"body 0xff", ff]];
    NSMutableData *magic = [good mutableCopy];
    ((uint8_t *)[magic mutableBytes])[9] = 'X';
    [variants addObject:@[@"bad magic", magic]];
    for (NSArray *v in variants) {
        currentCase = v[0];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"nibarchive-bad-%d", getpid()]];
        [fm() createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        [v[1] writeToFile:[dir stringByAppendingPathComponent:@"Bad.nib"] atomically:NO];
        BOOL raised = NO, ok = YES;
        @try {
            NSNib *nib = [[NSNib alloc] initWithNibNamed:@"Bad" bundle:[NSBundle bundleWithPath:dir]];
            CHECK(nib != nil);  // the data is not read until the nib is instantiated
            ok = [nib instantiateWithOwner:[MenuOwner new] topLevelObjects:NULL];
        } @catch (NSException *e) { raised = YES; }
        CHECK(!raised && !ok);
        [fm() removeItemAtPath:dir error:NULL];
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: %s <fixtures/nibarchive>\n", argv[0]); return 2; }
        [NSApplication sharedApplication];
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        NSMutableArray *staged = [NSMutableArray array];
        struct { NSString *name; void (*run)(NSString *); } cases[] = {
            { @"Table", checkTable }, { @"Menu", checkMenu }, { @"Custom", checkCustom },
        };
        for (int i = 0; i < 3; i++) {
            NSString *name = cases[i].name;
            NSString *flat = [root stringByAppendingFormat:@"/flat/%@.nib", name];
            NSString *dirNib = [root stringByAppendingFormat:@"/dirs/%@.nib", name];
            NSString *compat = [root stringByAppendingFormat:@"/compat/%@.nib", name];
            NSString *nibarchive = [fm() fileExistsAtPath:flat] ? flat : dirNib;
            currentCase = [name stringByAppendingString:@" (NIBArchive)"];
            NSString *d = stage(nibarchive, name, nil); [staged addObject:d];
            cases[i].run(d);
            currentCase = [name stringByAppendingString:@" (directory with keyed archive and NIBArchive files)"];
            d = stage(compat, name, nil); [staged addObject:d];
            cases[i].run(d);
            currentCase = [name stringByAppendingString:@" (keyed archive only)"];
            d = stage(compat, name, @"keyedobjects.nib"); [staged addObject:d];
            cases[i].run(d);
        }
        currentCase = @"damaged";
        checkDamaged([root stringByAppendingString:@"/flat/Menu.nib"]);
        for (NSString *d in staged) [fm() removeItemAtPath:d error:NULL];
        if (!failures) puts("PASS");
    }
    return failures ? 1 : 0;
}
