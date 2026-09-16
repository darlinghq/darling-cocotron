#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <execinfo.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

// Wayland backend M1 test: a window with coloured views, a label and a text view. Every NSEvent the
// window receives is printed, so runs can be checked against injected input and screenshots.

static void logLine(const char *format, ...) __attribute__((format(printf, 1, 2)));
static void logLine(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);
    fflush(stdout);
}

// A second window, hidden and shown again on right click. (AppKit terminates the app once no
// non-panel window is visible, so the main window stays up.)
static NSWindow *gSecondWindow;
static NSCursor *gImageCursor;
static unsigned gMenuActions;

static NSCursor *imageCursor(void) {
    BOOL unpremultiplied = getenv("UNPREMULT_CURSOR") != NULL;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL pixelsWide:32 pixelsHigh:24
            bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
            colorSpaceName:NSDeviceRGBColorSpace
            bitmapFormat:unpremultiplied ? NSAlphaNonpremultipliedBitmapFormat : 0
            bytesPerRow:128 bitsPerPixel:32];
    unsigned char *bytes = [rep bitmapData];
    for (int y = 0; y < 24; y++) {
        for (int x = 0; x < 32; x++) {
            unsigned char *pixel = bytes + y * [rep bytesPerRow] + x * 4;
            // Premultiplied RGBA: opaque left, transparent middle, half-alpha right.
            unsigned char alpha = x < 16 ? 255 : (x < 24 ? 0 : 128);
            unsigned char color = unpremultiplied ? 255 : alpha;
            pixel[0] = y < 12 ? color : 0;
            pixel[1] = y < 12 ? 0 : color;
            pixel[2] = color;
            pixel[3] = alpha;
        }
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(32, 24)];
    [image addRepresentation:rep];
    NSCursor *cursor = [[NSCursor alloc] initWithImage:image hotSpot:NSMakePoint(5, 7)];
    [image release];
    [rep release];
    return cursor;
}

static const char *typeName(NSEventType type) {
    switch (type) {
    case NSLeftMouseDown: return "LeftMouseDown";
    case NSLeftMouseUp: return "LeftMouseUp";
    case NSRightMouseDown: return "RightMouseDown";
    case NSRightMouseUp: return "RightMouseUp";
    case NSOtherMouseDown: return "OtherMouseDown";
    case NSOtherMouseUp: return "OtherMouseUp";
    case NSMouseMoved: return "MouseMoved";
    case NSLeftMouseDragged: return "LeftMouseDragged";
    case NSRightMouseDragged: return "RightMouseDragged";
    case NSScrollWheel: return "ScrollWheel";
    case NSKeyDown: return "KeyDown";
    case NSKeyUp: return "KeyUp";
    case NSFlagsChanged: return "FlagsChanged";
    default: return NULL;
    }
}

@interface ColorView : NSView {
    NSColor *_color;
    const char *_name;
}
- (instancetype)initWithFrame:(NSRect)frame color:(NSColor *)color name:(const char *)name;
@end

