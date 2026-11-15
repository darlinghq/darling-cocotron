/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Instance layout of AppKit classes on the legacy (fragile) Objective-C ABI.
//
// A 32-bit application's subclass of an AppKit class is compiled against
// Apple's instance layout: its ivars start at Apple's instance size, and it
// may read Apple's @protected ivars at their offsets. This test checks, on the
// legacy ABI, class_getInstanceSize of each covered class against the sizes
// measured on Mac OS X 10.14.4 (i386), and the offsets of the ivars kept at
// Apple's offsets. It then compiles "application" subclasses against those
// footprints (the superclass declarations below describe only the measured
// layout; AppKit headers are deliberately not imported) and checks that
// using AppKit API on them neither overwrites the subclass's ivars nor loses
// AppKit's own state, and that copies made with NSCopyObject() don't share
// state with the original.
//
// On the non-fragile ABI (x86_64) the size table doesn't apply (ivars slide);
// everything else runs there too and must pass unchanged.
//
// Build: clang -framework AppKit -framework Foundation (i386 and x86_64).
#import <Foundation/Foundation.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        printf("FAIL: %s\n", what);
        failures++;
    }
}

// Mac OS X 10.14.4, i386: class_getInstanceSize
static const struct {
    const char *name;
    size_t size;
} legacySizes[] = {
    {"NSResponder", 0x8},
    {"NSFont", 0x18},
    {"NSView", 0x50},
    {"NSColor", 0x4},
    {"NSWindow", 0x84},
    {"NSPanel", 0x84},
    {"NSControl", 0x5c},
    {"NSButton", 0x5c},
    {"NSImageRep", 0x1c},
    {"NSBitmapImageRep", 0x34},
    {"NSPopUpButton", 0x60},
    {"NSTextField", 0x64},
    {"NSSecureTextField", 0x64},
    {"NSSlider", 0x5c},
    {"NSImageView", 0x68},
    {"NSTableView", 0xe4},
    {"NSOpenGLContext", 0xc},
    {"NSOutlineView", 0x14c},
    {"NSScrollView", 0x78},
    {"NSClipView", 0x84},
    {"NSTextView", 0x54},
    {"NSBox", 0x88},
    {"NSTextStorage", 0x1c},
    {"NSTextContainer", 0x1c},
    {"NSOpenGLView", 0x64},
    {"NSCell", 0x14},
    {"NSActionCell", 0x24},
    {"NSButtonCell", 0x44},
    {"NSTextFieldCell", 0x30},
    {"NSWindowController", 0x28},
    {"NSViewController", 0x34},
    {"NSDocument", 0x34},
    {"NSApplication", 0x4c},
    {"NSMenu", 0x1c},
    {"NSMenuItem", 0x40},
    {"NSImage", 0x1c},
    {"NSScroller", 0x78},
    {"NSMatrix", 0xb0},
    {"NSSplitView", 0x54},
    {"NSTableColumn", 0x28},
};

