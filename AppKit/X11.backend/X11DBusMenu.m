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

// The protocol is the com.canonical.dbusmenu interface, as published at
// https://github.com/KDE/plasma-workspace/blob/master/libdbusmenuqt/com.canonical.dbusmenu.xml
// and the registrar is com.canonical.AppMenu.Registrar, as published at
// https://github.com/KDE/plasma-workspace/blob/master/appmenu/com.canonical.AppMenu.Registrar.xml

#import "X11DBusMenu.h"
#import <AppKit/NSEvent.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <CoreFoundation/CFSocket.h>
#import <dbus/dbus.h>
#import <stdlib.h>
#import <string.h>

#define MENU_PATH "/MenuBar"
#define MENU_INTERFACE "com.canonical.dbusmenu"
#define REGISTRAR_NAME "com.canonical.AppMenu.Registrar"
#define REGISTRAR_PATH "/com/canonical/AppMenu/Registrar"
#define REGISTRAR_INTERFACE "com.canonical.AppMenu.Registrar"
#define PROPERTIES_INTERFACE "org.freedesktop.DBus.Properties"
#define INTROSPECTABLE_INTERFACE "org.freedesktop.DBus.Introspectable"
#define MAX_ADDRESS_LENGTH 1024
#define CALL_TIMEOUT_MS 1000
// Changes arriving within this time are reported together.
#define REFRESH_DELAY 0.02

static const char *introspectionXML =
        "<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object "
        "Introspection 1.0//EN\" "
        "\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
        "<node>\n"
        " <interface name=\"org.freedesktop.DBus.Introspectable\">\n"
        "  <method name=\"Introspect\"><arg type=\"s\" direction=\"out\"/>"
        "</method>\n"
        " </interface>\n"
        " <interface name=\"org.freedesktop.DBus.Properties\">\n"
        "  <method name=\"Get\"><arg type=\"s\" direction=\"in\"/>"
        "<arg type=\"s\" direction=\"in\"/><arg type=\"v\" "
        "direction=\"out\"/></method>\n"
        "  <method name=\"GetAll\"><arg type=\"s\" direction=\"in\"/>"
        "<arg type=\"a{sv}\" direction=\"out\"/></method>\n"
        " </interface>\n"
        " <interface name=\"com.canonical.dbusmenu\">\n"
        "  <property name=\"Version\" type=\"u\" access=\"read\"/>\n"
        "  <property name=\"TextDirection\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"Status\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"IconThemePath\" type=\"as\" access=\"read\"/>\n"
        "  <method name=\"GetLayout\"><arg type=\"i\" direction=\"in\"/>"
        "<arg type=\"i\" direction=\"in\"/><arg type=\"as\" "
        "direction=\"in\"/><arg type=\"u\" direction=\"out\"/>"
        "<arg type=\"(ia{sv}av)\" direction=\"out\"/></method>\n"
        "  <method name=\"GetGroupProperties\"><arg type=\"ai\" "
        "direction=\"in\"/><arg type=\"as\" direction=\"in\"/>"
        "<arg type=\"a(ia{sv})\" direction=\"out\"/></method>\n"
        "  <method name=\"GetProperty\"><arg type=\"i\" direction=\"in\"/>"
        "<arg type=\"s\" direction=\"in\"/><arg type=\"v\" "
        "direction=\"out\"/></method>\n"
        "  <method name=\"Event\"><arg type=\"i\" direction=\"in\"/>"
        "<arg type=\"s\" direction=\"in\"/><arg type=\"v\" "
        "direction=\"in\"/><arg type=\"u\" direction=\"in\"/></method>\n"
        "  <method name=\"EventGroup\"><arg type=\"a(isvu)\" "
        "direction=\"in\"/><arg type=\"ai\" direction=\"out\"/></method>\n"
        "  <method name=\"AboutToShow\"><arg type=\"i\" direction=\"in\"/>"
        "<arg type=\"b\" direction=\"out\"/></method>\n"
        "  <method name=\"AboutToShowGroup\"><arg type=\"ai\" "
        "direction=\"in\"/><arg type=\"ai\" direction=\"out\"/>"
        "<arg type=\"ai\" direction=\"out\"/></method>\n"
        "  <signal name=\"ItemsPropertiesUpdated\"><arg "
        "type=\"a(ia{sv})\"/><arg type=\"a(ias)\"/></signal>\n"
        "  <signal name=\"LayoutUpdated\"><arg type=\"u\"/><arg "
        "type=\"i\"/></signal>\n"
        "  <signal name=\"ItemActivationRequested\"><arg type=\"i\"/><arg "
        "type=\"u\"/></signal>\n"
        " </interface>\n"
        "</node>\n";

#pragma mark - Message arguments

// libdbus is a host library reached through the wrapper library, which
// forwards calls without translating the calling convention. The variadic
// dbus_message_append_args() and dbus_message_get_args() read their
// arguments the way the host's C ABI passes them, which differs from the way
// code built for this platform passes variadic arguments on arm64. The
// message iterators have fixed signatures, so every argument goes through
// them instead.
static BOOL appendArgument(DBusMessage *message, int type, const void *value) {
    DBusMessageIter iterator;

    dbus_message_iter_init_append(message, &iterator);
    return dbus_message_iter_append_basic(&iterator, type, value) ? YES : NO;
}

