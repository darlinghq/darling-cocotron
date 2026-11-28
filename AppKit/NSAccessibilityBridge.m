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

// Internal fan-out for AppKit accessibility notifications and a best-effort emitter of AT-SPI 2 D-Bus
// events. The D-Bus interface and signal bodies are the ones published by at-spi2-core:
// org.a11y.atspi.Event.Object::StateChanged, ::PropertyChange and ::Announcement all use (siiva{sv}).
// Bus discovery follows the at-spi2-core bus README: AT_SPI_BUS_ADDRESS overrides discovery, otherwise
// org.a11y.Bus.GetAddress on the session bus supplies the separate accessibility bus address.
// https://gitlab.gnome.org/GNOME/at-spi2-core/-/blob/main/bus/README.md

#import <AppKit/NSAccessibility+Private.h>
#import <AppKit/NSAccessibility.h>
#import <AppKit/NSAccessibilityConstants.h>
#import <dbus/dbus.h>
#import <pthread.h>
#import <stdlib.h>
#import <string.h>
#import <time.h>

#pragma mark - Internal delivery

typedef struct NSAccessibilityHandlerEntry {
    NSAccessibilityNotificationHandler handler;
    void *context;
    struct NSAccessibilityHandlerEntry *next;
} NSAccessibilityHandlerEntry;

static pthread_mutex_t g_handlerLock = PTHREAD_MUTEX_INITIALIZER;
static NSAccessibilityHandlerEntry *g_handlers;

void NSAccessibilityRegisterNotificationHandler(NSAccessibilityNotificationHandler handler, void *context)
{
    if (handler == NULL)
        return;

    NSAccessibilityHandlerEntry *entry = malloc(sizeof(*entry));
    if (entry == NULL)
        return;
    entry->handler = handler;
    entry->context = context;

    pthread_mutex_lock(&g_handlerLock);
    entry->next = g_handlers;
    g_handlers = entry;
    pthread_mutex_unlock(&g_handlerLock);
}

void NSAccessibilityUnregisterNotificationHandler(NSAccessibilityNotificationHandler handler, void *context)
{
    if (handler == NULL)
        return;

    pthread_mutex_lock(&g_handlerLock);
    NSAccessibilityHandlerEntry **link = &g_handlers;
    while (*link != NULL) {
        NSAccessibilityHandlerEntry *entry = *link;
        if (entry->handler == handler && entry->context == context) {
            *link = entry->next;
            pthread_mutex_unlock(&g_handlerLock);
            free(entry);
            return;
        }
        link = &entry->next;
    }
    pthread_mutex_unlock(&g_handlerLock);
}

// A snapshot keeps a handler that unregisters itself from invalidating the walk.
void NSAccessibilityDeliverNotification(id element, NSString *notification, NSDictionary *userInfo)
{
    if (notification == nil)
        return;

    pthread_mutex_lock(&g_handlerLock);
    size_t count = 0;
    for (NSAccessibilityHandlerEntry *entry = g_handlers; entry != NULL; entry = entry->next)
        count++;

    NSAccessibilityHandlerEntry *snapshot = NULL;
    if (count != 0) {
        snapshot = malloc(count * sizeof(*snapshot));
        if (snapshot != NULL) {
            size_t i = 0;
            for (NSAccessibilityHandlerEntry *entry = g_handlers; entry != NULL; entry = entry->next)
                snapshot[i++] = *entry;
        }
    }
    pthread_mutex_unlock(&g_handlerLock);

    if (snapshot != NULL) {
        for (size_t i = 0; i < count; i++)
            snapshot[i].handler(element, notification, userInfo, snapshot[i].context);
        free(snapshot);
    }
}

#pragma mark - AT-SPI bus discovery

// All connections here are private. Closing before the final unref releases the transport instead of leaving
// libdbus in a state where dropping the last reference to an open private connection is invalid.
static void ClosePrivateConnection(DBusConnection *connection)
{
    if (connection == NULL)
        return;
    dbus_connection_close(connection);
    dbus_connection_unref(connection);
}

