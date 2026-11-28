// Copyright (C) 2026 Lubos Dolezel
//
// The private LaunchServices option dictionary on NSWorkspaceOpenConfiguration stores a copy and its background
// key maps to the public "do not switch" launch flag only when the value is truthy. The option is general: any
// caller that sets it gets the same launch behavior.
// Build: clang -framework AppKit <private include dir> appkit-launchservices-background-option.m
#import <AppKit/AppKit.h>
#import <AppKit/NSWorkspace+Private.h>
#include <LaunchServices/LSOpen.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *const BackgroundKey = @"_kLSOpenOptionBackgroundLaunchKey";

int main(void)
{
    @autoreleasepool {
        NSWorkspaceOpenConfiguration *plain = [NSWorkspaceOpenConfiguration configuration];
        CHECK(!([plain _launchFlags] & kLSLaunchDontSwitch));

        NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObject: [NSNumber numberWithBool: YES]
                                                                          forKey: BackgroundKey];
        [plain _setAdditionalLSOpenOptions: options];
        CHECK([[plain _additionalLSOpenOptions] isEqualToDictionary: options]);

        // The setter copies, so a caller mutating its dictionary cannot change the configuration.
        [options setObject: [NSNumber numberWithBool: NO] forKey: BackgroundKey];
        CHECK([[[plain _additionalLSOpenOptions] objectForKey: BackgroundKey] boolValue]);
        CHECK([plain _launchFlags] & kLSLaunchDontSwitch);

        NSWorkspaceOpenConfiguration *copied = [[plain copy] autorelease];
        CHECK(copied != plain);
        CHECK([[copied _additionalLSOpenOptions] isEqualToDictionary: [plain _additionalLSOpenOptions]]);
        CHECK([copied _launchFlags] & kLSLaunchDontSwitch);

        NSWorkspaceOpenConfiguration *disabled = [NSWorkspaceOpenConfiguration configuration];
        [disabled _setAdditionalLSOpenOptions: [NSDictionary dictionaryWithObject: [NSNumber numberWithBool: NO]
                                                                          forKey: BackgroundKey]];
        CHECK(!([disabled _launchFlags] & kLSLaunchDontSwitch));

        NSWorkspaceOpenConfiguration *nonBoolean = [NSWorkspaceOpenConfiguration configuration];
        [nonBoolean _setAdditionalLSOpenOptions: [NSDictionary dictionaryWithObject: @"YES"
                                                                             forKey: BackgroundKey]];
        CHECK(!([nonBoolean _launchFlags] & kLSLaunchDontSwitch));
    }

    if (failures == 0)
        printf("PASS: LaunchServices background option\n");
    return failures ? 1 : 0;
}
