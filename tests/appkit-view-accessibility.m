// Copyright (C) 2026 Lubos Dolezel
// The NSAccessibility protocol (macOS 10.10) on views, controls, cells, windows, the
// application and NSAccessibilityElement: the defaults of a plain NSView, how ignored
// views are flattened into their ancestors' children, the elements that cells and windows
// are, the setters, the legacy attribute methods and NSAccessibilityRoleDescription.
// Expected values were measured on macOS 26.7.3 and 10.14.4; checks that differ between
// the two are run only where they hold.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

static BOOL same(id a, id b) {
    return a == b || [a isEqual: b];
}

static const char *str(id o) {
    return o ? [[o description] UTF8String] : "nil";
}

#define CHECK_EQ(a, b) do { id _a = (a), _b = (b); CHECK(same(_a, _b), "%s is %s, expected %s", #a, str(_a), str(_b)); } while (0)
#define CHECK_RECT(a, b) do { NSRect _a = (a), _b = (b); CHECK(NSEqualRects(_a, _b), "%s is %s, expected %s", #a, [NSStringFromRect(_a) UTF8String], [NSStringFromRect(_b) UTF8String]); } while (0)

// A plain view that claims to be an element.
@interface ElementView : NSView
@end

@implementation ElementView
- (BOOL) isAccessibilityElement {
    return YES;
}
@end

// A view whose own children come from NSView's implementation.
@interface SuperChildrenView : NSView
@end

@implementation SuperChildrenView
- (NSArray *) accessibilityChildren {
    return [super accessibilityChildren];
}
@end

