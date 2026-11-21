// Copyright (C) 2026 Darling Developers
// Tests for macOS desktop appearance and theme adaptation:
// - AppleInterfaceStyle mapping to effectiveAppearance (Aqua vs DarkAqua)
// - NSRequiresAquaSystemAppearance override
// - Distributed notification AppleInterfaceThemeChangedNotification
// - KVO on effectiveAppearance and recursive viewDidChangeEffectiveAppearance
// - Measured macOS 10.14 Mojave sRGB values for accent colors (-1 to 6)
// - currentControlTint following AppleAquaColorVariant and AppleAccentColor
// - selectedTextBackgroundColor following AppleHighlightColor
// - Dynamic system color adaptation under light and dark appearances
#import <AppKit/AppKit.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <math.h>
#include <unistd.h>
#include <string.h>
#include <mach-o/dyld.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

@interface NSColor (Internal)
+ (NSColor *) _accentColorForCode: (NSInteger) code;
+ (NSColor *) _accentColorForCode: (NSInteger) code dark: (BOOL) dark;
@end

@interface NSLayoutConstraint (DeactivateStub)
+ (void) deactivateConstraints: (NSArray *) constraints;
@end
@implementation NSLayoutConstraint (DeactivateStub)
+ (void) deactivateConstraints: (NSArray *) constraints {}
@end

static BOOL near(NSColor *c, CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
    c = [c colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    return c && fabs([c redComponent] - r) < 0.005 && fabs([c greenComponent] - g) < 0.005 &&
           fabs([c blueComponent] - b) < 0.005 && fabs([c alphaComponent] - a) < 0.005;
}

@interface TestAppearanceView : NSView {
@public
    int appearanceChangeCount;
}
@end

@implementation TestAppearanceView
- (void) viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    appearanceChangeCount++;
}
@end

@interface KVOObserver : NSObject {
@public
    int kvoCount;
}
@end

@implementation KVOObserver
- (void) observeValueForKeyPath: (NSString *) keyPath
                       ofObject: (id) object
                         change: (NSDictionary *) change
                        context: (void *) context
{
    if ([keyPath isEqualToString: @"effectiveAppearance"]) {
        kvoCount++;
    }
}
@end

