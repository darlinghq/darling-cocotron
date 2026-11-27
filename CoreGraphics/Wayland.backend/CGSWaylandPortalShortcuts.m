/* Copyright (C) 2026 Lubos Dolezel

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

// The portal's D-Bus interface is described by the xdg-desktop-portal documentation:
// org.freedesktop.portal.GlobalShortcuts (CreateSession, BindShortcuts, Activated, Deactivated)
// and org.freedesktop.portal.Request (Response):
// https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html
// Shortcut triggers are keysym names as defined by the XDG Shortcuts Specification.

#import "CGSWaylandPortalShortcuts.h"
#import "CGSConnectionWayland.h"
#import "DarlingSessionBusAddress.h"
#import <CoreFoundation/CFPreferences.h>
#import <CoreFoundation/CFRunLoop.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define PORTAL_NAME "org.freedesktop.portal.Desktop"
#define PORTAL_PATH "/org/freedesktop/portal/desktop"
#define SHORTCUTS_INTERFACE "org.freedesktop.portal.GlobalShortcuts"
#define REQUEST_INTERFACE "org.freedesktop.portal.Request"
#define SESSION_INTERFACE "org.freedesktop.portal.Session"
#define REGISTRY_INTERFACE "org.freedesktop.host.portal.Registry"
#define BUS_NAME "org.freedesktop.DBus"
#define REQUEST_PATH_PREFIX "/org/freedesktop/portal/desktop/request/"
#define CALL_TIMEOUT_MS 5000

enum {
    RequestNone = 0,
    RequestCreateSession,
    RequestBindShortcuts,
};

// libdbus exposes NameHasOwner but not GetNameOwner as a convenience call, so use the bus API.
static void copyNameOwner(DBusConnection *connection, NSString **owner) {
    DBusMessage *call = dbus_message_new_method_call(DBUS_SERVICE_DBUS, DBUS_PATH_DBUS,
                                                     DBUS_INTERFACE_DBUS, "GetNameOwner");
    if (call == NULL)
        return;
    DBusMessageIter iterator;
    const char *name = PORTAL_NAME;
    dbus_message_iter_init_append(call, &iterator);
    dbus_message_iter_append_basic(&iterator, DBUS_TYPE_STRING, &name);

    DBusError error;
    dbus_error_init(&error);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(connection, call,
                                                                    CALL_TIMEOUT_MS, &error);
    dbus_message_unref(call);
    if (reply != NULL) {
        DBusMessageIter result;
        const char *uniqueName = NULL;
        if (dbus_message_iter_init(reply, &result) &&
            dbus_message_iter_get_arg_type(&result) == DBUS_TYPE_STRING) {
            dbus_message_iter_get_basic(&result, &uniqueName);
            if (uniqueName != NULL)
                *owner = [NSString stringWithUTF8String: uniqueName];
        }
        dbus_message_unref(reply);
    }
    dbus_error_free(&error);
}

static DBusConnection *connectToPortal(NSString **owner) {
    NSString *address = DarlingPortalSessionBusAddress();
    DBusError error;
    dbus_error_init(&error);

    DBusConnection *connection = address != nil
            ? dbus_connection_open_private([address UTF8String], &error) : NULL;
    if (connection != NULL && !dbus_bus_register(connection, &error)) {
        dbus_connection_close(connection);
        dbus_connection_unref(connection);
        connection = NULL;
    }
    if (connection != NULL)
        dbus_connection_set_exit_on_disconnect(connection, FALSE);

    if (connection != NULL && !dbus_bus_name_has_owner(connection, PORTAL_NAME, &error)) {
        dbus_uint32_t result = 0;
        // The portal is normally started on demand.
        dbus_error_free(&error);
        dbus_error_init(&error);
        if (!dbus_bus_start_service_by_name(connection, PORTAL_NAME, 0, &result, &error)) {
            dbus_connection_close(connection);
            dbus_connection_unref(connection);
            connection = NULL;
        }
    }
    if (connection != NULL)
        copyNameOwner(connection, owner);
    dbus_error_free(&error);
    return connection;
}

static void appendStringOption(DBusMessageIter *dictionary, const char *key, const char *value) {
    DBusMessageIter entry, variant;
    if (!dbus_message_iter_open_container(dictionary, DBUS_TYPE_DICT_ENTRY, NULL, &entry))
        return;
    if (!dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key))
        goto closeEntry;
    if (!dbus_message_iter_open_container(&entry, DBUS_TYPE_VARIANT,
                                          DBUS_TYPE_STRING_AS_STRING, &variant))
        goto closeEntry;
    dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &value);
    dbus_message_iter_close_container(&entry, &variant);
closeEntry:
    dbus_message_iter_close_container(dictionary, &entry);
}

static NSString *copyStringFromDict(DBusMessageIter *dict, const char *wanted) {
    if (dbus_message_iter_get_arg_type(dict) != DBUS_TYPE_ARRAY)
        return nil;
    DBusMessageIter entries;
    dbus_message_iter_recurse(dict, &entries);
    while (dbus_message_iter_get_arg_type(&entries) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter entry, value;
        const char *key = NULL;
        dbus_message_iter_recurse(&entries, &entry);
        if (dbus_message_iter_get_arg_type(&entry) != DBUS_TYPE_STRING)
            break;
        dbus_message_iter_get_basic(&entry, &key);
        if (!dbus_message_iter_next(&entry) ||
            dbus_message_iter_get_arg_type(&entry) != DBUS_TYPE_VARIANT)
            break;
        dbus_message_iter_recurse(&entry, &value);
        if (key != NULL && strcmp(key, wanted) == 0 &&
            dbus_message_iter_get_arg_type(&value) == DBUS_TYPE_STRING) {
            const char *string = NULL;
            dbus_message_iter_get_basic(&value, &string);
            return string != NULL ? [NSString stringWithUTF8String: string] : nil;
        }
        dbus_message_iter_next(&entries);
    }
    return nil;
}

// The response carries the shortcut IDs the desktop actually bound; other IDs in the session were
// declined and must not be reported by the portal.
static void collectShortcutIDs(DBusMessageIter *array, NSMutableSet *uids) {
    if (dbus_message_iter_get_arg_type(array) != DBUS_TYPE_ARRAY)
        return;
    DBusMessageIter entries;
    dbus_message_iter_recurse(array, &entries);
    while (dbus_message_iter_get_arg_type(&entries) == DBUS_TYPE_STRUCT) {
        DBusMessageIter entry;
        const char *identifier = NULL;
        dbus_message_iter_recurse(&entries, &entry);
        if (dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_STRING)
            dbus_message_iter_get_basic(&entry, &identifier);
        if (identifier != NULL && strncmp(identifier, "darling-", 8) == 0) {
            char *end = NULL;
            long uid = strtol(identifier + 8, &end, 10);
            if (end != identifier + 8 && *end == '\0' && uid >= INT_MIN && uid <= INT_MAX)
                [uids addObject: @((int) uid)];
        }
        // The details vardict has no information we need: the effective trigger is only a
        // translated description, not a machine-readable keysym.
        dbus_message_iter_next(&entries);
    }
}

// BindShortcuts returns its shortcuts inside the Request.Response results vardict, under the
// "shortcuts" key. ShortcutsChanged sends that array directly as its second argument.
static void collectResponseShortcutIDs(DBusMessageIter *results, NSMutableSet *uids) {
    if (dbus_message_iter_get_arg_type(results) != DBUS_TYPE_ARRAY)
        return;
    DBusMessageIter entries;
    dbus_message_iter_recurse(results, &entries);
    while (dbus_message_iter_get_arg_type(&entries) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter entry, value;
        const char *key = NULL;
        dbus_message_iter_recurse(&entries, &entry);
        if (dbus_message_iter_get_arg_type(&entry) != DBUS_TYPE_STRING)
            break;
        dbus_message_iter_get_basic(&entry, &key);
        if (!dbus_message_iter_next(&entry) ||
            dbus_message_iter_get_arg_type(&entry) != DBUS_TYPE_VARIANT)
            break;
        dbus_message_iter_recurse(&entry, &value);
        if (key != NULL && strcmp(key, "shortcuts") == 0)
            collectShortcutIDs(&value, uids);
        dbus_message_iter_next(&entries);
    }
}

static int uidFromShortcutID(const char *identifier) {
    if (identifier == NULL || strncmp(identifier, "darling-", 8) != 0)
        return 0;
    char *end = NULL;
    long uid = strtol(identifier + 8, &end, 10);
    if (end == identifier + 8 || *end != '\0' || uid < INT_MIN || uid > INT_MAX)
        return 0;
    return (int) uid;
}

@interface CGSWaylandPortalShortcuts ()
- (void) readMessages;
- (void) readQueuedMessages;
- (void) processMessage: (DBusMessage *) message;
- (NSString *) appID;
- (void) registerAppID;
- (void) createSession;
- (void) bindShortcuts;
- (void) rebuildSession;
- (void) closeSession;
- (void) forgetSession;
@end

static void socketCallback(CFSocketRef socket, CFSocketCallBackType type,
                           CFDataRef address, const void *data, void *info) {
    [(CGSWaylandPortalShortcuts *) info readMessages];
}

@implementation CGSWaylandPortalShortcuts

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection {
    self = [super init];
    if (self == nil)
        return nil;

    _connection = connection;
    NSString *owner = nil;
    _bus = connectToPortal(&owner);
    if (_bus == NULL) {
        [self release];
        return nil;
    }
    _portalOwner = [owner retain];

    // Listening before the first call means a fast Response or Activated cannot be missed between
    // the call and the match being installed.
    dbus_bus_add_match(_bus, "type='signal',sender='" PORTAL_NAME
                       "',interface='" REQUEST_INTERFACE "',member='Response'", NULL);
    dbus_bus_add_match(_bus, "type='signal',sender='" PORTAL_NAME
                       "',interface='" SHORTCUTS_INTERFACE "',member='Activated'", NULL);
    dbus_bus_add_match(_bus, "type='signal',sender='" PORTAL_NAME
                       "',interface='" SHORTCUTS_INTERFACE "',member='Deactivated'", NULL);
    dbus_bus_add_match(_bus, "type='signal',sender='" PORTAL_NAME
                       "',interface='" SHORTCUTS_INTERFACE "',member='ShortcutsChanged'", NULL);
    dbus_bus_add_match(_bus, "type='signal',sender='" PORTAL_NAME
                       "',interface='" SESSION_INTERFACE "',member='Closed'", NULL);
    dbus_bus_add_match(_bus, "type='signal',sender='" BUS_NAME
                       "',interface='" BUS_NAME "',member='NameOwnerChanged',arg0='" PORTAL_NAME "'",
                       NULL);

    int descriptor = -1;
    if (!dbus_connection_get_unix_fd(_bus, &descriptor)) {
        [self invalidate];
        [self release];
        return nil;
    }
    CFSocketContext context = {
        .version = 0,
        .info = self,
        .retain = NULL,
        .release = NULL,
        .copyDescription = NULL,
    };
    _socket = CFSocketCreateWithNative(kCFAllocatorDefault, descriptor, kCFSocketReadCallBack,
                                       socketCallback, &context);
    if (_socket == NULL) {
        [self invalidate];
        [self release];
        return nil;
    }
    // The descriptor belongs to libdbus.
    CFSocketSetSocketFlags(_socket, CFSocketGetSocketFlags(_socket) & ~kCFSocketCloseOnInvalidate);
    _source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
    if (_source != NULL)
        CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);

    _boundUIDs = [NSMutableSet new];
    _pressedUIDs = [NSMutableSet new];
    [self registerAppID];
    return self;
}

- (void) dealloc {
    [self invalidate];
    [super dealloc];
}

- (void) invalidate {
    if (_source != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source);
        _source = NULL;
    }
    if (_socket != NULL) {
        CFSocketInvalidate(_socket);
        CFRelease(_socket);
        _socket = NULL;
    }
    if (_bus != NULL) {
        dbus_connection_close(_bus);
        dbus_connection_unref(_bus);
        _bus = NULL;
    }
    [_sessionPath release];
    _sessionPath = nil;
    [_requestPath release];
    _requestPath = nil;
    [_portalOwner release];
    _portalOwner = nil;
    [_boundUIDs release];
    _boundUIDs = nil;
    [_pressedUIDs release];
    _pressedUIDs = nil;
    _requestKind = RequestNone;
}

- (BOOL) isUIDBound: (int) uid {
    return [_boundUIDs containsObject: @(uid)];
}

// The application id is used by newer portals to associate the bindings with the app. A preference
// lets a desktop supply the basename of a .desktop file; otherwise the process name is used. This
// is only an association: it does not change which Carbon APIs the process may call.
- (NSString *) appID {
    CFStringRef preferred = CFPreferencesCopyAppValue(CFSTR("PortalAppID"),
                                                      CFSTR("org.darlinghq.CoreGraphics"));
    NSString *result = [(NSString *) preferred autorelease];
    if ([result length] > 0)
        return result;

    NSString *processName = [[NSProcessInfo processInfo] processName];
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i = 0; i < [processName length]; i++) {
        unichar c = [processName characterAtIndex: i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '_' || c == '-')
            [name appendFormat: @"%C", c];
    }
    return [name length] > 0 ? name : @"darling";
}

- (void) registerAppID {
    NSString *appID = [self appID];
    if (appID == nil)
        return;
    DBusMessage *call = dbus_message_new_method_call(PORTAL_NAME, PORTAL_PATH,
                                                     REGISTRY_INTERFACE, "Register");
    if (call == NULL)
        return;
    DBusMessageIter arguments, options;
    const char *value = [appID UTF8String];
    dbus_message_iter_init_append(call, &arguments);
    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_STRING, &value);
    dbus_message_iter_open_container(&arguments, DBUS_TYPE_ARRAY, "{sv}", &options);
    dbus_message_iter_close_container(&arguments, &options);

    DBusError error;
    dbus_error_init(&error);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(_bus, call, CALL_TIMEOUT_MS,
                                                                   &error);
    if (reply != NULL) {
        if (_portalOwner == nil && dbus_message_get_sender(reply) != NULL)
            _portalOwner = [[NSString alloc] initWithUTF8String: dbus_message_get_sender(reply)];
        dbus_message_unref(reply);
    }
    dbus_message_unref(call);
    dbus_error_free(&error);
    [self readQueuedMessages];
}

// A shortcut set is offered in a fresh session: the portal allows BindShortcuts only once per
// session, so a changed set closes the old one first.
- (void) hotKeysDidChange {
    if (_bus == NULL)
        return;
    if (_requestKind != RequestNone) {
        _restartRequested = YES;
        return;
    }
    [self rebuildSession];
}

- (void) rebuildSession {
    if (_bus == NULL)
        return;
    if (_sessionPath != NULL)
        [self closeSession];
    if ([[_connection enabledHotKeysForPortal] count] == 0)
        return;
    [self createSession];
}

- (void) forgetSession {
    for (NSNumber *uid in _pressedUIDs) {
        [_connection postPortalHotKeyEventForUID: [uid intValue] pressed: NO];
    }
    [_pressedUIDs removeAllObjects];
    [_boundUIDs removeAllObjects];
    [_sessionPath release];
    _sessionPath = nil;
}

- (void) closeSession {
    if (_sessionPath == NULL)
        return;
    DBusMessage *call = dbus_message_new_method_call(PORTAL_NAME, [_sessionPath UTF8String],
                                                     SESSION_INTERFACE, "Close");
    if (call != NULL) {
        dbus_message_set_no_reply(call, TRUE);
        dbus_connection_send(_bus, call, NULL);
        dbus_message_unref(call);
    }
    [self forgetSession];
}

- (NSString *) nextTokenWithPrefix: (NSString *) prefix {
    return [NSString stringWithFormat: @"%@_%d_%llu", prefix, (int) getpid(), ++_counter];
}

// Sets _requestPath to the path the bus will use for the reply. The unique name has its leading
// colon removed and its dots replaced with underscores, as for all portal handles.
- (BOOL) prepareRequestWithToken: (NSString *) token {
    const char *uniqueName = dbus_bus_get_unique_name(_bus);
    if (uniqueName == NULL || uniqueName[0] != ':')
        return NO;
    NSString *sender = [[NSString stringWithUTF8String: uniqueName + 1]
            stringByReplacingOccurrencesOfString: @"." withString: @"_"];
    [_requestPath release];
    _requestPath = [[NSString stringWithFormat: @REQUEST_PATH_PREFIX "%@/%@", sender, token] retain];
    return YES;
}

- (void) createSession {
    NSString *handle = [self nextTokenWithPrefix: @"darling_request"];
    NSString *session = [self nextTokenWithPrefix: @"darling_session"];
    if (![self prepareRequestWithToken: handle]) {
        _requestKind = RequestNone;
        return;
    }

    DBusMessage *call = dbus_message_new_method_call(PORTAL_NAME, PORTAL_PATH,
                                                     SHORTCUTS_INTERFACE, "CreateSession");
    DBusMessageIter arguments, options;
    const char *handleToken = [handle UTF8String];
    const char *sessionToken = [session UTF8String];
    dbus_message_iter_init_append(call, &arguments);
    dbus_message_iter_open_container(&arguments, DBUS_TYPE_ARRAY, "{sv}", &options);
    appendStringOption(&options, "handle_token", handleToken);
    appendStringOption(&options, "session_handle_token", sessionToken);
    dbus_message_iter_close_container(&arguments, &options);

    DBusError error;
    dbus_error_init(&error);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(_bus, call, CALL_TIMEOUT_MS,
                                                                   &error);
    dbus_message_unref(call);
    BOOL ok = reply != NULL &&
              dbus_message_get_type(reply) == DBUS_MESSAGE_TYPE_METHOD_RETURN &&
              dbus_message_get_sender(reply) != NULL;
    if (ok) {
        if (_portalOwner == nil)
            _portalOwner = [[NSString alloc] initWithUTF8String: dbus_message_get_sender(reply)];
        // An older portal may ignore the token: listen to the path it picked instead.
        DBusMessageIter iterator;
        const char *path = NULL;
        if (dbus_message_iter_init(reply, &iterator) &&
            dbus_message_iter_get_arg_type(&iterator) == DBUS_TYPE_OBJECT_PATH) {
            dbus_message_iter_get_basic(&iterator, &path);
            if (path != NULL && ![_requestPath isEqualToString: [NSString stringWithUTF8String: path]]) {
                [_requestPath release];
                _requestPath = [[NSString alloc] initWithUTF8String: path];
            }
        }
        _requestKind = RequestCreateSession;
    } else {
        _requestKind = RequestNone;
        [_requestPath release];
        _requestPath = nil;
    }
    if (reply != NULL)
        dbus_message_unref(reply);
    dbus_error_free(&error);
    [self readQueuedMessages];
}

- (void) bindShortcuts {
    NSString *handle = [self nextTokenWithPrefix: @"darling_request"];
    if (![self prepareRequestWithToken: handle]) {
        _requestKind = RequestNone;
        return;
    }

    DBusMessage *call = dbus_message_new_method_call(PORTAL_NAME, PORTAL_PATH,
                                                     SHORTCUTS_INTERFACE, "BindShortcuts");
    DBusMessageIter arguments, shortcuts, options;
    const char *session = [_sessionPath UTF8String];
    const char *parentWindow = ""; // no window is known to own a global shortcut
    const char *handleToken = [handle UTF8String];
    dbus_message_iter_init_append(call, &arguments);
    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_OBJECT_PATH, &session);
    dbus_message_iter_open_container(&arguments, DBUS_TYPE_ARRAY, "(sa{sv})", &shortcuts);
    for (NSDictionary *hotKey in [_connection enabledHotKeysForPortal]) {
        int uid = [hotKey[@"uid"] intValue];
        NSString *identifier = [NSString stringWithFormat: @"darling-%d", uid];
        NSString *description = [NSString stringWithFormat: @"Carbon hot key %d", uid];
        NSString *trigger = [_connection portalTriggerForKeyCode: [hotKey[@"virtualKey"] unsignedIntValue]
                                                           flags: [hotKey[@"flags"] unsignedLongLongValue]];
        const char *identifierUTF8 = [identifier UTF8String];
        const char *descriptionUTF8 = [description UTF8String];
        const char *triggerUTF8 = [trigger UTF8String];
        DBusMessageIter entry, details;
        dbus_message_iter_open_container(&shortcuts, DBUS_TYPE_STRUCT, NULL, &entry);
        dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &identifierUTF8);
        dbus_message_iter_open_container(&entry, DBUS_TYPE_ARRAY, "{sv}", &details);
        appendStringOption(&details, "description", descriptionUTF8);
        if (triggerUTF8 != NULL && triggerUTF8[0] != '\0')
            appendStringOption(&details, "preferred_trigger", triggerUTF8);
        dbus_message_iter_close_container(&entry, &details);
        dbus_message_iter_close_container(&shortcuts, &entry);
    }
    dbus_message_iter_close_container(&arguments, &shortcuts);
    dbus_message_iter_append_basic(&arguments, DBUS_TYPE_STRING, &parentWindow);
    dbus_message_iter_open_container(&arguments, DBUS_TYPE_ARRAY, "{sv}", &options);
    appendStringOption(&options, "handle_token", handleToken);
    dbus_message_iter_close_container(&arguments, &options);

    DBusError error;
    dbus_error_init(&error);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(_bus, call, CALL_TIMEOUT_MS,
                                                                   &error);
    dbus_message_unref(call);
    BOOL ok = reply != NULL &&
              dbus_message_get_type(reply) == DBUS_MESSAGE_TYPE_METHOD_RETURN &&
              dbus_message_get_sender(reply) != NULL;
    if (ok) {
        _requestKind = RequestBindShortcuts;
    } else {
        _requestKind = RequestNone;
        [_sessionPath release];
        _sessionPath = nil;
        [_requestPath release];
        _requestPath = nil;
    }
    if (reply != NULL)
        dbus_message_unref(reply);
    dbus_error_free(&error);
    [self readQueuedMessages];
}

// A blocking call (send_with_reply_and_block) reads whatever else the bus has sent into libdbus's
// queue, for example the Response of a request whose call it was waiting for. Those messages
// never make the socket readable again, so look at the queue once the call is over.
- (void) readQueuedMessages {
    [self performSelectorOnMainThread: @selector(readMessages) withObject: nil waitUntilDone: NO];
}

- (void) readMessages {
    if (_bus == NULL)
        return;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    dbus_connection_read_write(_bus, 0);
    dbus_connection_flush(_bus);
    while (_bus != NULL) {
        DBusMessage *message = dbus_connection_pop_message(_bus);
        if (message == NULL)
            break;
        [self processMessage: message];
        dbus_message_unref(message);
    }
    if (_bus != NULL && !dbus_connection_get_is_connected(_bus))
        [self forgetSession];
    [pool release];
}

- (void) processMessage: (DBusMessage *) message {
    const char *sender = dbus_message_get_sender(message);
    BOOL fromPortal = sender != NULL && _portalOwner != NULL &&
                       strcmp(sender, [_portalOwner UTF8String]) == 0;

    if (dbus_message_is_signal(message, REQUEST_INTERFACE, "Response") &&
        fromPortal && _requestPath != NULL &&
        dbus_message_get_path(message) != NULL &&
        strcmp(dbus_message_get_path(message), [_requestPath UTF8String]) == 0) {
        DBusMessageIter iterator;
        dbus_uint32_t response = 2;
        if (dbus_message_iter_init(message, &iterator) &&
            dbus_message_iter_get_arg_type(&iterator) == DBUS_TYPE_UINT32)
            dbus_message_iter_get_basic(&iterator, &response);
        int kind = _requestKind;
        [_requestPath release];
        _requestPath = nil;
        _requestKind = RequestNone;

        if (response == 0 && kind == RequestCreateSession &&
            dbus_message_iter_next(&iterator) &&
            dbus_message_iter_get_arg_type(&iterator) == DBUS_TYPE_ARRAY) {
            NSString *handle = copyStringFromDict(&iterator, "session_handle");
            if ([handle length] > 0) {
                [_sessionPath release];
                _sessionPath = [handle retain];
            }
        }
        if (response == 0 && kind == RequestBindShortcuts &&
            dbus_message_iter_next(&iterator)) {
            collectResponseShortcutIDs(&iterator, _boundUIDs);
        }
        if (response != 0)
            [self forgetSession];
        if (_restartRequested) {
            _restartRequested = NO;
            [self rebuildSession];
        } else if (_sessionPath != NULL && kind == RequestCreateSession) {
            [self bindShortcuts];
        }
        return;
    }

    if (fromPortal &&
        (dbus_message_is_signal(message, SHORTCUTS_INTERFACE, "Activated") ||
         dbus_message_is_signal(message, SHORTCUTS_INTERFACE, "Deactivated"))) {
        BOOL pressed = dbus_message_is_signal(message, SHORTCUTS_INTERFACE, "Activated");
        DBusMessageIter iterator;
        const char *session = NULL, *identifier = NULL;
        if (dbus_message_iter_init(message, &iterator) &&
            dbus_message_iter_get_arg_type(&iterator) == DBUS_TYPE_OBJECT_PATH)
            dbus_message_iter_get_basic(&iterator, &session);
        if (dbus_message_iter_next(&iterator) &&
            dbus_message_iter_get_arg_type(&iterator) == DBUS_TYPE_STRING)
            dbus_message_iter_get_basic(&iterator, &identifier);
        if (session == NULL || _sessionPath == NULL ||
            strcmp(session, [_sessionPath UTF8String]) != 0)
            return;
        int uid = uidFromShortcutID(identifier);
        if (uid != 0 && [_boundUIDs containsObject: @(uid)]) {
            if (pressed) {
                if ([_pressedUIDs containsObject: @(uid)])
                    return; // the desktop already reported this press
                [_pressedUIDs addObject: @(uid)];
            } else if (![_pressedUIDs containsObject: @(uid)]) {
                return; // no press of this shortcut was reported to us
            } else {
                [_pressedUIDs removeObject: @(uid)];
            }
            [_connection postPortalHotKeyEventForUID: uid pressed: pressed];
        }
        return;
    }

    if (fromPortal && dbus_message_is_signal(message, SHORTCUTS_INTERFACE, "ShortcutsChanged")) {
        DBusMessageIter iterator;
        const char *session = NULL;
        if (dbus_message_iter_init(message, &iterator) &&
            dbus_message_iter_get_arg_type(&iterator) == DBUS_TYPE_OBJECT_PATH)
            dbus_message_iter_get_basic(&iterator, &session);
        if (session == NULL || _sessionPath == NULL ||
            strcmp(session, [_sessionPath UTF8String]) != 0 ||
            !dbus_message_iter_next(&iterator))
            return;
        NSMutableSet *bound = [NSMutableSet set];
        collectShortcutIDs(&iterator, bound);
        // The signal may describe only the shortcuts that changed; keep every binding already
        // known to be active unless the session itself goes away.
        [_boundUIDs unionSet: bound];
        return;
    }

    if (fromPortal && dbus_message_is_signal(message, SESSION_INTERFACE, "Closed") &&
        dbus_message_get_path(message) != NULL && _sessionPath != NULL &&
        strcmp(dbus_message_get_path(message), [_sessionPath UTF8String]) == 0) {
        [self forgetSession];
        return;
    }

    if (dbus_message_is_signal(message, BUS_NAME, "NameOwnerChanged")) {
        DBusMessageIter iterator;
        const char *name = NULL, *newOwner = NULL;
        if (dbus_message_iter_init(message, &iterator) &&
            dbus_message_iter_get_arg_type(&iterator) == DBUS_TYPE_STRING)
            dbus_message_iter_get_basic(&iterator, &name);
        if (name == NULL || strcmp(name, PORTAL_NAME) != 0 ||
            !dbus_message_iter_next(&iterator) ||
            !dbus_message_iter_next(&iterator) ||
            dbus_message_iter_get_arg_type(&iterator) != DBUS_TYPE_STRING)
            return;
        dbus_message_iter_get_basic(&iterator, &newOwner);
        if (newOwner == NULL)
            return;
        [_portalOwner release];
        _portalOwner = newOwner[0] == '\0'
                ? nil : [[NSString alloc] initWithUTF8String: newOwner];
        [_requestPath release];
        _requestPath = nil;
        _requestKind = RequestNone;
        _restartRequested = NO;
        [self forgetSession];

        if (_portalOwner != nil) {
            // The portal documents re-registering when its service restarts.
            [self registerAppID];
            [self hotKeysDidChange];
        }
    }
}

@end