// Reads the leading arguments of a message, which must have exactly the given
// basic types; value i receives the address of a variable of the matching C
// type. Returns NO if the message has fewer arguments or other types.
// Strings point into the message, as with dbus_message_get_args().
static BOOL readArguments(DBusMessage *message, const int *types,
                          unsigned count, void **values) {
    DBusMessageIter iterator;

    if (!dbus_message_iter_init(message, &iterator))
        return count == 0;

    for (unsigned i = 0; i < count; i++) {
        if (dbus_message_iter_get_arg_type(&iterator) != types[i])
            return NO;
        dbus_message_iter_get_basic(&iterator, values[i]);
        if (i + 1 < count && !dbus_message_iter_next(&iterator))
            return NO;
    }
    return YES;
}

#pragma mark - Session bus address

// D-Bus separates alternative addresses with ';' and accepts "unixexec:",
// which runs a program, and "autolaunch:", which may start a bus. Only one
// plain socket address (a path or an abstract name) is taken from the
// environment.
static BOOL addressAllowed(const char *address) {
    if (strncmp(address, "unix:path=", 10) != 0 &&
        strncmp(address, "unix:abstract=", 14) != 0)
        return NO;
    if (strlen(address) >= MAX_ADDRESS_LENGTH)
        return NO;
    for (const unsigned char *c = (const unsigned char *) address; *c != '\0';
         c++) {
        if (*c <= ' ' || *c >= 0x7f || *c == ';')
            return NO;
    }
    return strstr(address, "unixexec") == NULL;
}

// The address to connect to, or nil.
static NSString *sessionBusAddress(void) {
    const char *env = getenv("DBUS_SESSION_BUS_ADDRESS");

    if (env != NULL && env[0] != '\0')
        return addressAllowed(env) ? [NSString stringWithUTF8String: env] : nil;

    const char *runtimeDirectory = getenv("XDG_RUNTIME_DIR");
    if (runtimeDirectory == NULL || runtimeDirectory[0] != '/')
        return nil;

    char path[MAX_ADDRESS_LENGTH];
    if (snprintf(path, sizeof(path), "%s/bus", runtimeDirectory) >=
        (int) sizeof(path))
        return nil;

    char *escaped = dbus_address_escape_value(path);
    NSString *address = nil;
    if (escaped != NULL)
        address = [NSString stringWithFormat: @"unix:path=%s", escaped];
    dbus_free(escaped);
    return address;
}

#pragma mark - Menu description

static id boolValue(BOOL flag) {
    return flag ? (id) kCFBooleanTrue : (id) kCFBooleanFalse;
}

static BOOL isBoolValue(id value) {
    return CFGetTypeID((CFTypeRef) value) == CFBooleanGetTypeID();
}

// The name of the key of an item as the desktop spells it in a shortcut.
static NSString *shortcutKeyName(NSString *key) {
    if ([key length] != 1)
        return [key uppercaseString];

    unichar c = [key characterAtIndex: 0];

    if (c >= NSF1FunctionKey && c <= NSF35FunctionKey)
        return [NSString stringWithFormat: @"F%d", (int) (c - NSF1FunctionKey + 1)];

    switch (c) {
    case NSUpArrowFunctionKey:
        return @"Up";
    case NSDownArrowFunctionKey:
        return @"Down";
    case NSLeftArrowFunctionKey:
        return @"Left";
    case NSRightArrowFunctionKey:
        return @"Right";
    case NSHomeFunctionKey:
        return @"Home";
    case NSEndFunctionKey:
        return @"End";
    case NSPageUpFunctionKey:
        return @"Page_Up";
    case NSPageDownFunctionKey:
        return @"Page_Down";
    case NSDeleteFunctionKey:
        return @"Delete";
    case NSInsertFunctionKey:
        return @"Insert";
    case '\r':
    case 3:
        return @"Return";
    case '\t':
        return @"Tab";
    case 0x1b:
        return @"Escape";
    case 8:
    case 0x7f:
        return @"BackSpace";
    case ' ':
        return @"space";
    }
    return [key uppercaseString];
}

// The shortcut as the array of strings the protocol uses: the modifiers, then
// the key. The Command key is the key that acts as it on this system, which
// is Control by default (see NSModifierFlagMapping).
static NSArray *shortcutForItem(NSMenuItem *item) {
    NSString *key = [item keyEquivalent];

    if ([key length] == 0)
        return nil;

    NSUInteger mask = [item keyEquivalentModifierMask];
    NSMutableArray *parts = [NSMutableArray array];

    if (mask & NSCommandKeyMask)
        [parts addObject: @"Control"];
    if (mask & NSAlternateKeyMask)
        [parts addObject: @"Alt"];
    if ((mask & NSShiftKeyMask) ||
        ![key isEqualToString: [key lowercaseString]])
        [parts addObject: @"Shift"];
    if (mask & NSControlKeyMask)
        [parts addObject: @"Super"];
    [parts addObject: shortcutKeyName(key)];
    return [NSArray arrayWithObject: parts];
}

// Underscores introduce a mnemonic in the protocol's labels, so literal ones
// are doubled.
static NSString *labelForTitle(NSString *title) {
    return [title stringByReplacingOccurrencesOfString: @"_"
                                            withString: @"__"];
}

@implementation X11DBusMenu

+ (NSString *) menuObjectPath {
    return @MENU_PATH;
}

#pragma mark - Connection