static void set_global_pref(CFStringRef key, CFPropertyListRef val) {
    CFPreferencesSetValue(key, val, kCFPreferencesAnyApplication,
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication);
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// Posts a distributed notification from a separate process, the way settingsd does.
static void post_from_other_process(const char *selfPath, const char *name) {
    char command[1024];
    snprintf(command, sizeof(command), "'%s' --post %s", selfPath, name);
    system(command);
}

int main(int argc, char **argv)
{
    if (argc == 3 && strcmp(argv[1], "--post") == 0) {
        CFStringRef name = CFStringCreateWithCString(NULL, argv[2], kCFStringEncodingUTF8);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(), name, NULL, NULL, TRUE);
        CFRelease(name);
        return 0;
    }
    char selfPath[1024];
    uint32_t selfPathSize = sizeof(selfPath);
    if (_NSGetExecutablePath(selfPath, &selfPathSize) != 0) {
        printf("FAIL: executable path\n");
        return 1;
    }
    @autoreleasepool {
        [NSApplication sharedApplication];

        // Save original defaults to restore at exit
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        id origStyle = [[[defs objectForKey: @"AppleInterfaceStyle"] retain] autorelease];
        id origAccent = [[[defs objectForKey: @"AppleAccentColor"] retain] autorelease];
        id origVariant = [[[defs objectForKey: @"AppleAquaColorVariant"] retain] autorelease];
        id origHighlight = [[[defs objectForKey: @"AppleHighlightColor"] retain] autorelease];
        id origReqAqua = [[[defs objectForKey: @"NSRequiresAquaSystemAppearance"] retain] autorelease];

        // 1. Initial / default appearance is Aqua
        set_global_pref(CFSTR("AppleInterfaceStyle"), NULL);
        set_global_pref(CFSTR("AppleAccentColor"), NULL);
        set_global_pref(CFSTR("AppleAquaColorVariant"), NULL);
        set_global_pref(CFSTR("AppleHighlightColor"), NULL);
        set_global_pref(CFSTR("NSRequiresAquaSystemAppearance"), NULL);

        NSAppearance *eff = [NSApp effectiveAppearance];
        CHECK([[eff name] isEqualToString: NSAppearanceNameAqua]);

        // 2. Setting AppleInterfaceStyle to "Dark" gives DarkAqua
        set_global_pref(CFSTR("AppleInterfaceStyle"), CFSTR("Dark"));
        eff = [NSApp effectiveAppearance];
        CHECK([[eff name] isEqualToString: NSAppearanceNameDarkAqua]);

        // 3. Setting NSRequiresAquaSystemAppearance forces Aqua even in Dark style
        set_global_pref(CFSTR("NSRequiresAquaSystemAppearance"), (CFPropertyListRef)@YES);
        eff = [NSApp effectiveAppearance];
        CHECK([[eff name] isEqualToString: NSAppearanceNameAqua]);

        // Clear NSRequiresAquaSystemAppearance
        set_global_pref(CFSTR("NSRequiresAquaSystemAppearance"), NULL);
        eff = [NSApp effectiveAppearance];
        CHECK([[eff name] isEqualToString: NSAppearanceNameDarkAqua]);

        // Reset to Light (Aqua)
        set_global_pref(CFSTR("AppleInterfaceStyle"), NULL);
        eff = [NSApp effectiveAppearance];
        CHECK([[eff name] isEqualToString: NSAppearanceNameAqua]);

        // 4. Test KVO on effectiveAppearance and recursive viewDidChangeEffectiveAppearance
        KVOObserver *appObserver = [[[KVOObserver alloc] init] autorelease];
        [NSApp addObserver: appObserver
                forKeyPath: @"effectiveAppearance"
                   options: NSKeyValueObservingOptionNew
                   context: NULL];

        NSWindow *window = [[[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 200)
                                                        styleMask: NSWindowStyleMaskTitled
                                                          backing: NSBackingStoreBuffered
                                                            defer: NO] autorelease];
        KVOObserver *winObserver = [[[KVOObserver alloc] init] autorelease];
        [window addObserver: winObserver
                 forKeyPath: @"effectiveAppearance"
                    options: NSKeyValueObservingOptionNew
                    context: NULL];

        TestAppearanceView *contentView = [[[TestAppearanceView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)] autorelease];
        TestAppearanceView *subview = [[[TestAppearanceView alloc] initWithFrame: NSMakeRect(10, 10, 100, 100)] autorelease];
        [contentView addSubview: subview];
        [window setContentView: contentView];

        // Window with an explicit appearance must NOT receive KVO or subview changes on theme change
        NSWindow *explicitWin = [[[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 200)
                                                             styleMask: NSWindowStyleMaskTitled
                                                               backing: NSBackingStoreBuffered
                                                                 defer: NO] autorelease];
        [explicitWin setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameAqua]];
        KVOObserver *explicitWinObserver = [[[KVOObserver alloc] init] autorelease];
        [explicitWin addObserver: explicitWinObserver
                      forKeyPath: @"effectiveAppearance"
                         options: NSKeyValueObservingOptionNew
                         context: NULL];
        TestAppearanceView *explicitView = [[[TestAppearanceView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)] autorelease];
        [explicitWin setContentView: explicitView];

        __block int colorsChangedCount = 0;
        id colorsObserver = [[NSNotificationCenter defaultCenter] addObserverForName: NSSystemColorsDidChangeNotification
                                                                              object: nil
                                                                               queue: nil
                                                                          usingBlock: ^(NSNotification *n) { colorsChangedCount++; }];

        // Trigger change to Dark via a distributed notification posted by another process
        set_global_pref(CFSTR("AppleInterfaceStyle"), CFSTR("Dark"));
        post_from_other_process(selfPath, "AppleInterfaceThemeChangedNotification");

        for (int i = 0; i < 50 && (appObserver->kvoCount == 0); i++) {
            usleep(10000);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, false);
        }

        CHECK(appObserver->kvoCount == 1);
        CHECK(winObserver->kvoCount == 1);
        CHECK(explicitWinObserver->kvoCount == 0);
        CHECK(contentView->appearanceChangeCount >= 1);
        CHECK(subview->appearanceChangeCount >= 1);
        CHECK(explicitView->appearanceChangeCount == 0);
        // the style changed, the accent and highlight did not
        CHECK(colorsChangedCount == 0);

        // a notification without a change reports nothing
        post_from_other_process(selfPath, "AppleInterfaceThemeChangedNotification");
        for (int i = 0; i < 30; i++) {
            usleep(10000);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, false);
        }
        CHECK(appObserver->kvoCount == 1);
        CHECK(colorsChangedCount == 0);

        // an accent change is announced as AppleColorPreferencesChangedNotification
        set_global_pref(CFSTR("AppleAccentColor"), (CFPropertyListRef)@(5));
        post_from_other_process(selfPath, "AppleColorPreferencesChangedNotification");
        for (int i = 0; i < 50 && colorsChangedCount == 0; i++) {
            usleep(10000);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, false);
        }
        CHECK(colorsChangedCount == 1);
        CHECK(appObserver->kvoCount == 1);
        [[NSNotificationCenter defaultCenter] removeObserver: colorsObserver];

        [NSApp removeObserver: appObserver forKeyPath: @"effectiveAppearance"];
        [window removeObserver: winObserver forKeyPath: @"effectiveAppearance"];
        [explicitWin removeObserver: explicitWinObserver forKeyPath: @"effectiveAppearance"];

        // 5. Pinned sRGB values of the accent colours (-1 to 6), light appearance, read on macOS 10.14.4
        struct { NSInteger code; CGFloat r, g, b; } accentExpected[] = {
            { -1, 0.596, 0.596, 0.596 }, // Graphite
            {  0, 0.878, 0.220, 0.243 }, // Red
            {  1, 0.969, 0.510, 0.106 }, // Orange
            {  2, 0.988, 0.722, 0.153 }, // Yellow
            {  3, 0.384, 0.729, 0.275 }, // Green
            {  4, 0.000, 0.478, 1.000 }, // Blue
            {  5, 0.584, 0.239, 0.588 }, // Purple
            {  6, 0.969, 0.310, 0.620 }, // Pink
        };