// ivars kept at Apple's offsets (Mac OS X 10.14.4 i386 ivar_getOffset of the
// same state; our names)
static const struct {
    const char *className;
    const char *ivar;
    ptrdiff_t offset;
} legacyOffsets[] = {
    {"NSResponder", "_nextResponder", 0x4},
    {"NSView", "_frame", 0x8},
    {"NSView", "_bounds", 0x18},
    {"NSView", "_superview", 0x28},
    {"NSView", "_subviews", 0x2c},
    {"NSView", "_window", 0x30},
    {"NSView", "_layer", 0x3c},
    {"NSWindow", "_frame", 0x8},
    {"NSWindow", "_contentView", 0x18},
    {"NSWindow", "_delegate", 0x1c},
    {"NSWindow", "_firstResponder", 0x20},
    {"NSWindow", "_platformWindow", 0x2c},
    {"NSWindow", "_sharedFieldEditor", 0x30},
    {"NSWindow", "_level", 0x3c},
    {"NSWindow", "_backgroundColor", 0x40},
    {"NSWindow", "_backgroundView", 0x44},
    {"NSWindow", "_miniwindowImage", 0x54},
    {"NSWindow", "_representedURL", 0x60},
    {"NSWindow", "_autosaveFrameName", 0x68},
    {"NSWindow", "_toolbar", 0x6c},
    {"NSWindow", "_defaultButtonCell", 0x78},
    {"NSWindow", "_initialFirstResponder", 0x7c},
    {"NSControl", "_aux", 0x50},
    {"NSControl", "_cell", 0x54},
    {"NSActionCell", "_tag", 0x14},
    {"NSActionCell", "_target", 0x18},
    {"NSActionCell", "_action", 0x1c},
    {"NSActionCell", "_controlView", 0x20},
    {"NSButtonCell", "_alternateTitle", 0x24},
    {"NSButtonCell", "_sound", 0x28},
    {"NSButtonCell", "_keyEquivalent", 0x2c},
    {"NSButtonCell", "_normalImage", 0x3c},
    {"NSTextField", "_delegate", 0x5c},
    {"NSTextFieldCell", "_backgroundColor", 0x24},
    {"NSTextFieldCell", "_textColor", 0x28},
    {"NSWindowController", "_window", 0x8},
    {"NSWindowController", "_nibName", 0xc},
    {"NSWindowController", "_document", 0x10},
    {"NSWindowController", "_topLevelObjects", 0x14},
    {"NSWindowController", "_owner", 0x18},
    {"NSWindowController", "_windowFrameAutosaveName", 0x20},
    {"NSViewController", "_nibName", 0x8},
    {"NSViewController", "_nibBundle", 0xc},
    {"NSViewController", "_representedObject", 0x10},
    {"NSViewController", "_title", 0x14},
    {"NSViewController", "_view", 0x18},
    {"NSImageView", "_target", 0x60},
    {"NSImageView", "_action", 0x64},
    {"NSApplication", "_currentEvent", 0x8},
    {"NSApplication", "_windows", 0xc},
    {"NSApplication", "_keyWindow", 0x10},
    {"NSApplication", "_mainWindow", 0x14},
    {"NSApplication", "_delegate", 0x18},
    {"NSApplication", "_running", 0x32},
    {"NSApplication", "_mainMenu", 0x38},
    {"NSApplication", "_appearance", 0x40},
    {"NSOpenGLView", "_context", 0x50},
    {"NSOpenGLView", "_pixelFormat", 0x54},
    {"NSScrollView", "_verticalScroller", 0x50},
    {"NSScrollView", "_horizontalScroller", 0x54},
    {"NSScrollView", "_clipView", 0x58},
    {"NSScrollView", "_headerClipView", 0x5c},
    {"NSScrollView", "_cornerView", 0x60},
    {"NSClipView", "_backgroundColor", 0x50},
    {"NSClipView", "_docView", 0x54},
    {"NSClipView", "_docRect", 0x58},
    {"NSClipView", "_documentCursor", 0x78},
    {"NSTableView", "_headerView", 0x5c},
    {"NSTableView", "_cornerView", 0x60},
    {"NSTableView", "_tableColumns", 0x64},
    {"NSTableView", "_editingCell", 0x68},
    {"NSTableView", "_delegate", 0x6c},
    {"NSTableView", "_dataSource", 0x70},
    {"NSTableView", "_intercellSpacing", 0x74},
    {"NSTableView", "_standardRowHeight", 0x7c},
    {"NSTableView", "_editedRow", 0x88},
    {"NSTableView", "_editedColumn", 0x8c},
    {"NSTableView", "_backgroundColor", 0x9c},
    {"NSTableView", "_gridColor", 0xa0},
    {"NSTableView", "_doubleAction", 0xb0},
    {"NSOutlineView", "_outlineTableColumn", 0xfc},
    {"NSOutlineView", "_markerCell", 0x108},
    {"NSMenu", "_supermenu", 0x4},
    {"NSMenu", "_title", 0x8},
    {"NSMenuItem", "_menu", 0x4},
    {"NSMenuItem", "_title", 0x8},
    {"NSImage", "_name", 0x4},
    {"NSImage", "_size", 0x8},
    {"NSBox", "_titleCell", 0x50},
    {"NSBox", "_contentViewMargins", 0x58},
    {"NSScroller", "_floatValue", 0x5c},
    {"NSScroller", "_knobProportion", 0x60},
    {"NSMatrix", "_doubleAction", 0x64},
    {"NSMatrix", "_delegate", 0x6c},
    {"NSMatrix", "_numberOfRows", 0x7c},
    {"NSMatrix", "_numberOfColumns", 0x80},
    {"NSMatrix", "_cellSize", 0x84},
    {"NSMatrix", "_intercellSpacing", 0x8c},
    {"NSMatrix", "_font", 0x94},
    {"NSMatrix", "_protoCell", 0x98},
    {"NSMatrix", "_cellClass", 0x9c},
    {"NSMatrix", "_backgroundColor", 0xa0},
    {"NSMatrix", "_cells", 0xa8},
    {"NSTableColumn", "_identifier", 0x4},
};

static void checkLegacyLayout(void) {
#if !__OBJC2__
    for (size_t i = 0; i < sizeof(legacySizes) / sizeof(legacySizes[0]); i++) {
        Class cls = objc_getClass(legacySizes[i].name);
        size_t size = cls ? class_getInstanceSize(cls) : 0;
        if (size != legacySizes[i].size) {
            printf("FAIL: %s instance size 0x%zx, expected 0x%zx\n",
                   legacySizes[i].name, size, legacySizes[i].size);
            failures++;
        }
    }
    for (size_t i = 0; i < sizeof(legacyOffsets) / sizeof(legacyOffsets[0]); i++) {
        Class cls = objc_getClass(legacyOffsets[i].className);
        Ivar ivar = cls ? class_getInstanceVariable(cls, legacyOffsets[i].ivar) : NULL;
        ptrdiff_t offset = ivar ? ivar_getOffset(ivar) : -1;
        if (offset != legacyOffsets[i].offset) {
            printf("FAIL: %s.%s at 0x%tx, expected 0x%tx\n",
                   legacyOffsets[i].className, legacyOffsets[i].ivar, offset,
                   legacyOffsets[i].offset);
            failures++;
        }
    }
#endif
}

