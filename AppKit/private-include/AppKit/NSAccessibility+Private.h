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

#import <AppKit/AppKitExport.h>
#import <Foundation/Foundation.h>

// AppKit's internal delivery path for accessibility notifications. Assistive technology bridges register
// here; the public NSAccessibilityPostNotification entry points fan out to every registered handler.
typedef void (*NSAccessibilityNotificationHandler)(id element,
                                                   NSString *notification,
                                                   NSDictionary *userInfo,
                                                   void *context);

APPKIT_EXPORT void NSAccessibilityRegisterNotificationHandler(NSAccessibilityNotificationHandler handler,
                                                               void *context);
APPKIT_EXPORT void NSAccessibilityUnregisterNotificationHandler(NSAccessibilityNotificationHandler handler,
                                                                 void *context);
APPKIT_EXPORT void NSAccessibilityDeliverNotification(id element,
                                                       NSString *notification,
                                                       NSDictionary *userInfo);

// QUIRK: NSAccessibilityHandleFocusChanged asks assistive clients to query the focused element again and posts
// the focused-element notification without an element of its own. Not documented. Evidence: WebKit's
// BSD-licensed WebCore accessibility code and LibreOffice's MPL-2.0/LGPL Cocoa a11y code call this private entry
// point (tier 3, independent public Cocoa clients), and WebCore documents that AppKit queries the focused
// element synchronously from within it. No OS-version dependence is known.
// https://github.com/WebKit/WebKit/blob/main/Source/WebCore/accessibility/mac/AXObjectCacheMac.mm
// Test: appkit-accessibility-notification-delivery.
APPKIT_EXPORT void NSAccessibilityHandleFocusChanged(void);

// Returns the address of the accessibility bus from AT_SPI_BUS_ADDRESS, or by asking org.a11y.Bus on the
// session bus. The returned string must be freed. Returns NULL when no accessibility bus is available.
APPKIT_EXPORT char *NSAccessibilityATSPIBusAddress(void);

// Emits one org.a11y.atspi.Event.Object signal with the (siiva{sv}) body used by AT-SPI 2.
APPKIT_EXPORT void NSAccessibilityATSPIEvent(const char *member,
                                             const char *detail,
                                             int enabled,
                                             const char *value);
