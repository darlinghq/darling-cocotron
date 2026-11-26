// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: NSPopoverColorWell, NSColorPopoverController and
// NSColorPickerMatrixView, and the color well behavior they rely on.
// Observed on macOS 26.7.3 (x86_64) with the same calls:
// - the classes' superclasses (NSColorWell, NSViewController, NSView);
// - a color well supports alpha by default, and activating it sets the
//   color panel's showsAlpha to that;
// - +[NSColorWell _exclusiveColorPanelOwner] stays nil for plain wells, but
//   is a popover well activated exclusively, until it is deactivated;
// - activating a popover well does not show the color panel;
// - the controller has delegate and popover properties, and once its view
//   is loaded a topBarMatrixView that takes a color list, a column count and
//   a swatch size (as WebKit sets them).
// Needs a window system connection (X11 or Wayland).
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface NSColorWell (Private)
+ (NSColorWell *)_exclusiveColorPanelOwner;
@end

@interface NSColorPickerMatrixView : NSView
- (void)setColorList:(NSColorList *)list;
- (void)setSwatchSize:(NSSize)size;
- (void)setNumberOfColumns:(NSUInteger)columns;
@end

@interface NSColorPopoverController : NSViewController
@property (assign) id delegate;
@property (assign) NSPopover *popover;
@property (assign) NSColorPickerMatrixView *topBarMatrixView;
@end

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        report("NSPopoverColorWell is a color well", class_getSuperclass(objc_getClass("NSPopoverColorWell")) == [NSColorWell class]);
        report("NSColorPopoverController is a view controller", class_getSuperclass(objc_getClass("NSColorPopoverController")) == [NSViewController class]);
        report("NSColorPickerMatrixView is a view", class_getSuperclass(objc_getClass("NSColorPickerMatrixView")) == [NSView class]);

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 100) styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered defer: NO];
        NSColorWell *plain = [[[NSColorWell alloc] initWithFrame: NSMakeRect(0, 0, 40, 20)] autorelease];
        [window.contentView addSubview: plain];
        report("supports alpha by default", plain.supportsAlpha);
        report("no exclusive owner at first", [NSColorWell _exclusiveColorPanelOwner] == nil);
        [plain activate: YES];
        report("plain well: not the exclusive owner", [NSColorWell _exclusiveColorPanelOwner] == nil);
        report("plain well: panel shows alpha", [NSColorPanel sharedColorPanel].showsAlpha);
        [plain deactivate];
        plain.supportsAlpha = NO;
        [plain activate: YES];
        report("plain well without alpha: panel hides alpha", ![NSColorPanel sharedColorPanel].showsAlpha);
        [plain deactivate];
        [[NSColorPanel sharedColorPanel] orderOut: nil];

        NSColorWell *popoverWell = [[[objc_getClass("NSPopoverColorWell") alloc] initWithFrame: NSMakeRect(50, 0, 40, 20)] autorelease];
        [window.contentView addSubview: popoverWell];
        report("popover well responds to _showPopover", [popoverWell respondsToSelector: @selector(_showPopover)]);
        [popoverWell activate: YES];
        report("popover well: active", popoverWell.isActive);
        report("popover well: color panel not shown", ![NSColorPanel sharedColorPanel].isVisible);
        report("popover well: exclusive owner", [NSColorWell _exclusiveColorPanelOwner] == popoverWell);
        [popoverWell deactivate];
        report("popover well deactivated: no owner", [NSColorWell _exclusiveColorPanelOwner] == nil);

        NSColorPopoverController *controller = [[[objc_getClass("NSColorPopoverController") alloc] init] autorelease];
        NSPopover *popover = [[[NSPopover alloc] init] autorelease];
        controller.popover = popover;
        controller.delegate = popoverWell;
        report("controller properties", controller.popover == popover && controller.delegate == popoverWell);
        [controller loadView];
        NSColorPickerMatrixView *topBar = controller.topBarMatrixView;
        report("top bar matrix view", [topBar isKindOfClass: objc_getClass("NSColorPickerMatrixView")]);
        NSColorList *colors = [[[NSColorList alloc] initWithName: @"test"] autorelease];
        [colors insertColor: [NSColor redColor] key: @"0" atIndex: 0];
        [colors insertColor: [NSColor blueColor] key: @"1" atIndex: 1];
        [topBar setNumberOfColumns: 2];
        [topBar setSwatchSize: NSMakeSize(20, 13)];
        [topBar setColorList: colors];
        report("top bar takes colors", YES);
        [window release];
    }
    return failures != 0;
}