// The measured legacy footprints. Field names are ours; only the offsets and
// sizes matter on the legacy ABI. On the non-fragile ABI only the named
// fields that are read below must exist in AppKit.
@interface NSResponder : NSObject {
  @public
    id _nextResponder;
}
@end

@interface NSView : NSResponder {
  @public
    NSRect _frame;
    NSRect _bounds;
    id _superview;
    id _subviews;
    id _window;
    void *_appleLayout1[2];
    id _layer;
    void *_appleLayout2[4];
}
@end

@interface NSWindow : NSResponder {
  @public
    NSRect _frame;
    id _contentView;
    id _delegate;
    id _firstResponder;
    void *_appleLayout1[6];
    long _level;
    id _backgroundColor;
    void *_appleLayout2[16];
}
@end

@interface NSControl : NSView {
    void *_controlLayout[3];
}
@end

@interface NSTextField : NSControl {
    void *_textFieldLayout[2];
}
@end

@interface NSButton : NSControl
@end

@interface NSWindowController : NSResponder {
  @public
    id _window;
    void *_windowControllerLayout[7];
}
@end

@interface NSDocument : NSObject {
    void *_documentLayout[12];
}
@end

// the AppKit API used here
@interface NSObject (LegacyLayoutTestAPI)
+ (id) sharedApplication;
+ (id) redColor;
+ (id) blueColor;
+ (id) systemFontOfSize: (CGFloat) size;
- (id) initWithFrame: (NSRect) frame;
- (id) initWithContentRect: (NSRect) rect
                 styleMask: (NSUInteger) style
                   backing: (NSUInteger) backing
                     defer: (BOOL) defer;
- (id) initWithWindow: (id) window;
- (id) initWithActivityType: (NSString *) type;
- (id) initWithTitle: (NSString *) title;
- (id) initWithTitle: (NSString *) title action: (SEL) action keyEquivalent: (NSString *) key;
- (id) initTextCell: (NSString *) string;
- (id) initWithSize: (NSSize) size;
- (id) initWithRect: (NSRect) rect options: (NSUInteger) options owner: (id) owner userInfo: (id) info;
- (void) setNextResponder: (id) responder;
- (id) nextResponder;
- (void) setUserActivity: (id) activity;
- (id) userActivity;
- (void) setMenu: (id) menu;
- (id) menu;
- (void) setAutoresizingMask: (NSUInteger) mask;
- (NSUInteger) autoresizingMask;
- (void) setHidden: (BOOL) hidden;
- (BOOL) isHidden;
- (void) setToolTip: (NSString *) tip;
- (NSString *) toolTip;
- (void) registerForDraggedTypes: (NSArray *) types;
- (void) setNeedsDisplay: (BOOL) flag;
- (void) addSubview: (id) view;
- (void) removeFromSuperview;
- (id) superview;
- (void) addTrackingArea: (id) area;
- (void) removeTrackingArea: (id) area;
- (NSArray *) trackingAreas;
- (void) setTitle: (NSString *) title;
- (NSString *) title;
- (void) setLevel: (NSInteger) level;
- (NSInteger) level;
- (void) setBackgroundColor: (id) color;
- (void) setDelegate: (id) delegate;
- (id) delegate;
- (void) setAcceptsMouseMovedEvents: (BOOL) flag;
- (BOOL) acceptsMouseMovedEvents;
- (void) setReleasedWhenClosed: (BOOL) flag;
- (void) setMinSize: (NSSize) size;
- (BOOL) setFrameAutosaveName: (NSString *) name;
- (void) setContentView: (id) view;
- (id) contentView;
- (void) invalidateCursorRectsForView: (id) view;
- (void) disableCursorRects;
- (void) enableCursorRects;
- (void) close;
- (void) setStringValue: (NSString *) string;
- (NSString *) stringValue;
- (void) setPlaceholderString: (NSString *) string;
- (NSString *) placeholderString;
- (void) setEditable: (BOOL) flag;
- (void) setPreferredMaxLayoutWidth: (CGFloat) width;
- (CGFloat) preferredMaxLayoutWidth;
- (void) setAllowsExpansionToolTips: (BOOL) flag;
- (BOOL) allowsExpansionToolTips;
- (void) setAlternateTitle: (NSString *) title;
- (NSString *) alternateTitle;
- (void) setKeyEquivalent: (NSString *) key;
- (void) setHasDestructiveAction: (BOOL) flag;
- (BOOL) hasDestructiveAction;
- (void) setContentTintColor: (id) color;
- (id) contentTintColor;
- (id) window;
- (void) setShouldCascadeWindows: (BOOL) flag;
- (BOOL) shouldCascadeWindows;
- (void) setWindowFrameAutosaveName: (NSString *) name;
- (void) setFileType: (NSString *) type;
- (NSString *) fileType;
- (void) setFileURL: (NSURL *) url;
- (void) updateChangeCount: (NSUInteger) change;
- (BOOL) isDocumentEdited;
- (void) setFont: (id) font;
- (id) font;
- (void) addItem: (id) item;
- (NSInteger) numberOfItems;
- (void) setAccessibilityDescription: (NSString *) description;
- (NSString *) accessibilityDescription;
@end