static void socketCallback(CFSocketRef s, CFSocketCallBackType type,
                           CFDataRef address, const void *data, void *info) {
    [(X11DBusMenu *) info readyToRead];
}

- (instancetype) initWithSessionBus {
    if ((self = [super init]) == nil)
        return nil;

    NSString *address = sessionBusAddress();
    DBusError error;
    dbus_error_init(&error);

    DBusConnection *connection =
            address != nil
                    ? dbus_connection_open_private([address UTF8String], &error)
                    : NULL;
    if (connection != NULL && !dbus_bus_register(connection, &error)) {
        dbus_connection_close(connection);
        dbus_connection_unref(connection);
        connection = NULL;
    }

    int descriptor = -1;
    if (connection != NULL &&
        !dbus_connection_get_unix_fd(connection, &descriptor)) {
        dbus_connection_close(connection);
        dbus_connection_unref(connection);
        connection = NULL;
    }
    dbus_error_free(&error);

    if (connection == NULL) {
        [self release];
        return nil;
    }

    _connection = connection;
    dbus_connection_set_exit_on_disconnect(connection, FALSE);
    _busName = [[NSString stringWithUTF8String:
                                  dbus_bus_get_unique_name(connection)] retain];
    _idsByItem = [NSMutableDictionary new];
    _itemsByID = [NSMutableDictionary new];
    _windows = [NSMutableSet new];
    _revision = 1;

    // The descriptor stays the connection's; the socket only watches it.
    CFSocketContext context = {.version = 0, .info = self};
    _socket = CFSocketCreateWithNative(kCFAllocatorDefault, descriptor,
                                       kCFSocketReadCallBack, socketCallback,
                                       &context);
    CFSocketSetSocketFlags(_socket, CFSocketGetSocketFlags(_socket) &
                                            ~kCFSocketCloseOnInvalidate);
    _source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);

    dbus_bus_add_match(connection,
                       "type='signal',sender='org.freedesktop.DBus',"
                       "interface='org.freedesktop.DBus',member='"
                       "NameOwnerChanged',arg0='" REGISTRAR_NAME "'",
                       NULL);
    _registrarPresent = [self registrarHasOwner];
    [self processMessages];
    return self;
}

- (void) dealloc {
    [self invalidate];
    [_busName release];
    [_menu release];
    [_servedLayout release];
    [_idsByItem release];
    [_itemsByID release];
    [_windows release];
    [_applicationName release];
    [super dealloc];
}

- (void) invalidate {
    if (_refreshTimer != NULL) {
        CFRunLoopTimerInvalidate(_refreshTimer);
        CFRelease(_refreshTimer);
        _refreshTimer = NULL;
    }
    if (_source != NULL) {
        CFRunLoopSourceInvalidate(_source);
        CFRelease(_source);
        _source = NULL;
    }
    if (_socket != NULL) {
        CFSocketInvalidate(_socket);
        CFRelease(_socket);
        _socket = NULL;
    }
    if (_connection != NULL) {
        dbus_connection_close(_connection);
        dbus_connection_unref(_connection);
        _connection = NULL;
    }
    _delegate = nil;
}

- (NSString *) busName {
    return _busName;
}

- (BOOL) registrarPresent {
    return _registrarPresent;
}

- (void) setDelegate: (id) delegate {
    _delegate = delegate;
}

- (void) setApplicationName: (NSString *) name {
    if (name != _applicationName) {
        [_applicationName release];
        _applicationName = [name copy];
        [self menuChanged];
    }
}