static void testPlainView(NSView *view) {
    CHECK(![view isAccessibilityElement], "a plain view is not an element");
    CHECK_EQ([view accessibilityRole], NSAccessibilityUnknownRole);
    CHECK_EQ([view accessibilityRoleDescription], @"unknown");
    CHECK_EQ([view accessibilitySubrole], nil);
    CHECK_EQ([view accessibilityLabel], nil);
    CHECK_EQ([view accessibilityTitle], nil);
    CHECK_EQ([view accessibilityValue], nil);
    CHECK_EQ([view accessibilityIdentifier], nil);
    CHECK_EQ([view accessibilityHelp], nil);
    CHECK(![view isAccessibilityEnabled], "a plain view is not enabled");
    CHECK(![view isAccessibilityFocused], "a plain view is not focused");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CHECK([view accessibilityIsIgnored], "a plain view is ignored");
    CHECK_EQ([view accessibilityAttributeValue: NSAccessibilityRoleAttribute], NSAccessibilityUnknownRole);
    CHECK_EQ([view accessibilityAttributeValue: NSAccessibilityChildrenAttribute], [view accessibilityChildren]);
    CHECK_EQ([view accessibilityAttributeValue: NSAccessibilityParentAttribute], [view accessibilityParent]);
    CHECK([[view accessibilityAttributeNames] containsObject: NSAccessibilityChildrenAttribute], "AXChildren is listed");
#pragma clang diagnostic pop
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
        // macOS 10.14 lists only views that its legacy methods do not ignore, whatever
        // -isAccessibilityElement says, and describes a view by its default role even after
        // setAccessibilityRole:; macOS 26 follows the protocol's methods in both.
        BOOL followsProtocol = v.majorVersion > 10 || v.minorVersion >= 15;

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: YES];
        NSView *content = [window contentView];
        NSView *outer = [[NSView alloc] initWithFrame: NSMakeRect(10, 10, 200, 150)];
        NSView *inner = [[NSView alloc] initWithFrame: NSMakeRect(5, 5, 100, 100)];
        NSView *leaf = [[NSView alloc] initWithFrame: NSMakeRect(1, 2, 30, 40)];
        NSButton *nested = [[NSButton alloc] initWithFrame: NSMakeRect(40, 50, 50, 24)];
        [nested setTitle: @"Nested"];
        NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(220, 10, 60, 24)];
        [button setTitle: @"OK"];
        NSTextField *label = [NSTextField labelWithString: @"Hello"];
        NSSlider *slider = [[NSSlider alloc] initWithFrame: NSMakeRect(220, 50, 60, 20)];
        SuperChildrenView *custom = [[SuperChildrenView alloc] initWithFrame: NSMakeRect(220, 100, 60, 60)];
        [custom addSubview: [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)]];
        [content addSubview: outer];
        [outer addSubview: inner];
        [inner addSubview: leaf];
        [inner addSubview: nested];
        [content addSubview: button];
        [content addSubview: label];
        [content addSubview: slider];
        [content addSubview: custom];
        NSView *loose = [[NSView alloc] initWithFrame: NSMakeRect(3, 4, 10, 10)];

        // Plain views.
        for (NSView *view in @[content, outer, inner, leaf, custom, loose])
            testPlainView(view);

        // Ignored views are replaced by their unignored descendants; a control stands for its cell.
        CHECK_EQ([leaf accessibilityChildren], @[]);
        CHECK_EQ([inner accessibilityChildren], @[[nested cell]]);
        CHECK_EQ([outer accessibilityChildren], @[[nested cell]]);
        CHECK_EQ([custom accessibilityChildren], @[]);
        NSArray *expected = @[[nested cell], [button cell], [label cell], [slider cell]];
        CHECK_EQ([content accessibilityChildren], expected);
        // macOS 26 adds the title bar's elements after the content's.
        NSArray *windowChildren = [window accessibilityChildren];
        CHECK([windowChildren count] >= [expected count] &&
              same([windowChildren subarrayWithRange: NSMakeRange(0, [expected count])], expected),
              "the window's children start with its content view's: %s", str(windowChildren));

        // Hidden views and their descendants are left out.
        NSView *hiddenHost = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
        NSButton *shown = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)];
        NSButton *hidden = [[NSButton alloc] initWithFrame: NSMakeRect(0, 30, 50, 20)];
        [hidden setHidden: YES];
        NSView *hiddenGroup = [[NSView alloc] initWithFrame: NSMakeRect(0, 60, 50, 20)];
        [hiddenGroup setHidden: YES];
        [hiddenGroup addSubview: [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 50, 20)]];
        [hiddenHost addSubview: shown];
        [hiddenHost addSubview: hidden];
        [hiddenHost addSubview: hiddenGroup];
        CHECK_EQ([hiddenHost accessibilityChildren], @[[shown cell]]);
        CHECK_EQ([hidden accessibilityChildren], @[[hidden cell]]);

        // Parents are the nearest unignored ancestor; the window ends the chain below the application.
        CHECK_EQ([leaf accessibilityParent], window);
        CHECK_EQ([content accessibilityParent], window);
        CHECK_EQ([button accessibilityParent], window);
        CHECK_EQ([[nested cell] accessibilityParent], window);
        CHECK_EQ([window accessibilityParent], NSApp);
        CHECK_EQ([loose accessibilityParent], nil);
        CHECK_EQ([leaf accessibilityWindow], window);
        CHECK_EQ([leaf accessibilityTopLevelUIElement], window);
        CHECK_EQ([[button cell] accessibilityWindow], window);
        CHECK_EQ([loose accessibilityWindow], nil);
        CHECK_EQ([loose accessibilityTopLevelUIElement], nil);

        // Frames are in screen coordinates; outside a window, in the coordinates of the topmost view.
        CHECK_RECT([content accessibilityFrame], NSMakeRect(100, 100, 300, 200));
        CHECK_RECT([outer accessibilityFrame], NSMakeRect(110, 110, 200, 150));
        CHECK_RECT([leaf accessibilityFrame], NSMakeRect(116, 117, 30, 40));
        CHECK_RECT([loose accessibilityFrame], NSMakeRect(0, 0, 10, 10));
        CHECK_RECT([window accessibilityFrame], [window frame]);
        CHECK_RECT([[button cell] accessibilityFrame], [button accessibilityFrame]);

        // Controls are not elements themselves; their cells are.
        CHECK(![button isAccessibilityElement], "a button is not an element");
        CHECK_EQ([button accessibilityRole], NSAccessibilityUnknownRole);
        CHECK_EQ([button accessibilityChildren], @[[button cell]]);
        CHECK_EQ([button accessibilityLabel], @"OK");
        CHECK_EQ([button accessibilityTitle], @"OK");
        CHECK([button isAccessibilityEnabled], "a button is enabled");
        CHECK_EQ([label accessibilityValue], @"Hello");
        CHECK_EQ([label accessibilityLabel], nil);
        CHECK_EQ([slider accessibilityChildren], @[[slider cell]]);

        NSCell *cell = [button cell];
        CHECK([cell isAccessibilityElement], "a button cell is an element");
        CHECK_EQ([cell accessibilityRole], NSAccessibilityButtonRole);
        CHECK_EQ([cell accessibilityRoleDescription], @"button");
        CHECK_EQ([cell accessibilityLabel], @"OK");
        CHECK_EQ([cell accessibilityTitle], @"OK");
        CHECK_EQ([cell accessibilityValue], nil);
        CHECK_EQ([cell accessibilityChildren], nil);
        CHECK([cell isAccessibilityEnabled], "a button cell is enabled");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CHECK(![cell accessibilityIsIgnored], "a button cell is not ignored");
        CHECK_EQ([cell accessibilityAttributeValue: NSAccessibilityRoleAttribute], NSAccessibilityButtonRole);