@implementation ColorView
- (instancetype)initWithFrame:(NSRect)frame color:(NSColor *)color name:(const char *)name
{
    if ((self = [super initWithFrame:frame])) {
        _color = [color retain];
        _name = name;
    }
    return self;
}
- (void)drawRect:(NSRect)rect
{
    [_color set];
    NSRectFill([self bounds]);
    if (getenv("HIDPI_TEST") && strcmp(_name, "red") == 0) {
        [[NSColor whiteColor] set];
        NSRectFill(NSMakeRect(10, 10, 0.5, 40));
        CGAffineTransform device = CGContextGetCTM([[NSGraphicsContext currentContext] graphicsPort]);
        logLine("drawing device scale %.1f,%.1f screen scale %.1f\n", device.a, device.d,
                [[NSScreen mainScreen] backingScaleFactor]);
    }
    logLine("draw %s %.0fx%.0f\n", _name, [self bounds].size.width, [self bounds].size.height);
}
- (void)resetCursorRects
{
    if (gImageCursor != nil && strcmp(_name, "red") == 0)
        [self addCursorRect:[self bounds] cursor:gImageCursor];
}
- (void)mouseDown:(NSEvent *)event
{
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    logLine("view %s mouseDown at %.0f,%.0f clicks=%ld button=%ld\n", _name, p.x, p.y, (long)[event clickCount],
            (long)[event buttonNumber]);
    if (getenv("POPUP_TEST") && strcmp(_name, "green") == 0) {
        NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Wayland popup test"] autorelease];
        [menu setAutoenablesItems:NO];
        NSMenuItem *branch = [[[NSMenuItem alloc] initWithTitle:@"Branch" action:NULL keyEquivalent:@""] autorelease];
        NSMenu *nested = [[[NSMenu alloc] initWithTitle:@"Nested"] autorelease];
        [nested setAutoenablesItems:NO];
        NSMenuItem *leaf = [nested addItemWithTitle:@"Leaf" action:@selector(menuAction:) keyEquivalent:@""];
        [leaf setTarget:self];
        [branch setSubmenu:nested];
        [menu addItem:branch];
        NSMenuItem *select = [menu addItemWithTitle:@"Select" action:@selector(menuAction:) keyEquivalent:@""];
        [select setTarget:self];
        logLine("popup opening actions=%u\n", gMenuActions);
        [NSMenu popUpContextMenu:menu withEvent:event forView:self];
        logLine("popup returned actions=%u\n", gMenuActions);
    }
}
- (void)menuAction:(id)sender
{
    logLine("popup action %s count=%u\n", [[sender title] UTF8String], ++gMenuActions);
}
- (void)mouseUp:(NSEvent *)event
{
    logLine("view %s mouseUp\n", _name);
}
- (void)rightMouseDown:(NSEvent *)event
{
    // Hide and show the second window: exercises unmapping and remapping a toplevel.
    logLine("view %s rightMouseDown: ordering the second window out and back in\n", _name);
    [gSecondWindow orderOut:nil];
    logLine("second window visible=%d\n", [gSecondWindow isVisible]);
    [gSecondWindow performSelector:@selector(orderFront:) withObject:nil afterDelay:1.5];
}
- (void)scrollWheel:(NSEvent *)event
{
    logLine("view %s scrollWheel dx=%.2f dy=%.2f\n", _name, [event deltaX], [event deltaY]);
}
@end

@interface LogWindow : NSWindow
@end

@implementation LogWindow
- (void)sendEvent:(NSEvent *)event
{
    const char *name = typeName([event type]);
    if (name != NULL) {
        NSPoint p = [event locationInWindow];
        if ([event type] == NSKeyDown || [event type] == NSKeyUp)
            logLine("event %s chars=\"%s\" ignoring=\"%s\" keyCode=%u flags=0x%lx repeat=%d\n", name,
                    [[event characters] UTF8String], [[event charactersIgnoringModifiers] UTF8String],
                    [event keyCode], (unsigned long)[event modifierFlags], [event isARepeat]);
        else
            logLine("event %s at %.1f,%.1f clicks=%ld flags=0x%lx\n", name, p.x, p.y, (long)[event clickCount],
                    (unsigned long)[event modifierFlags]);
    }
    [super sendEvent:event];
}
@end

@interface Delegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
    LogWindow *_window;
    NSTextView *_text;
}
@end