- (BOOL) registrarHasOwner {
    DBusMessage *call = dbus_message_new_method_call(
            "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "NameHasOwner");
    if (call == NULL)
        return NO;

    const char *name = REGISTRAR_NAME;
    appendArgument(call, DBUS_TYPE_STRING, &name);

    DBusError error;
    dbus_error_init(&error);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(
            _connection, call, CALL_TIMEOUT_MS, &error);
    dbus_message_unref(call);
    dbus_error_free(&error);

    dbus_bool_t owned = FALSE;
    if (reply != NULL) {
        int types[] = { DBUS_TYPE_BOOLEAN };
        void *values[] = { &owned };

        readArguments(reply, types, 1, values);
        dbus_message_unref(reply);
    }
    return owned ? YES : NO;
}

- (void) readyToRead {
    if (_connection == NULL)
        return;

    dbus_connection_read_write(_connection, 0);
    [self processMessages];
}

- (void) send: (DBusMessage *) message {
    if (_connection == NULL || message == NULL)
        return;
    dbus_connection_send(_connection, message, NULL);
    dbus_connection_flush(_connection);
}

- (void) processMessages {
    for (;;) {
        if (_connection == NULL)
            return;

        DBusMessage *message = dbus_connection_pop_message(_connection);
        if (message == NULL)
            break;
        [self handleMessage: message];
        dbus_message_unref(message);
    }

    if (_connection != NULL && !dbus_connection_get_is_connected(_connection)) {
        id delegate = _delegate;
        BOOL wasPresent = _registrarPresent;

        [self invalidate];
        _registrarPresent = NO;
        if (wasPresent)
            [delegate dbusMenuRegistrarChanged: self];
    }
}

#pragma mark - Registrar

- (void) registrarOwnerChanged: (BOOL) present {
    if (present == _registrarPresent)
        return;
    _registrarPresent = present;
    if (present)
        for (NSNumber *window in _windows)
            [self sendRegistration: @"RegisterWindow"
                            window: [window unsignedLongValue]];
    [_delegate dbusMenuRegistrarChanged: self];
}

- (void) sendRegistration: (NSString *) method window: (unsigned long) window {
    DBusMessage *message = dbus_message_new_method_call(
            REGISTRAR_NAME, REGISTRAR_PATH, REGISTRAR_INTERFACE,
            [method UTF8String]);
    if (message == NULL)
        return;

    dbus_uint32_t identifier = (dbus_uint32_t) window;
    const char *path = MENU_PATH;
    appendArgument(message, DBUS_TYPE_UINT32, &identifier);
    if ([method isEqualToString: @"RegisterWindow"])
        appendArgument(message, DBUS_TYPE_OBJECT_PATH, &path);
    dbus_message_set_no_reply(message, TRUE);
    [self send: message];
    dbus_message_unref(message);
}

- (void) registerWindow: (unsigned long) window {
    [_windows addObject: [NSNumber numberWithUnsignedLong: window]];
    if (_registrarPresent)
        [self sendRegistration: @"RegisterWindow" window: window];
}

- (void) unregisterWindow: (unsigned long) window {
    NSNumber *key = [NSNumber numberWithUnsignedLong: window];

    if (![_windows containsObject: key])
        return;
    [_windows removeObject: key];
    if (_registrarPresent)
        [self sendRegistration: @"UnregisterWindow" window: window];
}

#pragma mark - Layout

- (void) setMenu: (NSMenu *) menu {
    if (menu == _menu)
        return;
    [_menu release];
    _menu = [menu retain];
    [self menuChanged];
}

// The identifier of an item, kept for as long as the item is in the menu.
- (int) identifierForItem: (NSMenuItem *) item {
    NSValue *key = [NSValue valueWithNonretainedObject: item];
    NSNumber *number = [_idsByItem objectForKey: key];

    if (number == nil) {
        number = [NSNumber numberWithInt: ++_nextID];
        [_idsByItem setObject: number forKey: key];
    }
    return [number intValue];
}

- (NSDictionary *) nodeForItem: (NSMenuItem *) item
                         items: (NSMutableDictionary *) items
                       topItem: (BOOL) top
{
    int identifier = [self identifierForItem: item];
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    NSMenu *submenu = [item submenu];
    NSString *title = [item title];

    [items setObject: item forKey: [NSNumber numberWithInt: identifier]];

    if ([item isSeparatorItem]) {
        [props setObject: @"separator" forKey: @"type"];
    } else {
        if (top && _applicationName != nil)
            title = _applicationName;
        [props setObject: labelForTitle(title != nil ? title : @"")
                  forKey: @"label"];
        [props setObject: boolValue([item isEnabled]) forKey: @"enabled"];
        if ([item state] != 0) {
            [props setObject: @"checkmark" forKey: @"toggle-type"];
            [props setObject: [NSNumber numberWithInt: [item state] > 0 ? 1 : -1]
                      forKey: @"toggle-state"];
        }
        NSArray *shortcut = shortcutForItem(item);
        if (shortcut != nil)
            [props setObject: shortcut forKey: @"shortcut"];
    }
    [props setObject: boolValue(![item isHidden]) forKey: @"visible"];

    NSMutableArray *children = [NSMutableArray array];
    if (submenu != nil) {
        [props setObject: @"submenu" forKey: @"children-display"];
        for (NSMenuItem *child in [submenu itemArray])
            [children addObject: [self nodeForItem: child
                                             items: items
                                           topItem: NO]];
    }

    return @{
        @"id" : [NSNumber numberWithInt: identifier],
        @"props" : props,
        @"children" : children
    };
}

// The whole menu as nested dictionaries (id, props, children). The root has
// identifier 0. Identifiers of items that left the menu are forgotten.
- (NSDictionary *) buildLayout {
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    NSMutableArray *children = [NSMutableArray array];
    BOOL first = YES;

    for (NSMenuItem *item in [_menu itemArray]) {
        [children addObject: [self nodeForItem: item items: items topItem: first]];
        first = NO;
    }

    NSMutableDictionary *live = [NSMutableDictionary dictionary];
    for (NSNumber *identifier in items)
        [live setObject: identifier
                 forKey: [NSValue valueWithNonretainedObject:
                                          [items objectForKey: identifier]]];
    [_idsByItem release];
    _idsByItem = [live retain];
    [_itemsByID release];
    _itemsByID = [items retain];

    return @{
        @"id" : [NSNumber numberWithInt: 0],
        @"props" : @{@"children-display" : @"submenu"},
        @"children" : children
    };
}

static NSDictionary *findNode(NSDictionary *node, int identifier) {
    if ([[node objectForKey: @"id"] intValue] == identifier)
        return node;
    for (NSDictionary *child in [node objectForKey: @"children"]) {
        NSDictionary *found = findNode(child, identifier);
        if (found != nil)
            return found;
    }
    return nil;
}

// The menu an identifier stands for: the submenu of its item, or the main
// menu for the root.
- (NSMenu *) menuForIdentifier: (int) identifier {
    if (identifier == 0)
        return _menu;
    return [[_itemsByID objectForKey: [NSNumber numberWithInt: identifier]]
            submenu];
}

- (void) menuChanged {
    if (_refreshTimer != NULL || _connection == NULL)
        return;

    CFRunLoopTimerContext context = {.version = 0, .info = self};
    _refreshTimer = CFRunLoopTimerCreate(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + REFRESH_DELAY, 0, 0,
            0, refreshCallback, &context);
    CFRunLoopAddTimer(CFRunLoopGetMain(), _refreshTimer, kCFRunLoopCommonModes);
}

static void refreshCallback(CFRunLoopTimerRef timer, void *info) {
    [(X11DBusMenu *) info refresh];
}

// Sends LayoutUpdated if the menu is no longer what a client last fetched.
- (void) refresh {
    if (_refreshTimer != NULL) {
        CFRunLoopTimerInvalidate(_refreshTimer);
        CFRelease(_refreshTimer);
        _refreshTimer = NULL;
    }
    if (_connection == NULL || _servedLayout == nil)
        return;

    NSDictionary *layout = [self buildLayout];
    if ([layout isEqual: _servedLayout])
        return;

    [_servedLayout release];
    _servedLayout = [layout retain];
    _revision++;

    DBusMessage *signal = dbus_message_new_signal(MENU_PATH, MENU_INTERFACE,
                                                  "LayoutUpdated");
    if (signal == NULL)
        return;
    dbus_uint32_t revision = _revision;
    dbus_int32_t parent = 0;
    appendArgument(signal, DBUS_TYPE_UINT32, &revision);
    appendArgument(signal, DBUS_TYPE_INT32, &parent);
    [self send: signal];
    dbus_message_unref(signal);
}

#pragma mark - Serialization

// Appends a property value, as a variant, to the iterator.
static void appendValue(DBusMessageIter *parent, id value) {
    DBusMessageIter variant;

    if ([value isKindOfClass: [NSString class]]) {
        const char *string = [value UTF8String];

        dbus_message_iter_open_container(parent, DBUS_TYPE_VARIANT, "s",
                                         &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &string);
    } else if (isBoolValue(value)) {
        dbus_bool_t flag = [value boolValue];

        dbus_message_iter_open_container(parent, DBUS_TYPE_VARIANT, "b",
                                         &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_BOOLEAN, &flag);
    } else if ([value isKindOfClass: [NSNumber class]]) {
        dbus_int32_t number = [value intValue];

        dbus_message_iter_open_container(parent, DBUS_TYPE_VARIANT, "i",
                                         &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_INT32, &number);
    } else {
        // A shortcut: an array of arrays of strings.
        DBusMessageIter outer;

        dbus_message_iter_open_container(parent, DBUS_TYPE_VARIANT, "aas",
                                         &variant);
        dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "as",
                                         &outer);
        for (NSArray *combination in value) {
            DBusMessageIter inner;

            dbus_message_iter_open_container(&outer, DBUS_TYPE_ARRAY, "s",
                                             &inner);
            for (NSString *part in combination) {
                const char *string = [part UTF8String];

                dbus_message_iter_append_basic(&inner, DBUS_TYPE_STRING,
                                               &string);
            }
            dbus_message_iter_close_container(&outer, &inner);
        }
        dbus_message_iter_close_container(&variant, &outer);
    }
    dbus_message_iter_close_container(parent, &variant);
}