#define CANARY_WORDS 16
#define CANARY(i) (0xC0DE0000u + (unsigned) (i))

#define APP_SUBCLASS(name, superclass)                                         \
    @interface name : superclass {                                             \
      @public                                                                  \
        unsigned _canary[CANARY_WORDS];                                        \
    }                                                                          \
    @end                                                                       \
    @implementation name                                                       \
    @end

APP_SUBCLASS(AppResponder, NSResponder)
APP_SUBCLASS(AppView, NSView)
APP_SUBCLASS(AppWindow, NSWindow)
APP_SUBCLASS(AppTextField, NSTextField)
APP_SUBCLASS(AppButton, NSButton)
APP_SUBCLASS(AppWindowController, NSWindowController)
APP_SUBCLASS(AppDocument, NSDocument)

// On the legacy ABI the declarations above must reproduce the measured
// footprints, or the subclass checks below test the wrong layout.
#define CANARY_OFFSET(name) ((size_t) (uintptr_t) &((name *) 0)->_canary)

static size_t legacySize(const char *name) {
    for (size_t i = 0; i < sizeof(legacySizes) / sizeof(legacySizes[0]); i++)
        if (strcmp(legacySizes[i].name, name) == 0)
            return legacySizes[i].size;
    return 0;
}

static void checkTestDeclarations(void) {
#if !__OBJC2__
    struct {
        const char *superclass;
        size_t canaryOffset;
    } declared[] = {
        {"NSResponder", CANARY_OFFSET(AppResponder)},
        {"NSView", CANARY_OFFSET(AppView)},
        {"NSWindow", CANARY_OFFSET(AppWindow)},
        {"NSTextField", CANARY_OFFSET(AppTextField)},
        {"NSButton", CANARY_OFFSET(AppButton)},
        {"NSWindowController", CANARY_OFFSET(AppWindowController)},
        {"NSDocument", CANARY_OFFSET(AppDocument)},
    };
    for (size_t i = 0; i < sizeof(declared) / sizeof(declared[0]); i++) {
        if (declared[i].canaryOffset != legacySize(declared[i].superclass)) {
            printf("FAIL: test declares %s as 0x%zx bytes, expected 0x%zx\n",
                   declared[i].superclass, declared[i].canaryOffset,
                   legacySize(declared[i].superclass));
            failures++;
        }
    }
#endif
}

static void fillCanary(unsigned *canary) {
    for (int i = 0; i < CANARY_WORDS; i++)
        canary[i] = CANARY(i);
}

static BOOL canaryIntact(const unsigned *canary) {
    for (int i = 0; i < CANARY_WORDS; i++)
        if (canary[i] != CANARY(i))
            return NO;
    return YES;
}

static id appKitClass(const char *name) {
    return (id) objc_getClass(name);
}

static void checkResponderSubclass(void) {
    AppResponder *r = [[AppResponder alloc] init];
    fillCanary(r->_canary);
    id next = [[appKitClass("NSResponder") alloc] init];
    [r setNextResponder: next];
    id activity = [[appKitClass("NSUserActivity") alloc] initWithActivityType: @"org.darlinghq.test"];
    [r setUserActivity: activity];
    expect([r nextResponder] == next, "NSResponder nextResponder");
    expect(r->_nextResponder == next, "NSResponder _nextResponder ivar");
    expect([r userActivity] == activity, "NSResponder userActivity");
    expect(canaryIntact(r->_canary), "NSResponder subclass ivars intact");
    [activity release];
    [next release];
    [r release];
}

static void checkViewSubclass(void) {
    AppView *v = [[AppView alloc] initWithFrame: NSMakeRect(10, 20, 300, 200)];
    fillCanary(v->_canary);
    id menu = [[appKitClass("NSMenu") alloc] initWithTitle: @"m"];
    [v setMenu: menu];
    [v setAutoresizingMask: 18];
    [v setHidden: YES];
    [v setToolTip: @"tip"];
    [v registerForDraggedTypes: @[ @"public.utf8-plain-text" ]];
    [v setNeedsDisplay: YES];
    id child = [[appKitClass("NSView") alloc] initWithFrame: NSMakeRect(1, 2, 3, 4)];
    [v addSubview: child];
    // NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
    id area = [[appKitClass("NSTrackingArea") alloc] initWithRect: NSMakeRect(0, 0, 10, 10)
                                                          options: 0x01 | 0x80
                                                            owner: v
                                                         userInfo: nil];
    [v addTrackingArea: area];

    expect(canaryIntact(v->_canary), "NSView subclass ivars intact");
    expect([v menu] == menu, "NSView menu");
    expect([v autoresizingMask] == 18, "NSView autoresizingMask");
    expect([v isHidden], "NSView hidden");
    expect([[v toolTip] isEqual: @"tip"], "NSView toolTip");
    expect([[v trackingAreas] containsObject: area], "NSView trackingAreas");
    expect([child superview] == v, "NSView superview");
    expect(v->_frame.size.width == 300 && v->_frame.size.height == 200 &&
                   v->_frame.origin.x == 10,
           "NSView _frame ivar");
    expect(v->_bounds.size.width == 300 && v->_bounds.size.height == 200,
           "NSView _bounds ivar");
    expect([(NSArray *) v->_subviews count] == 1 &&
                   [(NSArray *) v->_subviews objectAtIndex: 0] == child,
           "NSView _subviews ivar");
    expect(((NSView *) child)->_superview == v, "NSView _superview ivar");

    [child removeFromSuperview];
    [v removeTrackingArea: area];
    expect(canaryIntact(v->_canary), "NSView subclass ivars intact after removal");
    [area release];
    [child release];
    [menu release];
    [v release];
}