@implementation Delegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    id display = [NSClassFromString(@"NSDisplay") performSelector:@selector(currentDisplay)];
    logLine("backend %s\n", object_getClassName(display));
    if (getenv("IMAGE_CURSOR") && strcmp(object_getClassName(display), "WaylandDisplay") == 0) {
        gImageCursor = imageCursor();
        logLine("image cursor created 32x24 hotspot=5,7\n");
    }

    _window = [[LogWindow alloc] initWithContentRect:NSMakeRect(100, 100, 600, 400)
                                           styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                     NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                             backing:NSBackingStoreBuffered
                                               defer:NO];
    [_window setTitle:@"Wayland M1 test"];
    // The state timer keeps using the window after the compositor closes it.
    [_window setReleasedWhenClosed:NO];
    [_window setDelegate:self];
    [_window setAcceptsMouseMovedEvents:getenv("MOUSE_MOVED") != NULL];
    NSView *content = [_window contentView];

    NSArray *colors = @[ [NSColor redColor], [NSColor greenColor], [NSColor blueColor] ];
    const char *names[] = {"red", "green", "blue"};
    for (int i = 0; i < 3; i++) {
        ColorView *view = [[ColorView alloc] initWithFrame:NSMakeRect(20 + i * 195, 220, 170, 160)
                                                     color:colors[i]
                                                      name:names[i]];
        [view setAutoresizingMask:NSViewMinYMargin];
        [content addSubview:view];
    }

    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 180, 560, 30)];
    [label setStringValue:@"Hello Wayland from Darling"];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont systemFontOfSize:20]];
    [label setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
    [content addSubview:label];

    _text = [[NSTextView alloc] initWithFrame:NSMakeRect(20, 20, 560, 150)];
    [_text setFont:[NSFont systemFontOfSize:18]];
    [_text setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview:_text];

    gSecondWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(750, 300, 300, 200)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [gSecondWindow setTitle:@"Wayland M1 second"];
    [gSecondWindow setReleasedWhenClosed:NO];
    ColorView *yellow = [[ColorView alloc] initWithFrame:NSMakeRect(20, 20, 260, 160)
                                                   color:[NSColor yellowColor]
                                                    name:"yellow"];
    [yellow setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[gSecondWindow contentView] addSubview:yellow];
    [gSecondWindow orderFront:nil];

    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_text];
    logLine("window shown frame=%s\n", [NSStringFromRect([_window frame]) UTF8String]);

    [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(dump:) userInfo:nil repeats:YES];
    const char *exitAfter = getenv("EXIT_AFTER");
    [NSTimer scheduledTimerWithTimeInterval:exitAfter ? atof(exitAfter) : 60.0
                                     target:self
                                   selector:@selector(quit:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)dump:(NSTimer *)timer
{
    logLine("state frame=%s key=%d visible=%d text=\"%s\"\n", [NSStringFromRect([_window frame]) UTF8String],
            [_window isKeyWindow], [_window isVisible], [[_text string] UTF8String]);
}

- (void)windowDidResize:(NSNotification *)notification
{
    logLine("windowDidResize %s\n", [NSStringFromRect([_window frame]) UTF8String]);
}
- (void)windowDidBecomeKey:(NSNotification *)notification
{
    logLine("windowDidBecomeKey\n");
}
- (void)windowDidResignKey:(NSNotification *)notification
{
    logLine("windowDidResignKey\n");
}
- (BOOL)windowShouldClose:(id)sender
{
    logLine("windowShouldClose\n");
    return YES;
}
- (void)windowWillClose:(NSNotification *)notification
{
    logLine("windowWillClose\n");
}
- (void)quit:(NSTimer *)timer
{
    logLine("quit\n");
    exit(0);
}
@end

static void crashHandler(int sig)
{
    void *frames[64];
    int count = backtrace(frames, 64);
    dprintf(1, "crash signal %d, backtrace:\n", sig);
    backtrace_symbols_fd(frames, count, 1);
    _exit(128 + sig);
}

static void atExit(void)
{
    dprintf(1, "atexit\n");
}

int main(int argc, const char **argv)
{
    signal(SIGSEGV, crashHandler);
    signal(SIGBUS, crashHandler);
    signal(SIGABRT, crashHandler);
    signal(SIGILL, crashHandler);
    atexit(atExit);
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setDelegate:[Delegate new]];
        [app run];
    }
    return 0;
}