static void appendProperties(DBusMessageIter *parent, NSDictionary *props,
                             NSSet *names) {
    DBusMessageIter array;

    dbus_message_iter_open_container(parent, DBUS_TYPE_ARRAY, "{sv}", &array);
    for (NSString *name in props) {
        if ([names count] > 0 && ![names containsObject: name])
            continue;

        const char *key = [name UTF8String];
        DBusMessageIter entry;

        dbus_message_iter_open_container(&array, DBUS_TYPE_DICT_ENTRY, NULL,
                                         &entry);
        dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
        appendValue(&entry, [props objectForKey: name]);
        dbus_message_iter_close_container(&array, &entry);
    }
    dbus_message_iter_close_container(parent, &array);
}

// Appends the struct (ia{sv}av) of a node and, to the given depth (-1 for no
// limit), its descendants.
static void appendNode(DBusMessageIter *parent, NSDictionary *node, int depth,
                       NSSet *names) {
    DBusMessageIter structure, children;
    dbus_int32_t identifier = [[node objectForKey: @"id"] intValue];

    dbus_message_iter_open_container(parent, DBUS_TYPE_STRUCT, NULL, &structure);
    dbus_message_iter_append_basic(&structure, DBUS_TYPE_INT32, &identifier);
    appendProperties(&structure, [node objectForKey: @"props"], names);
    dbus_message_iter_open_container(&structure, DBUS_TYPE_ARRAY, "v", &children);
    if (depth != 0) {
        for (NSDictionary *child in [node objectForKey: @"children"]) {
            DBusMessageIter variant;

            dbus_message_iter_open_container(&children, DBUS_TYPE_VARIANT,
                                             "(ia{sv}av)", &variant);
            appendNode(&variant, child, depth < 0 ? -1 : depth - 1, names);
            dbus_message_iter_close_container(&children, &variant);
        }
    }
    dbus_message_iter_close_container(&structure, &children);
    dbus_message_iter_close_container(parent, &structure);
}

#pragma mark - Incoming calls

