/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

#import <AppKit/NSWorkspace.h>
#include <LaunchServices/LSOpen.h>

// The LaunchServices flags Darling derives from a public open configuration and its private options.
APPKIT_EXPORT LSLaunchFlags NSWorkspaceLaunchFlagsForConfiguration(NSWorkspaceOpenConfiguration *configuration);

// QUIRK: NSWorkspaceOpenConfiguration accepts a private dictionary of LaunchServices options, including
// _kLSOpenOptionBackgroundLaunchKey, whose truthy value keeps the launched application in the background.
// Not documented. Evidence: Chromium's BSD-licensed launch_services_spi.h and WebKit's BSD-licensed
// LaunchServicesSPI.h declare the property/key (tier 3, public source of independent Cocoa clients). No
// OS-version dependence is known.
// https://chromium.googlesource.com/chromium/src/+/731fa51dac6814748b0943d8e4a61698fbe099c5/base/mac/launch_services_spi.h
// https://github.com/WebKit/WebKit/blob/main/Source/WebCore/PAL/pal/spi/cocoa/LaunchServicesSPI.h
// Test: appkit-launchservices-background-option.
@interface NSWorkspaceOpenConfiguration (NSLaunchServicesOptions)
@property(nonatomic, readwrite, copy, setter=_setAdditionalLSOpenOptions:) NSDictionary<NSString *, id> *_additionalLSOpenOptions;
@end
