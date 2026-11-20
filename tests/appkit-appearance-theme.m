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

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

@interface NSColor (Internal)
+ (NSColor *) _accentColorForCode: (NSInteger) code;
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

int main(void)
{
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

        // Trigger change to Dark via distributed notification
        set_global_pref(CFSTR("AppleInterfaceStyle"), CFSTR("Dark"));
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFSTR("AppleInterfaceThemeChangedNotification"),
            NULL,
            NULL,
            TRUE
        );

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

        [NSApp removeObserver: appObserver forKeyPath: @"effectiveAppearance"];
        [window removeObserver: winObserver forKeyPath: @"effectiveAppearance"];
        [explicitWin removeObserver: explicitWinObserver forKeyPath: @"effectiveAppearance"];

        // 5. Pinned Mojave sRGB values for accent colors (-1 to 6)
        struct { NSInteger code; CGFloat r, g, b; } accentExpected[] = {
            { -1, 0.557, 0.557, 0.576 }, // Graphite
            {  0, 1.000, 0.231, 0.188 }, // Red
            {  1, 1.000, 0.584, 0.000 }, // Orange
            {  2, 1.000, 0.800, 0.000 }, // Yellow
            {  3, 0.157, 0.804, 0.255 }, // Green
            {  4, 0.000, 0.478, 1.000 }, // Blue
            {  5, 0.686, 0.322, 0.871 }, // Purple
            {  6, 1.000, 0.176, 0.333 }, // Pink
        };
#if DARLING
        for (size_t i = 0; i < sizeof(accentExpected) / sizeof(accentExpected[0]); i++) {
            NSColor *color = [NSColor _accentColorForCode: accentExpected[i].code];
            if (!near(color, accentExpected[i].r, accentExpected[i].g, accentExpected[i].b, 1.0)) {
                printf("FAIL: _accentColorForCode %ld\n", (long)accentExpected[i].code);
                g_failures++;
            }
        }
#endif
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
        CHECK(lightCtrlW > 0.8 && darkCtrlW < 0.3);
        CHECK(fabs(lightWinR - 0.925) < 0.01 && fabs(darkWinR - 0.20) < 0.02);

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