static NSSet *stringArray(DBusMessageIter *iter) {
    NSMutableSet *strings = [NSMutableSet set];

    if (dbus_message_iter_get_arg_type(iter) != DBUS_TYPE_ARRAY)
        return strings;

    DBusMessageIter array;
    dbus_message_iter_recurse(iter, &array);
    while (dbus_message_iter_get_arg_type(&array) == DBUS_TYPE_STRING) {
        const char *string = NULL;

        dbus_message_iter_get_basic(&array, &string);
        [strings addObject: [NSString stringWithUTF8String: string]];
        dbus_message_iter_next(&array);
    }
    return strings;
}

static NSArray *integerArray(DBusMessageIter *iter) {
    NSMutableArray *numbers = [NSMutableArray array];

    if (dbus_message_iter_get_arg_type(iter) != DBUS_TYPE_ARRAY)
        return numbers;

    DBusMessageIter array;
    dbus_message_iter_recurse(iter, &array);
    while (dbus_message_iter_get_arg_type(&array) == DBUS_TYPE_INT32) {
        dbus_int32_t number = 0;

        dbus_message_iter_get_basic(&array, &number);
        [numbers addObject: [NSNumber numberWithInt: number]];
        dbus_message_iter_next(&array);
    }
    return numbers;
}

- (void) replyError: (const char *) name
            message: (const char *) text
                 to: (DBusMessage *) call
{
    if (dbus_message_get_no_reply(call))
        return;

    DBusMessage *reply = dbus_message_new_error(call, name, text);

    [self send: reply];
    if (reply != NULL)
        dbus_message_unref(reply);
}

// Replies to a call with a reply the caller fills in.
- (DBusMessage *) newReplyTo: (DBusMessage *) call {
    return dbus_message_new_method_return(call);
}

- (void) sendReply: (DBusMessage *) reply {
    [self send: reply];
    if (reply != NULL)
        dbus_message_unref(reply);
}

- (void) handleGetLayout: (DBusMessage *) call {
    DBusMessageIter iter;
    dbus_int32_t parent = 0, depth = -1;
    NSSet *names = nil;

    if (dbus_message_iter_init(call, &iter)) {
        dbus_message_iter_get_basic(&iter, &parent);
        dbus_message_iter_next(&iter);
        dbus_message_iter_get_basic(&iter, &depth);
        dbus_message_iter_next(&iter);
        names = stringArray(&iter);
    }

    NSDictionary *layout = [self buildLayout];
    NSDictionary *node = findNode(layout, parent);
    if (node == nil) {
        [self replyError: DBUS_ERROR_INVALID_ARGS
                 message: "No such menu item"
                      to: call];
        return;
    }

    [_servedLayout release];
    _servedLayout = [layout retain];

    DBusMessage *reply = [self newReplyTo: call];
    DBusMessageIter out;
    dbus_uint32_t revision = _revision;

    dbus_message_iter_init_append(reply, &out);
    dbus_message_iter_append_basic(&out, DBUS_TYPE_UINT32, &revision);
    appendNode(&out, node, depth, names);
    [self sendReply: reply];
}

- (void) handleGetGroupProperties: (DBusMessage *) call {
    DBusMessageIter iter;
    NSArray *identifiers = nil;
    NSSet *names = nil;

    if (dbus_message_iter_init(call, &iter)) {
        identifiers = integerArray(&iter);
        dbus_message_iter_next(&iter);
        names = stringArray(&iter);
    }

    NSDictionary *layout = [self buildLayout];
    DBusMessage *reply = [self newReplyTo: call];
    DBusMessageIter out, array;

    dbus_message_iter_init_append(reply, &out);
    dbus_message_iter_open_container(&out, DBUS_TYPE_ARRAY, "(ia{sv})", &array);
    for (NSNumber *identifier in identifiers) {
        NSDictionary *node = findNode(layout, [identifier intValue]);
        DBusMessageIter structure;
        dbus_int32_t value = [identifier intValue];

        if (node == nil)
            continue;
        dbus_message_iter_open_container(&array, DBUS_TYPE_STRUCT, NULL,
                                         &structure);
        dbus_message_iter_append_basic(&structure, DBUS_TYPE_INT32, &value);
        appendProperties(&structure, [node objectForKey: @"props"], names);
        dbus_message_iter_close_container(&array, &structure);
    }
    dbus_message_iter_close_container(&out, &array);
    [self sendReply: reply];
}

- (void) handleGetProperty: (DBusMessage *) call {
    dbus_int32_t identifier = 0;
    const char *name = NULL;

    int types[] = { DBUS_TYPE_INT32, DBUS_TYPE_STRING };
    void *values[] = { &identifier, &name };

    if (!readArguments(call, types, 2, values)) {
        [self replyError: DBUS_ERROR_INVALID_ARGS message: "Bad arguments" to: call];
        return;
    }

    NSDictionary *node = findNode([self buildLayout], identifier);
    NSDictionary *props = [node objectForKey: @"props"];
    NSString *key = [NSString stringWithUTF8String: name];

    if ([props objectForKey: key] == nil) {
        [self replyError: DBUS_ERROR_INVALID_ARGS
                 message: "No such property"
                      to: call];
        return;
    }

    DBusMessage *reply = [self newReplyTo: call];
    DBusMessageIter out;

    dbus_message_iter_init_append(reply, &out);
    appendValue(&out, [props objectForKey: key]);
    [self sendReply: reply];
}