#pragma clang diagnostic pop

        NSButton *check = [NSButton checkboxWithTitle: @"C" target: nil action: NULL];
        NSButton *radio = [NSButton radioButtonWithTitle: @"R" target: nil action: NULL];
        NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 20) pullsDown: NO];
        NSTextField *field = [NSTextField textFieldWithString: @"E"];
        NSImageView *imageView = [[NSImageView alloc] initWithFrame: NSMakeRect(0, 0, 20, 20)];
        struct { NSCell *cell; NSString *role, *description; id value; } cells[] = {
            {[check cell], NSAccessibilityCheckBoxRole, @"checkbox", @0},
            {[radio cell], NSAccessibilityRadioButtonRole, @"radio button", @0},
            {[popUp cell], NSAccessibilityPopUpButtonRole, @"pop up button", nil},
            {[label cell], NSAccessibilityStaticTextRole, @"text", @"Hello"},
            {[field cell], NSAccessibilityTextFieldRole, @"text field", @"E"},
            {[slider cell], NSAccessibilitySliderRole, @"slider", @0},
            {[imageView cell], NSAccessibilityImageRole, @"image", nil},
        };
        for (size_t i = 0; i < sizeof(cells) / sizeof(cells[0]); i++) {
            CHECK([cells[i].cell isAccessibilityElement], "%s is an element", class_getName([cells[i].cell class]));
            CHECK_EQ([cells[i].cell accessibilityRole], cells[i].role);
            CHECK_EQ([cells[i].cell accessibilityRoleDescription], cells[i].description);
            CHECK_EQ([cells[i].cell accessibilityValue], cells[i].value);
        }

        // The window and the application.
        CHECK([window isAccessibilityElement], "a window is an element");
        CHECK_EQ([window accessibilityRole], NSAccessibilityWindowRole);
        CHECK_EQ([window accessibilityWindow], nil);
        CHECK_EQ([NSApp accessibilityRole], NSAccessibilityApplicationRole);

        // Setters override the defaults and change nothing else.
        [leaf setAccessibilityLabel: @"L"];
        CHECK_EQ([leaf accessibilityLabel], @"L");
        [leaf setAccessibilityRole: NSAccessibilityImageRole];
        CHECK_EQ([leaf accessibilityRole], NSAccessibilityImageRole);
        if (followsProtocol)
            CHECK_EQ([leaf accessibilityRoleDescription], @"image");
        CHECK(![leaf isAccessibilityElement], "setting a role does not make an element");
        [outer setAccessibilityFrame: NSMakeRect(1, 2, 3, 4)];
        CHECK_RECT([outer accessibilityFrame], NSMakeRect(1, 2, 3, 4));
        [outer setAccessibilityParent: button];
        CHECK_EQ([outer accessibilityParent], button);
        [outer setAccessibilityIdentifier: @"axid"];
        CHECK_EQ([outer accessibilityIdentifier], @"axid");
        CHECK_EQ([outer identifier], nil);
        [button setAccessibilityLabel: @"Confirm"];
        CHECK_EQ([button accessibilityLabel], @"Confirm");
        [custom setAccessibilityEnabled: YES];
        CHECK([custom isAccessibilityEnabled], "setAccessibilityEnabled: YES");
        [leaf setAccessibilityElement: YES];
        CHECK([leaf isAccessibilityElement], "setAccessibilityElement: YES");

        if (followsProtocol) {
            CHECK_EQ([inner accessibilityChildren], (@[leaf, [nested cell]]));
            CHECK_EQ([outer accessibilityChildren], (@[leaf, [nested cell]]));
            [inner setAccessibilityElement: YES];
            CHECK_EQ([outer accessibilityChildren], @[inner]);
            CHECK_EQ([leaf accessibilityParent], inner);
            ElementView *element = [[ElementView alloc] initWithFrame: NSMakeRect(0, 0, 5, 5)];
            [custom addSubview: element];
            CHECK_EQ([custom accessibilityChildren], @[element]);
            CHECK_EQ([element accessibilityParent], window);
        }

        [inner setAccessibilityChildren: @[leaf]];
        CHECK_EQ([inner accessibilityChildren], @[leaf]);

        // NSAccessibilityElement: an element by default; its window comes from its parent and
        // a frame in its parent's space follows the parent.
        NSAccessibilityElement *made = [NSAccessibilityElement accessibilityElementWithRole: NSAccessibilityButtonRole
                                                                                      frame: NSMakeRect(1, 2, 3, 4)
                                                                                      label: @"x"
                                                                                     parent: custom];
        CHECK([made isAccessibilityElement], "an NSAccessibilityElement is an element");
        CHECK_EQ([made accessibilityRole], NSAccessibilityButtonRole);
        CHECK_EQ([made accessibilityLabel], @"x");
        CHECK_EQ([made accessibilityParent], custom);
        CHECK_RECT([made accessibilityFrame], NSMakeRect(1, 2, 3, 4));
        CHECK_EQ([made accessibilityWindow], window);
        NSAccessibilityElement *band = [[NSAccessibilityElement alloc] init];
        CHECK_EQ([band accessibilityRole], nil);
        CHECK_EQ([band accessibilityParent], nil);
        CHECK_RECT([band accessibilityFrame], NSZeroRect);
        [band setAccessibilityParent: custom];
        [band setAccessibilityFrameInParentSpace: NSMakeRect(5, 6, 7, 8)];
        CHECK_RECT([band accessibilityFrameInParentSpace], NSMakeRect(5, 6, 7, 8));
        CHECK_RECT([band accessibilityFrame], NSMakeRect(325, 206, 7, 8));
        NSAccessibilityElement *part = [[NSAccessibilityElement alloc] init];
        [part setAccessibilityFrameInParentSpace: NSMakeRect(1, 1, 2, 2)];
        [band accessibilityAddChildElement: part];
        CHECK_EQ([band accessibilityChildren], @[part]);
        CHECK_EQ([part accessibilityParent], band);
        CHECK_RECT([part accessibilityFrame], NSMakeRect(326, 207, 2, 2));
        CHECK_EQ([part accessibilityWindow], window);
        [custom setFrameOrigin: NSMakePoint(230, 110)];
        CHECK_RECT([band accessibilityFrame], NSMakeRect(335, 216, 7, 8));
        NSAccessibilityElement *onWindow = [[NSAccessibilityElement alloc] init];
        [onWindow setAccessibilityParent: window];
        [onWindow setAccessibilityFrameInParentSpace: NSMakeRect(5, 6, 7, 8)];
        CHECK_RECT([onWindow accessibilityFrame], NSOffsetRect(NSMakeRect(5, 6, 7, 8), NSMinX([window frame]), NSMinY([window frame])));
        CHECK_EQ([onWindow accessibilityWindow], nil);

        // Role descriptions.
        CHECK_EQ(NSAccessibilityRoleDescription(NSAccessibilityGroupRole, nil), @"group");
        CHECK_EQ(NSAccessibilityRoleDescription(NSAccessibilityTextAreaRole, nil), @"text entry area");
        CHECK_EQ(NSAccessibilityRoleDescription(NSAccessibilityIncrementorRole, nil), @"stepper");
        CHECK_EQ(NSAccessibilityRoleDescription(NSAccessibilityWindowRole, NSAccessibilityStandardWindowSubrole), @"standard window");
        CHECK_EQ(NSAccessibilityRoleDescription(NSAccessibilityWindowRole, NSAccessibilityDialogSubrole), @"dialog");
        CHECK_EQ(NSAccessibilityRoleDescription(NSAccessibilityButtonRole, NSAccessibilityCloseButtonSubrole), @"close button");
        CHECK_EQ(NSAccessibilityRoleDescription(NSAccessibilityTextFieldRole, NSAccessibilitySearchFieldSubrole), @"search text field");
        CHECK_EQ(NSAccessibilityRoleDescription(NSAccessibilityButtonRole, @"AXMadeUp"), @"button");
        CHECK_EQ(NSAccessibilityRoleDescription(@"AXMadeUp", nil), @"AXMadeUp");
        CHECK_EQ(NSAccessibilityRoleDescriptionForUIElement([button cell]), @"button");
    }
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