char *NSAccessibilityATSPIBusAddress(void)
{
    const char *configured = getenv("AT_SPI_BUS_ADDRESS");
    if (configured != NULL && *configured != '\0')
        return strdup(configured);

    DBusError error;
    dbus_error_init(&error);
    DBusConnection *session = dbus_bus_get_private(DBUS_BUS_SESSION, &error);
    if (session == NULL) {
        dbus_error_free(&error);
        return NULL;
    }
    // Losing the session bus must not terminate the application; this is only an address lookup.
    dbus_connection_set_exit_on_disconnect(session, FALSE);

    char *address = NULL;
    DBusMessage *call = dbus_message_new_method_call("org.a11y.Bus", "/org/a11y/bus",
                                                     "org.a11y.Bus", "GetAddress");
    if (call != NULL) {
        DBusMessage *reply = dbus_connection_send_with_reply_and_block(session, call, 1000, &error);
        if (reply != NULL) {
            DBusMessageIter arguments;
            if (dbus_message_iter_init(reply, &arguments)
                && dbus_message_iter_get_arg_type(&arguments) == DBUS_TYPE_STRING) {
                const char *found = NULL;
                dbus_message_iter_get_basic(&arguments, &found);
                if (found != NULL && *found != '\0')
                    address = strdup(found);
            }
            dbus_message_unref(reply);
        }
        dbus_message_unref(call);
    }

    ClosePrivateConnection(session);
    dbus_error_free(&error);
    return address;
}

#pragma mark - AT-SPI signal emission

static pthread_mutex_t g_busLock = PTHREAD_MUTEX_INITIALIZER;
static DBusConnection *g_bus;
static BOOL g_busAttempted;
static struct timespec g_busAttempt;

// Call with g_busLock held. Failed discovery is retried after a short interval so that a screen reader started
// after the application can still receive later events.
static DBusConnection *AccessibilityBusLocked(void)
{
    if (g_bus != NULL && dbus_connection_get_is_connected(g_bus))
        return g_bus;
    if (g_bus != NULL) {
        ClosePrivateConnection(g_bus);
        g_bus = NULL;
    }

    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
        return NULL;
    if (g_busAttempted && now.tv_sec - g_busAttempt.tv_sec < 5)
        return NULL;
    g_busAttempted = YES;
    g_busAttempt = now;

    char *address = NSAccessibilityATSPIBusAddress();
    if (address == NULL)
        return NULL;

    DBusError error;
    dbus_error_init(&error);
    g_bus = dbus_connection_open_private(address, &error);
    if (g_bus != NULL)
        dbus_connection_set_exit_on_disconnect(g_bus, FALSE);
    dbus_error_free(&error);
    free(address);
    return g_bus;
}

static BOOL AppendBasic(DBusMessageIter *iterator, int type, const void *value)
{
    return dbus_message_iter_append_basic(iterator, type, value) ? YES : NO;
}

static BOOL AppendVariantString(DBusMessageIter *iterator, const char *value)
{
    DBusMessageIter variant;
    if (!dbus_message_iter_open_container(iterator, DBUS_TYPE_VARIANT, "s", &variant))
        return NO;
    if (!AppendBasic(&variant, DBUS_TYPE_STRING, &value)) {
        dbus_message_iter_close_container(iterator, &variant);
        return NO;
    }
    return dbus_message_iter_close_container(iterator, &variant) ? YES : NO;
}

static BOOL AppendEventBody(DBusMessage *message, const char *detail, int enabled, const char *value)
{
    DBusMessageIter arguments;
    // libdbus initializes an append iterator without a failure result; the caller has already checked that
    // the message exists.
    dbus_message_iter_init_append(message, &arguments);
    if (!AppendBasic(&arguments, DBUS_TYPE_STRING, &detail))
        return NO;
    if (!AppendBasic(&arguments, DBUS_TYPE_INT32, &enabled))
        return NO;
    int zero = 0;
    if (!AppendBasic(&arguments, DBUS_TYPE_INT32, &zero))
        return NO;
    if (!AppendVariantString(&arguments, value != NULL ? value : ""))
        return NO;

    DBusMessageIter properties;
    if (!dbus_message_iter_open_container(&arguments, DBUS_TYPE_ARRAY, "{sv}", &properties))
        return NO;
    return dbus_message_iter_close_container(&arguments, &properties) ? YES : NO;
}