- (void) performEvent: (NSString *) event forIdentifier: (int) identifier {
    NSMenuItem *item = [_itemsByID objectForKey: [NSNumber numberWithInt: identifier]];
    NSMenu *menu = [item menu];

    if (item == nil || menu == nil)
        return;

    if ([event isEqualToString: @"clicked"]) {
        NSInteger index = [menu indexOfItem: item];

        if (![item hasSubmenu] && index != NSNotFound)
            [menu performActionForItemAtIndex: index];
    } else if ([event isEqualToString: @"opened"]) {
        id delegate = [[item submenu] delegate];

        if ([delegate respondsToSelector: @selector(menuWillOpen:)])
            [delegate menuWillOpen: [item submenu]];
    } else if ([event isEqualToString: @"closed"]) {
        id delegate = [[item submenu] delegate];

        if ([delegate respondsToSelector: @selector(menuDidClose:)])
            [delegate menuDidClose: [item submenu]];
    } else if ([event isEqualToString: @"hovered"]) {
        id delegate = [menu delegate];

        if ([delegate respondsToSelector: @selector(menu:willHighlightItem:)])
            [delegate menu: menu willHighlightItem: item];
    }
    [self menuChanged];
}

- (void) handleEvent: (DBusMessage *) call {
    dbus_int32_t identifier = 0;
    const char *event = NULL;

    int types[] = { DBUS_TYPE_INT32, DBUS_TYPE_STRING };
    void *values[] = { &identifier, &event };

    if (!readArguments(call, types, 2, values)) {
        [self replyError: DBUS_ERROR_INVALID_ARGS message: "Bad arguments" to: call];
        return;
    }
    [self performEvent: [NSString stringWithUTF8String: event]
         forIdentifier: identifier];
    [self sendReply: [self newReplyTo: call]];
}

- (void) handleEventGroup: (DBusMessage *) call {
    DBusMessageIter iter;

    if (dbus_message_iter_init(call, &iter) &&
        dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_ARRAY) {
        DBusMessageIter array;

        dbus_message_iter_recurse(&iter, &array);
        while (dbus_message_iter_get_arg_type(&array) == DBUS_TYPE_STRUCT) {
            DBusMessageIter structure;
            dbus_int32_t identifier = 0;
            const char *event = NULL;

            dbus_message_iter_recurse(&array, &structure);
            dbus_message_iter_get_basic(&structure, &identifier);
            dbus_message_iter_next(&structure);
            dbus_message_iter_get_basic(&structure, &event);
            [self performEvent: [NSString stringWithUTF8String: event]
                 forIdentifier: identifier];
            dbus_message_iter_next(&array);
        }
    }

    DBusMessage *reply = [self newReplyTo: call];
    DBusMessageIter out, errors;

    dbus_message_iter_init_append(reply, &out);
    dbus_message_iter_open_container(&out, DBUS_TYPE_ARRAY, "i", &errors);
    dbus_message_iter_close_container(&out, &errors);
    [self sendReply: reply];
}

// Brings the menu with the identifier up to date, as before it is shown, and
// says whether what a client fetched earlier is out of date.
- (BOOL) aboutToShow: (int) identifier {
    NSDictionary *before = _servedLayout;

    [self buildLayout];

    NSMenu *menu = [self menuForIdentifier: identifier];
    // Updating asks the delegate (-menuNeedsUpdate:) and validates the items.
    [menu update];

    NSDictionary *after = [self buildLayout];
    return before == nil || ![after isEqual: before];
}

- (void) handleAboutToShow: (DBusMessage *) call {
    dbus_int32_t identifier = 0;

    int types[] = { DBUS_TYPE_INT32 };
    void *values[] = { &identifier };

    if (!readArguments(call, types, 1, values)) {
        [self replyError: DBUS_ERROR_INVALID_ARGS message: "Bad arguments" to: call];
        return;
    }

    dbus_bool_t needUpdate = [self aboutToShow: identifier];
    DBusMessage *reply = [self newReplyTo: call];

    appendArgument(reply, DBUS_TYPE_BOOLEAN, &needUpdate);
    [self sendReply: reply];
}

- (void) handleAboutToShowGroup: (DBusMessage *) call {
    DBusMessageIter iter;
    NSArray *identifiers = nil;

    if (dbus_message_iter_init(call, &iter))
        identifiers = integerArray(&iter);

    DBusMessage *reply = [self newReplyTo: call];
    DBusMessageIter out, updates, errors;

    dbus_message_iter_init_append(reply, &out);
    dbus_message_iter_open_container(&out, DBUS_TYPE_ARRAY, "i", &updates);
    for (NSNumber *identifier in identifiers) {
        if ([self aboutToShow: [identifier intValue]]) {
            dbus_int32_t value = [identifier intValue];

            dbus_message_iter_append_basic(&updates, DBUS_TYPE_INT32, &value);
        }
    }
    dbus_message_iter_close_container(&out, &updates);
    dbus_message_iter_open_container(&out, DBUS_TYPE_ARRAY, "i", &errors);
    dbus_message_iter_close_container(&out, &errors);
    [self sendReply: reply];
}