#if DARLING
        // the accents that differ in the dark appearance (read on macOS 10.14.4 and 26.7.3)
        CHECK(near([NSColor _accentColorForCode: -1 dark: YES], 0.549, 0.549, 0.549, 1.0));
        CHECK(near([NSColor _accentColorForCode: 0 dark: YES], 1.000, 0.322, 0.341, 1.0));
        CHECK(near([NSColor _accentColorForCode: 5 dark: YES], 0.647, 0.314, 0.655, 1.0));
        CHECK(near([NSColor _accentColorForCode: 4 dark: YES], 0.000, 0.478, 1.000, 1.0));
        for (size_t i = 0; i < sizeof(accentExpected) / sizeof(accentExpected[0]); i++) {
            NSColor *color = [NSColor _accentColorForCode: accentExpected[i].code];
            if (!near(color, accentExpected[i].r, accentExpected[i].g, accentExpected[i].b, 1.0)) {
                printf("FAIL: _accentColorForCode %ld\n", (long)accentExpected[i].code);
                g_failures++;
            }
        }
#endif
        // the light values: Red, Graphite and Purple differ in the dark appearance
        [NSAppearance setCurrentAppearance: [NSAppearance appearanceNamed: NSAppearanceNameAqua]];
        for (size_t i = 0; i < sizeof(accentExpected) / sizeof(accentExpected[0]); i++) {
            set_global_pref(CFSTR("AppleAccentColor"), (CFPropertyListRef)@(accentExpected[i].code));
            NSColor *viaCatalog = [NSColor controlAccentColor];
            if (!near(viaCatalog, accentExpected[i].r, accentExpected[i].g, accentExpected[i].b, 1.0)) {
                printf("FAIL: controlAccentColor for code %ld\n", (long)accentExpected[i].code);
                g_failures++;
            }
        }

        // 6. currentControlTint
        set_global_pref(CFSTR("AppleAquaColorVariant"), (CFPropertyListRef)@(6));
        set_global_pref(CFSTR("AppleAccentColor"), NULL);
        CHECK([NSColor currentControlTint] == NSGraphiteControlTint);

        set_global_pref(CFSTR("AppleAquaColorVariant"), NULL);
        set_global_pref(CFSTR("AppleAccentColor"), (CFPropertyListRef)@(-1));
        CHECK([NSColor currentControlTint] == NSGraphiteControlTint);

        set_global_pref(CFSTR("AppleAccentColor"), (CFPropertyListRef)@(4));
        CHECK([NSColor currentControlTint] == NSBlueControlTint);
        CHECK([NSColor currentControlTint] != NSDefaultControlTint);

        // 7. selectedTextBackgroundColor follows AppleHighlightColor
        set_global_pref(CFSTR("AppleHighlightColor"), CFSTR("0.25 0.50 0.75"));
        NSColor *highlight = [NSColor selectedTextBackgroundColor];
        CHECK(near(highlight, 0.25, 0.50, 0.75, 1.0));

        // Default highlight in Aqua is Mojave blue (0.698039, 0.843137, 1.0)
        set_global_pref(CFSTR("AppleHighlightColor"), NULL);
        set_global_pref(CFSTR("AppleInterfaceStyle"), NULL);
        highlight = [NSColor selectedTextBackgroundColor];
        CHECK(near(highlight, 0.698039, 0.843137, 1.0, 1.0));

        // 8. Dynamic system color resolution under Aqua vs DarkAqua
        NSAppearance *aqua = [NSAppearance appearanceNamed: NSAppearanceNameAqua];
        NSAppearance *darkAqua = [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua];

        NSColor *textColor = [NSColor textColor];
        NSColor *controlColor = [NSColor controlColor];
        NSColor *windowBg = [NSColor windowBackgroundColor];

        __block CGFloat lightTextW = 1.0, darkTextW = 0.0;
        __block CGFloat lightCtrlW = 0.0, darkCtrlW = 1.0;
        __block CGFloat lightWinR = 0.0, darkWinR = 1.0;

        [aqua performAsCurrentDrawingAppearance: ^{
            NSColor *resolvedText = [textColor colorUsingColorSpaceName: NSCalibratedWhiteColorSpace];
            NSColor *resolvedCtrl = [controlColor colorUsingColorSpaceName: NSCalibratedWhiteColorSpace];
            NSColor *resolvedWin = [windowBg colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
            lightTextW = [resolvedText whiteComponent];
            lightCtrlW = [resolvedCtrl whiteComponent];
            lightWinR = [resolvedWin redComponent];
        }];

        [darkAqua performAsCurrentDrawingAppearance: ^{
            NSColor *resolvedText = [textColor colorUsingColorSpaceName: NSCalibratedWhiteColorSpace];
            NSColor *resolvedCtrl = [controlColor colorUsingColorSpaceName: NSCalibratedWhiteColorSpace];
            NSColor *resolvedWin = [windowBg colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
            darkTextW = [resolvedText whiteComponent];
            darkCtrlW = [resolvedCtrl whiteComponent];
            darkWinR = [resolvedWin redComponent];
        }];

        CHECK(lightTextW < 0.1 && darkTextW > 0.9);
        CHECK(lightCtrlW > 0.8);
        (void) darkCtrlW;
        CHECK(fabs(lightWinR - 0.925) < 0.01 && fabs(darkWinR - 0.196) < 0.01);

        // The dark values of the system colours, read on macOS 10.14.4 (sRGB) in the DarkAqua appearance.
        static const struct { NSString *name; CGFloat r, g, b, a; } darkExpected[] = {
            { @"windowBackgroundColor", 0.196, 0.196, 0.196, 1.0 },
            { @"controlColor", 1.0, 1.0, 1.0, 0.247 },
            { @"controlBackgroundColor", 0.118, 0.118, 0.118, 1.0 },
            { @"textBackgroundColor", 0.118, 0.118, 0.118, 1.0 },
            { @"controlTextColor", 1.0, 1.0, 1.0, 0.847 },
            { @"selectedControlTextColor", 1.0, 1.0, 1.0, 0.847 },
            { @"selectedControlColor", 0.247, 0.388, 0.545, 1.0 },
            { @"selectedTextBackgroundColor", 0.247, 0.388, 0.545, 1.0 },
            { @"gridColor", 1.0, 1.0, 1.0, 0.098 },
            { @"headerTextColor", 1.0, 1.0, 1.0, 1.0 },
            { @"alternatingContentBackgroundColor", 1.0, 1.0, 1.0, 0.047 },
            { @"disabledControlTextColor", 1.0, 1.0, 1.0, 0.247 },
            { @"highlightColor", 0.706, 0.706, 0.706, 1.0 },
            { @"linkColor", 0.255, 0.612, 1.0, 1.0 },
            { @"keyboardFocusIndicatorColor", 0.102, 0.663, 1.0, 0.298 },
        };
        set_global_pref(CFSTR("AppleHighlightColor"), NULL);
        set_global_pref(CFSTR("AppleAccentColor"), NULL);
        for (size_t i = 0; i < sizeof(darkExpected) / sizeof(darkExpected[0]); i++) {
            NSColor *c = [NSColor performSelector: NSSelectorFromString(darkExpected[i].name)];
            __block BOOL ok = NO;
            [darkAqua performAsCurrentDrawingAppearance: ^{
                ok = near(c, darkExpected[i].r, darkExpected[i].g, darkExpected[i].b, darkExpected[i].a);
            }];
            if (!ok) {
                printf("FAIL: dark %s\n", [darkExpected[i].name UTF8String]);
                g_failures++;
            }
        }

        // The selection colours follow the accent/highlight preset (read on macOS 10.14.4, {light, dark}): Purple.
        set_global_pref(CFSTR("AppleAccentColor"), (CFPropertyListRef)@(5));
        {
            static const struct { NSString *name; CGFloat r, g, b, a; } purpleExpected[2][3] = {
                { { @"selectedControlColor", 0.875, 0.773, 0.875, 1.0 },
                  { @"selectedContentBackgroundColor", 0.490, 0.165, 0.494, 1.0 },
                  { @"keyboardFocusIndicatorColor", 0.514, 0.149, 0.518, 0.247 } },
                { { @"selectedControlColor", 0.439, 0.337, 0.439, 1.0 },
                  { @"selectedContentBackgroundColor", 0.498, 0.196, 0.502, 1.0 },
                  { @"keyboardFocusIndicatorColor", 0.859, 0.471, 0.871, 0.298 } },
            };
            NSAppearance *appearances[2] = { aqua, darkAqua };
            set_global_pref(CFSTR("AppleHighlightColor"), CFSTR("0.968627 0.831373 1.000000 Purple"));
            for (int a = 0; a < 2; a++) {
                for (int c = 0; c < 3; c++) {
                    NSColor *color = [NSColor performSelector: NSSelectorFromString(purpleExpected[a][c].name)];
                    __block BOOL ok = NO;
                    [appearances[a] performAsCurrentDrawingAppearance: ^{
                        ok = near(color, purpleExpected[a][c].r, purpleExpected[a][c].g, purpleExpected[a][c].b, purpleExpected[a][c].a);
                    }];
                    if (!ok) {
                        printf("FAIL: purple %s (%s)\n", [purpleExpected[a][c].name UTF8String], a ? "dark" : "light");
                        g_failures++;
                    }
                }
            }
        }

        // Restore original defaults
        set_global_pref(CFSTR("AppleInterfaceStyle"), (CFPropertyListRef)origStyle);
        set_global_pref(CFSTR("AppleAccentColor"), (CFPropertyListRef)origAccent);
        set_global_pref(CFSTR("AppleAquaColorVariant"), (CFPropertyListRef)origVariant);
        set_global_pref(CFSTR("AppleHighlightColor"), (CFPropertyListRef)origHighlight);
        set_global_pref(CFSTR("NSRequiresAquaSystemAppearance"), (CFPropertyListRef)origReqAqua);
    }

    if (g_failures) {
        printf("%d failure(s)\n", g_failures);
        return 1;
    }
    printf("ok\n");
    return 0;
}