static void checkWindowSubclass(void) {
    // titled | closable | resizable, buffered
    AppWindow *w = [[AppWindow alloc] initWithContentRect: NSMakeRect(50, 60, 320, 240)
                                                styleMask: 1 | 2 | 8
                                                  backing: 2
                                                    defer: YES];
    fillCanary(w->_canary);
    [w setTitle: @"legacy layout"];
    [w setLevel: 3];
    id color = [appKitClass("NSColor") redColor];
    [w setBackgroundColor: color];
    id delegate = [NSObject new];
    [w setDelegate: delegate];
    [w setAcceptsMouseMovedEvents: YES];
    [w setReleasedWhenClosed: NO];
    [w setMinSize: NSMakeSize(100, 80)];
    [w setFrameAutosaveName: @""];
    id content = [[appKitClass("NSView") alloc] initWithFrame: NSMakeRect(0, 0, 320, 240)];
    [w setContentView: content];
    [w invalidateCursorRectsForView: content];
    [w disableCursorRects];
    [w enableCursorRects];

    expect(canaryIntact(w->_canary), "NSWindow subclass ivars intact");
    expect([[w title] isEqual: @"legacy layout"], "NSWindow title");
    expect([w level] == 3, "NSWindow level");
    expect([w acceptsMouseMovedEvents], "NSWindow acceptsMouseMovedEvents");
    expect([w contentView] == content, "NSWindow contentView");
    expect(w->_contentView == content, "NSWindow _contentView ivar");
    expect(w->_delegate == delegate, "NSWindow _delegate ivar");
    expect(w->_level == 3, "NSWindow _level ivar");
    expect(w->_backgroundColor == color, "NSWindow _backgroundColor ivar");
    expect(w->_frame.size.width > 0 && w->_frame.size.height > 0, "NSWindow _frame ivar");
    expect(((NSView *) content)->_window == w, "NSView _window ivar");

    [w setDelegate: nil];
    [w close];
    expect(canaryIntact(w->_canary), "NSWindow subclass ivars intact after close");
    [content release];
    [delegate release];
    [w release];
}

static void checkControlSubclasses(void) {
    AppTextField *field = [[AppTextField alloc] initWithFrame: NSMakeRect(0, 0, 120, 22)];
    fillCanary(field->_canary);
    id delegate = [NSObject new];
    [field setStringValue: @"text"];
    [field setPlaceholderString: @"placeholder"];
    [field setDelegate: delegate];
    [field setEditable: YES];
    [field setPreferredMaxLayoutWidth: 99];
    [field setAllowsExpansionToolTips: YES];
    expect(canaryIntact(field->_canary), "NSTextField subclass ivars intact");
    expect([[field stringValue] isEqual: @"text"], "NSTextField stringValue");
    expect([field delegate] == delegate, "NSTextField delegate");
    expect([field preferredMaxLayoutWidth] == 99, "NSTextField preferredMaxLayoutWidth");
    expect([field allowsExpansionToolTips], "NSControl allowsExpansionToolTips");
    [field setDelegate: nil];
    [field release];
    [delegate release];

    AppButton *button = [[AppButton alloc] initWithFrame: NSMakeRect(0, 0, 80, 24)];
    fillCanary(button->_canary);
    id blue = [appKitClass("NSColor") blueColor];
    [button setTitle: @"OK"];
    [button setAlternateTitle: @"Alt"];
    [button setKeyEquivalent: @"\r"];
    [button setHasDestructiveAction: YES];
    [button setContentTintColor: blue];
    expect(canaryIntact(button->_canary), "NSButton subclass ivars intact");
    expect([[button title] isEqual: @"OK"], "NSButton title");
    expect([[button alternateTitle] isEqual: @"Alt"], "NSButton alternateTitle");
    expect([button hasDestructiveAction], "NSButton hasDestructiveAction");
    expect([button contentTintColor] == blue, "NSButton contentTintColor");
    [button release];
}

