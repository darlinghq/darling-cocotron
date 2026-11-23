/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Increase Contrast: the increaseContrast preference of com.apple.universalaccess drives
 * -[NSWorkspace accessibilityDisplayShouldIncreaseContrast], makes Aqua and Dark Aqua match their high contrast
 * variants in -bestMatchFromAppearancesWithNames: (their names stay), and a change announced to the application
 * posts NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification once. Expected values are what macOS 10.14.4
 * and 26.7.3 answer.
 */
#import <AppKit/AppKit.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

static void set_contrast(CFPropertyListRef value) {
    CFPreferencesSetAppValue(CFSTR("increaseContrast"), value, CFSTR("com.apple.universalaccess"));
    CFPreferencesAppSynchronize(CFSTR("com.apple.universalaccess"));
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
    if (_NSGetExecutablePath(selfPath, &selfPathSize) != 0)
        return 1;

    @autoreleasepool {
        [NSApplication sharedApplication];
        CFPropertyListRef original = CFPreferencesCopyAppValue(CFSTR("increaseContrast"), CFSTR("com.apple.universalaccess"));
        NSArray *all = @[NSAppearanceNameAqua, NSAppearanceNameAccessibilityHighContrastAqua,
                         NSAppearanceNameDarkAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua];
        NSArray *basic = @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua];
        NSAppearance *aqua = [NSAppearance appearanceNamed: NSAppearanceNameAqua];
        NSAppearance *dark = [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua];

        set_contrast(NULL);
        CHECK(![[NSWorkspace sharedWorkspace] accessibilityDisplayShouldIncreaseContrast]);
        CHECK([[aqua bestMatchFromAppearancesWithNames: all] isEqualToString: NSAppearanceNameAqua]);
        CHECK([[dark bestMatchFromAppearancesWithNames: all] isEqualToString: NSAppearanceNameDarkAqua]);

        __block int notifications = 0;
        id observer = [[[NSWorkspace sharedWorkspace] notificationCenter]
                addObserverForName: NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
                            object: nil
                             queue: nil
                        usingBlock: ^(NSNotification *n) { notifications++; }];

        set_contrast(kCFBooleanTrue);
        CHECK([[NSWorkspace sharedWorkspace] accessibilityDisplayShouldIncreaseContrast]);
        CHECK([[aqua bestMatchFromAppearancesWithNames: all] isEqualToString: NSAppearanceNameAccessibilityHighContrastAqua]);
        CHECK([[dark bestMatchFromAppearancesWithNames: all] isEqualToString: NSAppearanceNameAccessibilityHighContrastDarkAqua]);
        CHECK([[aqua bestMatchFromAppearancesWithNames: basic] isEqualToString: NSAppearanceNameAqua]);
        CHECK([[aqua name] isEqualToString: NSAppearanceNameAqua]);
        CHECK([[[NSApp effectiveAppearance] name] isEqualToString: NSAppearanceNameAqua] ||
              [[[NSApp effectiveAppearance] name] isEqualToString: NSAppearanceNameDarkAqua]);

        char command[1100];
        snprintf(command, sizeof(command), "'%s' --post AppleInterfaceThemeChangedNotification", selfPath);
        system(command);
        for (int i = 0; i < 50 && notifications == 0; i++) {
            usleep(10000);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, false);
        }
        CHECK(notifications == 1);
        // nothing changed: no second notification
        system(command);
        for (int i = 0; i < 30; i++) {
            usleep(10000);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, false);
        }
        CHECK(notifications == 1);

        set_contrast(NULL);
        system(command);
        for (int i = 0; i < 50 && notifications == 1; i++) {
            usleep(10000);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, false);
        }
        CHECK(notifications == 2);
        CHECK([[aqua bestMatchFromAppearancesWithNames: all] isEqualToString: NSAppearanceNameAqua]);

        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: observer];
        set_contrast(original);
        if (original != NULL)
            CFRelease(original);
    }
    if (g_failures) {
        printf("%d failure(s)\n", g_failures);
        return 1;
    }
    printf("ok\n");
    return 0;
}