void NSAccessibilityATSPIEvent(const char *member, const char *detail, int enabled, const char *value)
{
    if (member == NULL || detail == NULL)
        return;

    pthread_mutex_lock(&g_busLock);
    DBusConnection *bus = AccessibilityBusLocked();
    if (bus == NULL) {
        pthread_mutex_unlock(&g_busLock);
        return;
    }

    DBusMessage *message = dbus_message_new_signal("/org/a11y/atspi/accessible/root",
                                                   "org.a11y.atspi.Event.Object", member);
    if (message != NULL) {
        if (AppendEventBody(message, detail, enabled, value)) {
            dbus_connection_send(bus, message, NULL);
            dbus_connection_flush(bus);
        }
        dbus_message_unref(message);
    }
    pthread_mutex_unlock(&g_busLock);
}

#pragma mark - Notification mapping

static NSString *AXValueDescription(id element, NSString *attribute, NSDictionary *userInfo)
{
    id value = [userInfo objectForKey: attribute];
    if (value == nil && [element respondsToSelector: @selector(accessibilityAttributeValue:)])
        value = [element accessibilityAttributeValue: attribute];

    if ([value isKindOfClass: [NSString class]])
        return value;
    if ([value isKindOfClass: [NSNumber class]])
        return [value stringValue];
    if (value != nil)
        return [value description];
    return @"";
}

static void EmitATSPIEventForNotification(id element, NSString *notification, NSDictionary *userInfo)
{
    if ([notification isEqualToString: NSAccessibilityFocusedUIElementChangedNotification]) {
        NSAccessibilityATSPIEvent("StateChanged", "focused", 1, "0");
    } else if ([notification isEqualToString: NSAccessibilityApplicationActivatedNotification]) {
        NSAccessibilityATSPIEvent("StateChanged", "active", 1, "0");
    } else if ([notification isEqualToString: NSAccessibilityApplicationDeactivatedNotification]) {
        NSAccessibilityATSPIEvent("StateChanged", "active", 0, "0");
    } else if ([notification isEqualToString: NSAccessibilityApplicationHiddenNotification]) {
        NSAccessibilityATSPIEvent("StateChanged", "visible", 0, "0");
    } else if ([notification isEqualToString: NSAccessibilityApplicationShownNotification]) {
        NSAccessibilityATSPIEvent("StateChanged", "visible", 1, "0");
    } else if ([notification isEqualToString: NSAccessibilityValueChangedNotification]) {
        NSString *value = AXValueDescription(element, NSAccessibilityValueAttribute, userInfo);
        NSAccessibilityATSPIEvent("PropertyChange", "value", 0, [value UTF8String]);
    } else if ([notification isEqualToString: NSAccessibilityTitleChangedNotification]) {
        NSString *value = AXValueDescription(element, NSAccessibilityTitleAttribute, userInfo);
        NSAccessibilityATSPIEvent("PropertyChange", "name", 0, [value UTF8String]);
    } else if ([notification isEqualToString:
                    NSAccessibilityAnnouncementRequestedNotification]) {
        NSString *announcement = [userInfo objectForKey: NSAccessibilityAnnouncementKey];
        if (![announcement isKindOfClass: [NSString class]])
            announcement = @"";
        int politeness = 1;
        NSNumber *priority = [userInfo objectForKey: NSAccessibilityPriorityKey];
        if ([priority respondsToSelector: @selector(intValue)]) {
           NSInteger level = [priority integerValue];
            politeness = level >= NSAccessibilityPriorityHigh ? 2
                       : level <= NSAccessibilityPriorityLow ? 0 : 1;
        }
        // AT-SPI puts the politeness level in the first integer detail and the text in the variant; the
        // leading string detail is unused for this event.
        NSAccessibilityATSPIEvent("Announcement", "", politeness, [announcement UTF8String]);
    }
}

void NSAccessibilityNotificationBridgeHandler(id element, NSString *notification,
                                               NSDictionary *userInfo, void *context)
{
    (void) context;
    EmitATSPIEventForNotification(element, notification, userInfo);
}

__attribute__((constructor))
static void InstallAccessibilityBridge(void)
{
    NSAccessibilityRegisterNotificationHandler(NSAccessibilityNotificationBridgeHandler, NULL);
}