static void checkControllerSubclasses(void) {
    id window = [[appKitClass("NSWindow") alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                           styleMask: 1
                                                             backing: 2
                                                               defer: YES];
    AppWindowController *controller = [[AppWindowController alloc] initWithWindow: window];
    fillCanary(controller->_canary);
    [controller setShouldCascadeWindows: NO];
    [controller setWindowFrameAutosaveName: @""];
    expect(canaryIntact(controller->_canary), "NSWindowController subclass ivars intact");
    expect([controller window] == window, "NSWindowController window");
    expect(controller->_window == window, "NSWindowController _window ivar");
    expect(![controller shouldCascadeWindows], "NSWindowController shouldCascadeWindows");
    [controller release];
    [window release];

    AppDocument *document = [[AppDocument alloc] init];
    fillCanary(document->_canary);
    [document setFileType: @"public.plain-text"];
    [document setFileURL: [NSURL fileURLWithPath: @"/tmp/legacy-layout.txt"]];
    [document updateChangeCount: 0]; // NSChangeDone
    expect(canaryIntact(document->_canary), "NSDocument subclass ivars intact");
    expect([[document fileType] isEqual: @"public.plain-text"], "NSDocument fileType");
    expect([document isDocumentEdited], "NSDocument edited");
    [document release];
}

// copies made with NSCopyObject() must not share state with the original
static void checkCopies(void) {
    id cell = [[appKitClass("NSButtonCell") alloc] initTextCell: @"a"];
    [cell setAlternateTitle: @"alt"];
    [cell setFont: [appKitClass("NSFont") systemFontOfSize: 13]];
    id cellCopy = [cell copy];
    [cellCopy setTitle: @"b"];
    [cellCopy setAlternateTitle: @"alt2"];
    expect([[cell title] isEqual: @"a"], "NSButtonCell original title");
    expect([[cell alternateTitle] isEqual: @"alt"], "NSButtonCell original alternateTitle");
    expect([[cellCopy title] isEqual: @"b"], "NSButtonCell copy title");
    expect([cellCopy font] == [cell font], "NSButtonCell copy font");
    [cellCopy release];
    expect([[cell title] isEqual: @"a"], "NSButtonCell outlives its copy");
    [cell release];

    id textCell = [[appKitClass("NSTextFieldCell") alloc] initTextCell: @"t"];
    [textCell setPlaceholderString: @"p"];
    id textCopy = [textCell copy];
    [textCopy setPlaceholderString: @"q"];
    expect([[textCell placeholderString] isEqual: @"p"], "NSTextFieldCell original placeholder");
    expect([[textCopy placeholderString] isEqual: @"q"], "NSTextFieldCell copy placeholder");
    [textCopy release];
    [textCell release];

    id item = [[appKitClass("NSMenuItem") alloc] initWithTitle: @"Item" action: NULL keyEquivalent: @"i"];
    [item setToolTip: @"tip"];
    id itemCopy = [item copy];
    [itemCopy setToolTip: @"tip2"];
    [itemCopy setTitle: @"Copy"];
    expect([[item toolTip] isEqual: @"tip"], "NSMenuItem original toolTip");
    expect([[item title] isEqual: @"Item"], "NSMenuItem original title");
    expect([[itemCopy toolTip] isEqual: @"tip2"], "NSMenuItem copy toolTip");

    id menu = [[appKitClass("NSMenu") alloc] initWithTitle: @"Menu"];
    [menu addItem: item];
    id menuCopy = [menu copy];
    expect([menuCopy numberOfItems] == 1, "NSMenu copy items");
    [menuCopy setTitle: @"Other"];
    expect([[menu title] isEqual: @"Menu"], "NSMenu original title");
    [menuCopy release];
    [menu release];
    [itemCopy release];
    [item release];

    id image = [[appKitClass("NSImage") alloc] initWithSize: NSMakeSize(16, 16)];
    [image setAccessibilityDescription: @"img"];
    id imageCopy = [image copy];
    [imageCopy setAccessibilityDescription: @"img2"];
    expect([[image accessibilityDescription] isEqual: @"img"], "NSImage original description");
    expect([[imageCopy accessibilityDescription] isEqual: @"img2"], "NSImage copy description");
    [imageCopy release];
    [image release];
}

// NSTextStorage and NSTextContainer are 0x1c bytes; their state beyond the
// words that fit is kept in the extras block
@interface NSObject (LegacyLayoutTextAPI)
- (id) initWithString: (NSString *) string;
- (NSRange) editedRange;
- (NSUInteger) editedMask;
- (NSInteger) changeInLength;
- (void) beginEditing;
- (void) endEditing;
- (void) replaceCharactersInRange: (NSRange) range withString: (NSString *) string;
- (void) addLayoutManager: (id) manager;
- (id) initWithContainerSize: (NSSize) size;
- (void) setLineFragmentPadding: (CGFloat) padding;
- (CGFloat) lineFragmentPadding;
- (void) setMaximumNumberOfLines: (NSUInteger) lines;
- (NSUInteger) maximumNumberOfLines;
- (void) setWidthTracksTextView: (BOOL) flag;
- (BOOL) widthTracksTextView;
- (void) setHeightTracksTextView: (BOOL) flag;
- (BOOL) heightTracksTextView;
- (NSSize) containerSize;
- (void) setContainerSize: (NSSize) size;
- (void) setTextContainer: (id) container;
@end

static void checkTextStorageAndContainer(void) {
    id storage = [[appKitClass("NSTextStorage") alloc] initWithString: @"hello"];
    [storage beginEditing];
    [storage replaceCharactersInRange: NSMakeRange(1, 2) withString: @"EYYY"];
    [storage endEditing];
    expect([[storage string] isEqual: @"hEYYYlo"], "NSTextStorage edit");
    id copy = [[appKitClass("NSTextStorage") alloc] initWithString: @"x"];
    [copy beginEditing];
    [copy replaceCharactersInRange: NSMakeRange(0, 1) withString: @"yz"];
    // inside an edit the range being changed is tracked in the extras
    expect([copy editedRange].location == 0 && [copy editedRange].length == 2, "NSTextStorage editedRange");
    expect([copy changeInLength] == 1, "NSTextStorage changeInLength");
    [copy endEditing];
    [copy release];
    [storage release];

    id container = [[appKitClass("NSTextContainer") alloc] initWithContainerSize: NSMakeSize(100, 50)];
    expect([container containerSize].width == 100 && [container containerSize].height == 50,
           "NSTextContainer size");
    [container setLineFragmentPadding: 3];
    [container setMaximumNumberOfLines: 7];
    [container setWidthTracksTextView: YES];
    [container setHeightTracksTextView: YES];
    expect([container lineFragmentPadding] == 3, "NSTextContainer lineFragmentPadding");
    expect([container maximumNumberOfLines] == 7, "NSTextContainer maximumNumberOfLines");
    expect([container widthTracksTextView] && [container heightTracksTextView],
           "NSTextContainer tracking flags");
    [container setWidthTracksTextView: NO];
    expect(![container widthTracksTextView] && [container heightTracksTextView],
           "NSTextContainer tracking flags independent");
    expect([container containerSize].width == 100, "NSTextContainer size unchanged");
    [container release];
}

// NSImageRep (0x1c) has no room for any extra state and NSBitmapImageRep
// (0x34) only one pointer; an application's subclass keeps its ivars after
// them
@interface NSImageRep : NSObject {
    void *_imageRepLayout[6];
}
@end

@interface NSBitmapImageRep : NSImageRep {
    void *_bitmapImageRepLayout[6];
}
@end

APP_SUBCLASS(AppBitmapImageRep, NSBitmapImageRep)

@interface NSObject (LegacyLayoutBitmapAPI)
- (id) initWithBitmapDataPlanes: (unsigned char **) planes
                     pixelsWide: (NSInteger) width
                     pixelsHigh: (NSInteger) height
                  bitsPerSample: (NSInteger) bitsPerSample
                samplesPerPixel: (NSInteger) samplesPerPixel
                       hasAlpha: (BOOL) hasAlpha
                       isPlanar: (BOOL) isPlanar
                 colorSpaceName: (NSString *) colorSpaceName
                    bytesPerRow: (NSInteger) bytesPerRow
                   bitsPerPixel: (NSInteger) bitsPerPixel;
- (NSInteger) pixelsWide;
- (NSInteger) pixelsHigh;
- (NSInteger) bitsPerSample;
- (NSInteger) samplesPerPixel;
- (NSInteger) bitsPerPixel;
- (NSInteger) bytesPerRow;
- (BOOL) hasAlpha;
- (BOOL) isOpaque;
- (BOOL) isPlanar;
- (void) setOpaque: (BOOL) flag;
- (void) setAlpha: (BOOL) flag;
- (unsigned char *) bitmapData;
- (NSString *) colorSpaceName;
- (void) setProperty: (NSString *) property withValue: (id) value;
- (id) valueForProperty: (NSString *) property;
@end

static void checkImageReps(void) {
#if !__OBJC2__
    expect(CANARY_OFFSET(AppBitmapImageRep) == 0x34, "test declares NSBitmapImageRep as 0x34 bytes");
#endif
    AppBitmapImageRep *rep = [[AppBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                      pixelsWide: 5
                                                                      pixelsHigh: 3
                                                                   bitsPerSample: 8
                                                                 samplesPerPixel: 4
                                                                        hasAlpha: YES
                                                                        isPlanar: NO
                                                                  colorSpaceName: @"NSCalibratedRGBColorSpace"
                                                                     bytesPerRow: 20
                                                                    bitsPerPixel: 32];
    expect(rep != nil, "NSBitmapImageRep created");
    fillCanary(rep->_canary);
    expect([rep pixelsWide] == 5 && [rep pixelsHigh] == 3, "NSImageRep pixel size");
    expect([rep bitsPerSample] == 8, "NSImageRep bitsPerSample");
    expect([rep hasAlpha] == YES && [rep isOpaque] == NO, "NSImageRep alpha flags");
    [rep setOpaque: YES];
    [rep setAlpha: NO];
    expect([rep hasAlpha] == NO && [rep isOpaque] == YES, "NSImageRep alpha flags set");
    [rep setOpaque: NO];
    [rep setAlpha: YES];
    expect([rep hasAlpha] == YES && [rep isOpaque] == NO, "NSImageRep alpha flags set again");
    expect([rep bitsPerSample] == 8 && [rep pixelsWide] == 5, "NSImageRep flags leave neighbours alone");
    expect([rep samplesPerPixel] == 4 && [rep bitsPerPixel] == 32 && [rep bytesPerRow] == 20,
           "NSBitmapImageRep layout");
    expect([rep isPlanar] == NO, "NSBitmapImageRep isPlanar");
    unsigned char *data = [rep bitmapData];
    expect(data != NULL, "NSBitmapImageRep bitmapData");
    if (data != NULL) {
        memset(data, 0x5a, 20 * 3);
        expect(data[0] == 0x5a && data[59] == 0x5a, "NSBitmapImageRep pixel storage");
    }
    [rep setProperty: @"legacyProperty" withValue: @"v"];
    expect(canaryIntact(rep->_canary), "NSBitmapImageRep subclass ivars intact");
    [rep release];
}

// An application's NSOpenGLContext subclass keeps its ivars after Apple's
// 0xc bytes. The context is only allocated (no GL driver is needed): the
// state AppKit keeps for a view must not touch the subclass's ivars.
@interface NSOpenGLContext : NSObject {
    void *_openGLContextLayout[2];
}
@end

APP_SUBCLASS(AppOpenGLContext, NSOpenGLContext)

@interface NSObject (LegacyLayoutOpenGLAPI)
- (void) setView: (id) view;
- (id) view;
@end

static void checkOpenGLContext(void) {
#if !__OBJC2__
    expect(CANARY_OFFSET(AppOpenGLContext) == 0xc, "test declares NSOpenGLContext as 0xc bytes");
#endif
    AppOpenGLContext *context = [AppOpenGLContext alloc];
    fillCanary(context->_canary);
    id view = [[appKitClass("NSView") alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
    expect([context view] == nil, "NSOpenGLContext has no view yet");
    [context setView: view];
    expect([context view] == view, "NSOpenGLContext view");
    expect(canaryIntact(context->_canary), "NSOpenGLContext subclass ivars intact");
    [context setView: nil];
    expect([context view] == nil, "NSOpenGLContext view cleared");
    expect(canaryIntact(context->_canary), "NSOpenGLContext subclass ivars intact after clearing");
    [view release];
    // the context is not released: it was never initialized with a pixel format
}

// NSColor is an abstract class cluster root of one word on the legacy ABI;
// the state of the concrete colors lives in their own classes
@interface NSObject (LegacyLayoutColorAPI)
+ (id) colorWithCalibratedRed: (CGFloat) red green: (CGFloat) green blue: (CGFloat) blue alpha: (CGFloat) alpha;
+ (id) colorWithCatalogName: (NSString *) catalog colorName: (NSString *) name;
+ (id) colorWithName: (NSString *) name dynamicProvider: (id (^)(id appearance)) provider;
+ (id) colorWithPatternImage: (id) image;
- (NSString *) catalogNameComponent;
- (NSString *) colorNameComponent;
- (NSString *) colorSpaceName;
- (id) patternImage;
@end

static void checkColor(void) {
    id rgb = [appKitClass("NSColor") colorWithCalibratedRed: 0.25 green: 0.5 blue: 0.75 alpha: 1];
    expect([[rgb catalogNameComponent] length] == 0, "NSColor component color has no catalog name");
    expect([rgb colorSpaceName] != nil, "NSColor component color space name");

    id image = [[appKitClass("NSImage") alloc] initWithSize: NSMakeSize(4, 4)];
    id pattern = [appKitClass("NSColor") colorWithPatternImage: image];
    expect([pattern patternImage] != nil, "NSColor pattern image");
    [image release];

    id catalog = [appKitClass("NSColor") colorWithCatalogName: @"System" colorName: @"controlTextColor"];
    expect([[catalog catalogNameComponent] isEqual: @"System"], "NSColor catalog name");
    expect([[catalog colorNameComponent] isEqual: @"controlTextColor"], "NSColor catalog color name");

    id dynamic = [appKitClass("NSColor") colorWithName: @"legacy.dynamic"
                                       dynamicProvider: ^id(id appearance) { return rgb; }];
    expect([[dynamic colorNameComponent] isEqual: @"legacy.dynamic"], "NSColor dynamic color name");
}

// NSFont keeps its state in the extra struct: the legacy size must not cost
// functionality
@interface NSObject (LegacyLayoutFontAPI)
+ (id) fontWithName: (NSString *) name size: (CGFloat) size;
- (CGFloat) pointSize;
- (NSString *) fontName;
- (CGFloat) ascender;
- (CGFloat) descender;
- (const CGFloat *) matrix;
@end

static void checkFont(void) {
    id font = [appKitClass("NSFont") systemFontOfSize: 13];
    expect([font pointSize] == 13, "NSFont pointSize");
    expect([[font fontName] length] > 0, "NSFont fontName");
    expect([font ascender] > 0 && [font descender] < 0, "NSFont ascender/descender");
    expect([font matrix] != NULL && [font matrix][0] == 13 && [font matrix][3] == 13,
           "NSFont matrix");
    id same = [appKitClass("NSFont") fontWithName: [font fontName] size: 13];
    expect([same pointSize] == 13 && [[same fontName] isEqual: [font fontName]],
           "NSFont fontWithName:size:");
    expect([font copy] == font, "NSFont copy returns itself");
    [font release]; // the copy
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [appKitClass("NSApplication") sharedApplication];
        checkTestDeclarations();
        checkLegacyLayout();
        checkResponderSubclass();
        checkViewSubclass();
        checkWindowSubclass();
        checkControlSubclasses();
        checkControllerSubclasses();
        checkCopies();
        checkTextStorageAndContainer();
        checkImageReps();
        checkOpenGLContext();
        checkColor();
        checkFont();
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