- (void) handleProperties: (DBusMessage *) call {
    const char *member = dbus_message_get_member(call);
    BOOL all = strcmp(member, "GetAll") == 0;

    if (!all && strcmp(member, "Get") != 0) {
        [self replyError: DBUS_ERROR_UNKNOWN_METHOD message: member to: call];
        return;
    }

    DBusMessageIter iter;
    const char *interface = "", *name = "";

    if (dbus_message_iter_init(call, &iter)) {
        dbus_message_iter_get_basic(&iter, &interface);
        if (!all && dbus_message_iter_next(&iter))
            dbus_message_iter_get_basic(&iter, &name);
    }
    if (strcmp(interface, MENU_INTERFACE) != 0 && interface[0] != '\0') {
        [self replyError: DBUS_ERROR_UNKNOWN_INTERFACE message: interface to: call];
        return;
    }

    static const char *const names[] = {"Version", "TextDirection", "Status",
                                        "IconThemePath"};
    DBusMessage *reply = [self newReplyTo: call];
    DBusMessageIter out, array;
    BOOL found = NO;

    dbus_message_iter_init_append(reply, &out);
    if (all)
        dbus_message_iter_open_container(&out, DBUS_TYPE_ARRAY, "{sv}", &array);

    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        if (!all && strcmp(name, names[i]) != 0)
            continue;

        DBusMessageIter entry, variant;
        DBusMessageIter *target = &out;

        if (all) {
            dbus_message_iter_open_container(&array, DBUS_TYPE_DICT_ENTRY, NULL,
                                             &entry);
            const char *propertyName = names[i];

            dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING,
                                           &propertyName);
            target = &entry;
        }
        switch (i) {
        case 0: {
            dbus_uint32_t version = 3;

            dbus_message_iter_open_container(target, DBUS_TYPE_VARIANT, "u",
                                             &variant);
            dbus_message_iter_append_basic(&variant, DBUS_TYPE_UINT32, &version);
            break;
        }
        case 1:
        case 2: {
            const char *value = i == 1 ? "ltr" : "normal";

            dbus_message_iter_open_container(target, DBUS_TYPE_VARIANT, "s",
                                             &variant);
            dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &value);
            break;
        }
        default: {
            DBusMessageIter empty;

            dbus_message_iter_open_container(target, DBUS_TYPE_VARIANT, "as",
                                             &variant);
            dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "s",
                                             &empty);
            dbus_message_iter_close_container(&variant, &empty);
            break;
        }
        }
        dbus_message_iter_close_container(target, &variant);
        if (all)
            dbus_message_iter_close_container(&array, &entry);
        found = YES;
    }
    if (all)
        dbus_message_iter_close_container(&out, &array);

    if (!found) {
        dbus_message_unref(reply);
        [self replyError: DBUS_ERROR_INVALID_ARGS message: name to: call];
        return;
    }
    [self sendReply: reply];
}

- (void) handleMethodCall: (DBusMessage *) call {
    const char *interface = dbus_message_get_interface(call);
    const char *member = dbus_message_get_member(call);
    const char *path = dbus_message_get_path(call);

    if (path == NULL || strcmp(path, MENU_PATH) != 0) {
        [self replyError: DBUS_ERROR_UNKNOWN_OBJECT message: "Unknown object" to: call];
        return;
    }

    if (interface != NULL && strcmp(interface, INTROSPECTABLE_INTERFACE) == 0) {
        DBusMessage *reply = [self newReplyTo: call];

        appendArgument(reply, DBUS_TYPE_STRING, &introspectionXML);
        [self sendReply: reply];
    } else if (interface != NULL && strcmp(interface, PROPERTIES_INTERFACE) == 0) {
        [self handleProperties: call];
    } else if (interface != NULL && strcmp(interface, MENU_INTERFACE) == 0) {
        if (strcmp(member, "GetLayout") == 0)
            [self handleGetLayout: call];
        else if (strcmp(member, "GetGroupProperties") == 0)
            [self handleGetGroupProperties: call];
        else if (strcmp(member, "GetProperty") == 0)
            [self handleGetProperty: call];
        else if (strcmp(member, "Event") == 0)
            [self handleEvent: call];
        else if (strcmp(member, "EventGroup") == 0)
            [self handleEventGroup: call];
        else if (strcmp(member, "AboutToShow") == 0)
            [self handleAboutToShow: call];
        else if (strcmp(member, "AboutToShowGroup") == 0)
            [self handleAboutToShowGroup: call];
        else
            [self replyError: DBUS_ERROR_UNKNOWN_METHOD message: member to: call];
    } else {
        [self replyError: DBUS_ERROR_UNKNOWN_INTERFACE
                 message: "Unknown interface"
                      to: call];
    }
}

- (void) handleMessage: (DBusMessage *) message {
    switch (dbus_message_get_type(message)) {
    case DBUS_MESSAGE_TYPE_METHOD_CALL:
        [self handleMethodCall: message];
        break;
    case DBUS_MESSAGE_TYPE_SIGNAL:
        if (dbus_message_is_signal(message, "org.freedesktop.DBus",
                                   "NameOwnerChanged")) {
            const char *name = NULL, *oldOwner = NULL, *newOwner = NULL;

            int types[] = { DBUS_TYPE_STRING, DBUS_TYPE_STRING,
                            DBUS_TYPE_STRING };
            void *values[] = { &name, &oldOwner, &newOwner };

            if (readArguments(message, types, 3, values) &&
                strcmp(name, REGISTRAR_NAME) == 0)
                [self registrarOwnerChanged: newOwner[0] != '\0'];
        }
        break;
    default:
        break;
    }
}

@end
