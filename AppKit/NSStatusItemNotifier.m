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

// The protocol is StatusNotifierItem / StatusNotifierWatcher, as published at
// https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/ and in the
// interface descriptions of KDE's plasma-workspace
// (https://github.com/KDE/plasma-workspace/tree/master/statusnotifierwatcher).

#import "NSStatusItemNotifier.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSDBusMenu.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSStatusBar.h>
#import <AppKit/NSStatusItem+Private.h>
#import <AppKit/NSStatusItem.h>
#import <AppKit/NSStringDrawing.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>
#import <string.h>
#import <unistd.h>

#define WATCHER_NAME "org.kde.StatusNotifierWatcher"
#define WATCHER_PATH "/StatusNotifierWatcher"
#define WATCHER_INTERFACE "org.kde.StatusNotifierWatcher"
#define ITEM_PATH "/StatusNotifierItem"
#define ITEM_INTERFACE "org.kde.StatusNotifierItem"
#define MENU_PATH "/StatusNotifierItem/Menu"
#define PROPERTIES_INTERFACE "org.freedesktop.DBus.Properties"
#define INTROSPECTABLE_INTERFACE "org.freedesktop.DBus.Introspectable"

// Icons are drawn for a tray slot of this many points, at 1x and 2x.
#define SLOT_POINTS 22
#define TEXT_MAX_POINTS 220
// Changes arriving within this time are reported together.
#define FLUSH_DELAY 0.02

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
        "  <signal name=\"PropertiesChanged\"><arg type=\"s\"/>"
        "<arg type=\"a{sv}\"/><arg type=\"as\"/></signal>\n"
        " </interface>\n"
        " <interface name=\"org.kde.StatusNotifierItem\">\n"
        "  <property name=\"Category\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"Id\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"Title\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"Status\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"WindowId\" type=\"u\" access=\"read\"/>\n"
        "  <property name=\"IconThemePath\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"Menu\" type=\"o\" access=\"read\"/>\n"
        "  <property name=\"ItemIsMenu\" type=\"b\" access=\"read\"/>\n"
        "  <property name=\"IconName\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"IconPixmap\" type=\"a(iiay)\" access=\"read\"/>\n"
        "  <property name=\"OverlayIconName\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"OverlayIconPixmap\" type=\"a(iiay)\" access=\"read\"/>\n"
        "  <property name=\"AttentionIconName\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"AttentionIconPixmap\" type=\"a(iiay)\" access=\"read\"/>\n"
        "  <property name=\"AttentionMovieName\" type=\"s\" access=\"read\"/>\n"
        "  <property name=\"ToolTip\" type=\"(sa(iiay)ss)\" access=\"read\"/>\n"
        "  <method name=\"ContextMenu\"><arg type=\"i\" direction=\"in\"/>"
        "<arg type=\"i\" direction=\"in\"/></method>\n"
        "  <method name=\"Activate\"><arg type=\"i\" direction=\"in\"/>"
        "<arg type=\"i\" direction=\"in\"/></method>\n"
        "  <method name=\"SecondaryActivate\"><arg type=\"i\" direction=\"in\"/>"
        "<arg type=\"i\" direction=\"in\"/></method>\n"
        "  <method name=\"Scroll\"><arg type=\"i\" direction=\"in\"/>"
        "<arg type=\"s\" direction=\"in\"/></method>\n"
        "  <signal name=\"NewTitle\"/>\n"
        "  <signal name=\"NewIcon\"/>\n"
        "  <signal name=\"NewAttentionIcon\"/>\n"
        "  <signal name=\"NewOverlayIcon\"/>\n"
        "  <signal name=\"NewToolTip\"/>\n"
        "  <signal name=\"NewStatus\"><arg type=\"s\"/></signal>\n"
        " </interface>\n"
        "</node>\n";

static const char *const propertyNames[] = {
    "Category", "Id", "Title", "Status", "WindowId", "IconThemePath", "Menu",
    "ItemIsMenu", "IconName", "IconPixmap", "OverlayIconName",
    "OverlayIconPixmap", "AttentionIconName", "AttentionIconPixmap",
    "AttentionMovieName", "ToolTip"};
#define PROPERTY_COUNT (sizeof(propertyNames) / sizeof(propertyNames[0]))

#pragma mark - Icon rendering

// Template images are masks. Trays that show pixmaps do not recolour them, and
// most of them are dark, so a template is drawn in a light grey.
static void templateColor(CGFloat *components) {
    components[0] = components[1] = components[2] = 0.92;
    components[3] = 1.0;
}

// Renders the image, or else the text, into a width x height bitmap in
// pixels and returns the pixels the way the protocol wants them: ARGB, one
// byte each, with straight (not premultiplied) alpha. The content is drawn at
// the given number of pixels per point.
static NSData *renderPixels(NSImage *image, NSString *text, int width,
                            int height, int scale) {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
            NULL, width, height, 8, 0, colorSpace,
            kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);

    CGColorSpaceRelease(colorSpace);
    if (context == NULL)
        return nil;

    CGFloat tint[4];
    templateColor(tint);

    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSGraphicsContext *graphicsContext =
            [NSGraphicsContext graphicsContextWithGraphicsPort: context
                                                       flipped: NO];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: graphicsContext];

    if (image != nil) {
        // Aspect fit, centered, never enlarged.
        NSSize size = [image size];
        CGFloat factor = 1.0;

        if (size.width * scale > width)
            factor = width / (size.width * scale);
        if (size.height * scale * factor > height)
            factor = height / (size.height * scale);

        NSSize drawn = NSMakeSize(size.width * scale * factor,
                                  size.height * scale * factor);
        NSRect rect = NSMakeRect((width - drawn.width) / 2,
                                 (height - drawn.height) / 2, drawn.width,
                                 drawn.height);

        [image drawInRect: rect
                 fromRect: NSZeroRect
                operation: NSCompositeSourceOver
                 fraction: 1.0];
        if ([image isTemplate]) {
            // Keep the shape (the alpha), replace the colour.
            CGContextSetBlendMode(context, kCGBlendModeSourceIn);
            CGContextSetRGBFillColor(context, tint[0], tint[1], tint[2],
                                     tint[3]);
            CGContextFillRect(context, CGRectMake(0, 0, width, height));
        }
    } else {
        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        NSFont *font = [NSFont systemFontOfSize: 13.0 * scale];
        NSColor *color = [NSColor colorWithCalibratedRed: tint[0]
                                                   green: tint[1]
                                                    blue: tint[2]
                                                   alpha: tint[3]];

        [attributes setObject: font forKey: NSFontAttributeName];
        [attributes setObject: color forKey: NSForegroundColorAttributeName];

        NSSize size = [text sizeWithAttributes: attributes];
        NSPoint origin = NSMakePoint((width - size.width) / 2,
                                     (height - size.height) / 2);

        [text drawAtPoint: origin withAttributes: attributes];
    }

    [NSGraphicsContext restoreGraphicsState];
    [pool release];

    const uint8_t *source = CGBitmapContextGetData(context);
    size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);
    NSMutableData *data = [NSMutableData dataWithLength: (NSUInteger) width * height * 4];
    uint8_t *target = [data mutableBytes];

    for (int row = 0; row < height; row++) {
        const uint8_t *in = source + row * bytesPerRow;

        for (int column = 0; column < width; column++, in += 4, target += 4) {
            // Premultiplied BGRA in memory (little-endian ARGB word).
            unsigned alpha = in[3];

            target[0] = (uint8_t) alpha;
            if (alpha == 0) {
                target[1] = target[2] = target[3] = 0;
            } else {
                target[1] = (uint8_t) MIN(255u, (in[2] * 255u + alpha / 2) / alpha);
                target[2] = (uint8_t) MIN(255u, (in[1] * 255u + alpha / 2) / alpha);
                target[3] = (uint8_t) MIN(255u, (in[0] * 255u + alpha / 2) / alpha);
            }
        }
    }
    CGContextRelease(context);
    return data;
}

#pragma mark - Message building

static void appendStringVariant(DBusMessageIter *parent, const char *value) {
    DBusMessageIter variant;

    dbus_message_iter_open_container(parent, DBUS_TYPE_VARIANT, "s", &variant);
    dbus_message_iter_append_basic(&variant, DBUS_TYPE_STRING, &value);
    dbus_message_iter_close_container(parent, &variant);
}

// One (iiay) element.
static void appendPixmap(DBusMessageIter *array, NSDictionary *pixmap) {
    DBusMessageIter structure, bytes;
    dbus_int32_t width = [[pixmap objectForKey: @"width"] intValue];
    dbus_int32_t height = [[pixmap objectForKey: @"height"] intValue];
    NSData *data = [pixmap objectForKey: @"data"];
    const void *pointer = [data bytes];

    dbus_message_iter_open_container(array, DBUS_TYPE_STRUCT, NULL, &structure);
    dbus_message_iter_append_basic(&structure, DBUS_TYPE_INT32, &width);
    dbus_message_iter_append_basic(&structure, DBUS_TYPE_INT32, &height);
    dbus_message_iter_open_container(&structure, DBUS_TYPE_ARRAY, "y", &bytes);
    dbus_message_iter_append_fixed_array(&bytes, DBUS_TYPE_BYTE, &pointer,
                                         (int) [data length]);
    dbus_message_iter_close_container(&structure, &bytes);
    dbus_message_iter_close_container(array, &structure);
}

// An a(iiay) value, as a variant if wrapped.
static void appendPixmaps(DBusMessageIter *parent, NSArray *pixmaps,
                          BOOL wrapped) {
    DBusMessageIter variant, array;
    DBusMessageIter *target = parent;

    if (wrapped) {
        dbus_message_iter_open_container(parent, DBUS_TYPE_VARIANT, "a(iiay)",
                                         &variant);
        target = &variant;
    }
    dbus_message_iter_open_container(target, DBUS_TYPE_ARRAY, "(iiay)", &array);
    for (NSDictionary *pixmap in pixmaps)
        appendPixmap(&array, pixmap);
    dbus_message_iter_close_container(target, &array);
    if (wrapped)
        dbus_message_iter_close_container(parent, &variant);
}

static NSString *applicationIdentifier(void) {
    NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];

    return [identifier length] > 0 ? identifier
                                   : [[NSProcessInfo processInfo] processName];
}

@implementation NSStatusItemNotifier

static unsigned itemCounter;

- (instancetype) initWithStatusItem: (NSStatusItem *) item {
    if ((self = [super init]) == nil)
        return nil;

    _bus = [[NSDBusMenu alloc] initWithSessionBus];
    if (_bus == nil) {
        [self release];
        return nil;
    }
    _item = item;
    [_bus setObjectPath: @MENU_PATH];
    [_bus setDelegate: self];

    DBusConnection *connection = [_bus connection];
    DBusError error;

    // The protocol names an item by a bus name of this form.
    _serviceName = [[NSString stringWithFormat: @"org.kde.StatusNotifierItem-%d-%u",
                                                (int) getpid(), ++itemCounter] retain];
    dbus_error_init(&error);
    // The name is only a handle for the watcher; keeping the name is not
    // required for the item to work, so a refusal is not an error.
    dbus_bus_request_name(connection, [_serviceName UTF8String],
                          DBUS_NAME_FLAG_DO_NOT_QUEUE, &error);
    dbus_error_free(&error);

    dbus_bus_add_match(connection,
                       "type='signal',sender='org.freedesktop.DBus',"
                       "interface='org.freedesktop.DBus',member='"
                       "NameOwnerChanged',arg0='" WATCHER_NAME "'",
                       NULL);

    [[NSNotificationCenter defaultCenter]
            addObserver: self
               selector: @selector(menuStructureChanged:)
                   name: NSMenuDidAddItemNotification
                 object: nil];
    [[NSNotificationCenter defaultCenter]
            addObserver: self
               selector: @selector(menuStructureChanged:)
                   name: NSMenuDidRemoveItemNotification
                 object: nil];
    [[NSNotificationCenter defaultCenter]
            addObserver: self
               selector: @selector(menuStructureChanged:)
                   name: NSMenuDidChangeItemNotification
                 object: nil];

    [_bus setMenu: [item menu]];
    [self registerWithWatcher];
    return self;
}

- (void) dealloc {
    [self invalidate];
    [_serviceName release];
    [_pixmaps release];
    [super dealloc];
}

- (void) invalidate {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    if (_flushTimer != NULL) {
        CFRunLoopTimerInvalidate(_flushTimer);
        CFRelease(_flushTimer);
        _flushTimer = NULL;
    }
    // Closing the connection releases the item's name, which is how a watcher
    // learns that the item is gone.
    [_bus invalidate];
    [_bus release];
    _bus = nil;
    _item = nil;
}

#pragma mark - Watcher

// A watcher that is not there answers the call with an error nobody reads
// (the call asks for no reply); one that appears later, or comes back, is
// registered with when its name gets an owner.
- (void) registerWithWatcher {
    if (_bus == nil)
        return;

    DBusMessage *message = dbus_message_new_method_call(
            WATCHER_NAME, WATCHER_PATH, WATCHER_INTERFACE,
            "RegisterStatusNotifierItem");
    if (message == NULL)
        return;

    const char *service = [_serviceName UTF8String];

    NSDBusAppendArgument(message, DBUS_TYPE_STRING, &service);
    dbus_message_set_no_reply(message, TRUE);
    [_bus send: message];
    dbus_message_unref(message);
}

- (BOOL) handleWatcherChange: (DBusMessage *) message {
    const char *name = NULL, *oldOwner = NULL, *newOwner = NULL;
    int types[] = {DBUS_TYPE_STRING, DBUS_TYPE_STRING, DBUS_TYPE_STRING};
    void *values[] = {&name, &oldOwner, &newOwner};

    if (!NSDBusReadArguments(message, types, 3, values) ||
        strcmp(name, WATCHER_NAME) != 0)
        return NO;

    if (newOwner[0] != '\0')
        [self registerWithWatcher];
    return YES;
}

#pragma mark - Item state

- (NSString *) status {
    return [_item isVisible] && [self hasContent] ? @"Active" : @"Passive";
}

- (BOOL) hasContent {
    return [_item image] != nil || [[_item title] length] > 0 ||
           [[[_item attributedTitle] string] length] > 0;
}

// The identifier hosts remember positions by: the application, and the name of
// the item within it.
- (NSString *) identifier {
    NSString *name = [_item autosaveName];

    return [NSString stringWithFormat: @"%@-%@", applicationIdentifier(),
                                       name != nil ? name : @"Item"];
}

- (NSString *) title {
    NSString *title = [_item title];

    return [title length] > 0 ? title : [[NSProcessInfo processInfo] processName];
}

// The pixmaps of the item's image or, without an image, of its title.
- (NSArray *) iconPixmaps {
    if (_pixmaps != nil)
        return _pixmaps;

    NSImage *image = [_item image];
    NSString *text = [_item title];
    NSAttributedString *attributed = [_item attributedTitle];

    if ([text length] == 0)
        text = [attributed string];

    _pixmaps = [NSMutableArray new];
    if (image == nil && [text length] == 0)
        return _pixmaps;

    for (int scale = 1; scale <= 2; scale++) {
        int height = SLOT_POINTS * scale;
        int width = height;

        if (image == nil) {
            NSDictionary *attributes = [NSDictionary
                    dictionaryWithObject: [NSFont systemFontOfSize: 13.0 * scale]
                                  forKey: NSFontAttributeName];
            CGFloat measured = [text sizeWithAttributes: attributes].width;

            width = (int) MIN(ceil(measured) + 4 * scale,
                              (CGFloat) TEXT_MAX_POINTS * scale);
        }

        NSData *data = renderPixels(image, text, width, height, scale);

        if (data != nil)
            [_pixmaps addObject: @{
                @"width" : [NSNumber numberWithInt: width],
                @"height" : [NSNumber numberWithInt: height],
                @"data" : data
            }];
    }
    return _pixmaps;
}

// Appends the value of a property, as a variant, to the iterator; NO for a
// name that is not a property.
- (BOOL) appendProperty: (const char *) name to: (DBusMessageIter *) parent {
    DBusMessageIter variant;

    if (strcmp(name, "Category") == 0) {
        appendStringVariant(parent, "ApplicationStatus");
    } else if (strcmp(name, "Id") == 0) {
        appendStringVariant(parent, [[self identifier] UTF8String]);
    } else if (strcmp(name, "Title") == 0) {
        appendStringVariant(parent, [[self title] UTF8String]);
    } else if (strcmp(name, "Status") == 0) {
        appendStringVariant(parent, [[self status] UTF8String]);
    } else if (strcmp(name, "WindowId") == 0) {
        dbus_uint32_t window = 0;

        dbus_message_iter_open_container(parent, DBUS_TYPE_VARIANT, "u", &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_UINT32, &window);
        dbus_message_iter_close_container(parent, &variant);
    } else if (strcmp(name, "IconThemePath") == 0 ||
               strcmp(name, "IconName") == 0 ||
               strcmp(name, "OverlayIconName") == 0 ||
               strcmp(name, "AttentionIconName") == 0 ||
               strcmp(name, "AttentionMovieName") == 0) {
        appendStringVariant(parent, "");
    } else if (strcmp(name, "Menu") == 0) {
        // The root path stands for no menu.
        const char *path = [_item menu] != nil ? MENU_PATH : "/";

        dbus_message_iter_open_container(parent, DBUS_TYPE_VARIANT, "o", &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_OBJECT_PATH, &path);
        dbus_message_iter_close_container(parent, &variant);
    } else if (strcmp(name, "ItemIsMenu") == 0) {
        // The desktop shows the menu itself when the item is clicked.
        dbus_bool_t isMenu = [_item menu] != nil;

        dbus_message_iter_open_container(parent, DBUS_TYPE_VARIANT, "b", &variant);
        dbus_message_iter_append_basic(&variant, DBUS_TYPE_BOOLEAN, &isMenu);
        dbus_message_iter_close_container(parent, &variant);
    } else if (strcmp(name, "IconPixmap") == 0) {
        appendPixmaps(parent, [self iconPixmaps], YES);
    } else if (strcmp(name, "OverlayIconPixmap") == 0 ||
               strcmp(name, "AttentionIconPixmap") == 0) {
        appendPixmaps(parent, @[], YES);
    } else if (strcmp(name, "ToolTip") == 0) {
        DBusMessageIter structure;
        const char *icon = "";
        const char *title = [[_item toolTip] UTF8String];
        const char *description = "";

        if (title == NULL)
            title = "";
        dbus_message_iter_open_container(parent, DBUS_TYPE_VARIANT,
                                         "(sa(iiay)ss)", &variant);
        dbus_message_iter_open_container(&variant, DBUS_TYPE_STRUCT, NULL,
                                         &structure);
        dbus_message_iter_append_basic(&structure, DBUS_TYPE_STRING, &icon);
        appendPixmaps(&structure, @[], NO);
        dbus_message_iter_append_basic(&structure, DBUS_TYPE_STRING, &title);
        dbus_message_iter_append_basic(&structure, DBUS_TYPE_STRING, &description);
        dbus_message_iter_close_container(&variant, &structure);
        dbus_message_iter_close_container(parent, &variant);
    } else {
        return NO;
    }
    return YES;
}

#pragma mark - Changes

- (void) menuStructureChanged: (NSNotification *) notification {
    NSMenu *menu = [notification object];
    NSMenu *root = [_item menu];

    while ([menu supermenu] != nil && menu != root)
        menu = [menu supermenu];
    if (root != nil && menu == root)
        [_bus menuChanged];
}

static void flushCallback(CFRunLoopTimerRef timer, void *info) {
    [(NSStatusItemNotifier *) info flush];
}

- (void) itemChanged: (NSUInteger) aspects {
    if (_bus == nil)
        return;
    if (aspects & NSStatusItemNotifierIcon) {
        [_pixmaps release];
        _pixmaps = nil;
    }
    // A change of content can turn the status over from passive to active.
    if (aspects & (NSStatusItemNotifierIcon | NSStatusItemNotifierTitle))
        aspects |= NSStatusItemNotifierStatus;
    if (aspects & NSStatusItemNotifierMenu)
        [_bus setMenu: [_item menu]];

    _pending |= aspects;
    if (_flushTimer == NULL) {
        CFRunLoopTimerContext context = {.version = 0, .info = self};

        _flushTimer = CFRunLoopTimerCreate(
                kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + FLUSH_DELAY, 0,
                0, 0, flushCallback, &context);
        CFRunLoopAddTimer(CFRunLoopGetMain(), _flushTimer, kCFRunLoopCommonModes);
    }
}

- (void) sendSignal: (const char *) name status: (NSString *) status {
    DBusMessage *signal = dbus_message_new_signal(ITEM_PATH, ITEM_INTERFACE, name);

    if (signal == NULL)
        return;
    if (status != nil) {
        const char *value = [status UTF8String];

        NSDBusAppendArgument(signal, DBUS_TYPE_STRING, &value);
    }
    [_bus send: signal];
    dbus_message_unref(signal);
}

// org.freedesktop.DBus.Properties.PropertiesChanged for Menu and ItemIsMenu,
// which have no signal of their own.
- (void) sendMenuPropertiesChanged {
    DBusMessage *signal = dbus_message_new_signal(ITEM_PATH, PROPERTIES_INTERFACE,
                                                  "PropertiesChanged");
    if (signal == NULL)
        return;

    DBusMessageIter out, changed, invalidated;
    const char *interface = ITEM_INTERFACE;
    static const char *const names[] = {"Menu", "ItemIsMenu"};

    dbus_message_iter_init_append(signal, &out);
    dbus_message_iter_append_basic(&out, DBUS_TYPE_STRING, &interface);
    dbus_message_iter_open_container(&out, DBUS_TYPE_ARRAY, "{sv}", &changed);
    for (int i = 0; i < 2; i++) {
        DBusMessageIter entry;
        const char *key = names[i];

        dbus_message_iter_open_container(&changed, DBUS_TYPE_DICT_ENTRY, NULL, &entry);
        dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
        [self appendProperty: key to: &entry];
        dbus_message_iter_close_container(&changed, &entry);
    }
    dbus_message_iter_close_container(&out, &changed);
    dbus_message_iter_open_container(&out, DBUS_TYPE_ARRAY, "s", &invalidated);
    dbus_message_iter_close_container(&out, &invalidated);
    [_bus send: signal];
    dbus_message_unref(signal);
}

- (void) flush {
    if (_flushTimer != NULL) {
        CFRunLoopTimerInvalidate(_flushTimer);
        CFRelease(_flushTimer);
        _flushTimer = NULL;
    }
    if (_bus == nil)
        return;

    NSUInteger pending = _pending;

    _pending = 0;
    if (pending & NSStatusItemNotifierTitle)
        [self sendSignal: "NewTitle" status: nil];
    if (pending & NSStatusItemNotifierIcon)
        [self sendSignal: "NewIcon" status: nil];
    if (pending & NSStatusItemNotifierToolTip)
        [self sendSignal: "NewToolTip" status: nil];
    if (pending & NSStatusItemNotifierMenu)
        [self sendMenuPropertiesChanged];
    if (pending & NSStatusItemNotifierStatus)
        [self sendSignal: "NewStatus" status: [self status]];
}

#pragma mark - Incoming calls

- (void) replyError: (const char *) name to: (DBusMessage *) call {
    if (dbus_message_get_no_reply(call))
        return;

    DBusMessage *reply = dbus_message_new_error(call, name, "");

    if (reply == NULL)
        return;
    [_bus send: reply];
    dbus_message_unref(reply);
}

- (void) replyTo: (DBusMessage *) call {
    if (dbus_message_get_no_reply(call))
        return;

    DBusMessage *reply = dbus_message_new_method_return(call);

    if (reply == NULL)
        return;
    [_bus send: reply];
    dbus_message_unref(reply);
}

- (void) handleProperties: (DBusMessage *) call {
    const char *member = dbus_message_get_member(call);
    BOOL all = strcmp(member, "GetAll") == 0;

    if (!all && strcmp(member, "Get") != 0) {
        [self replyError: DBUS_ERROR_UNKNOWN_METHOD to: call];
        return;
    }

    DBusMessageIter iter;
    const char *interface = "", *name = "";

    if (dbus_message_iter_init(call, &iter)) {
        dbus_message_iter_get_basic(&iter, &interface);
        if (!all && dbus_message_iter_next(&iter))
            dbus_message_iter_get_basic(&iter, &name);
    }
    if (strcmp(interface, ITEM_INTERFACE) != 0 && interface[0] != '\0') {
        [self replyError: DBUS_ERROR_UNKNOWN_INTERFACE to: call];
        return;
    }

    DBusMessage *reply = dbus_message_new_method_return(call);
    DBusMessageIter out, array;

    dbus_message_iter_init_append(reply, &out);
    if (!all) {
        if (![self appendProperty: name to: &out]) {
            dbus_message_unref(reply);
            [self replyError: DBUS_ERROR_INVALID_ARGS to: call];
            return;
        }
    } else {
        dbus_message_iter_open_container(&out, DBUS_TYPE_ARRAY, "{sv}", &array);
        for (size_t i = 0; i < PROPERTY_COUNT; i++) {
            DBusMessageIter entry;
            const char *key = propertyNames[i];

            dbus_message_iter_open_container(&array, DBUS_TYPE_DICT_ENTRY, NULL,
                                             &entry);
            dbus_message_iter_append_basic(&entry, DBUS_TYPE_STRING, &key);
            [self appendProperty: key to: &entry];
            dbus_message_iter_close_container(&array, &entry);
        }
        dbus_message_iter_close_container(&out, &array);
    }
    [_bus send: reply];
    dbus_message_unref(reply);
}

// Activate and SecondaryActivate are the primary and the secondary click.
// Clicks that the desktop answers by showing the menu (the item is a menu) do
// not come here.
- (void) handleClick: (BOOL) secondary {
    NSStatusItem *item = _item;

    if (item == nil || [item menu] != nil)
        return;
    [item _sendActionForClick: secondary];
}

- (void) handleItemCall: (DBusMessage *) call {
    const char *interface = dbus_message_get_interface(call);
    const char *member = dbus_message_get_member(call);

    if (interface != NULL && strcmp(interface, INTROSPECTABLE_INTERFACE) == 0) {
        DBusMessage *reply = dbus_message_new_method_return(call);

        NSDBusAppendArgument(reply, DBUS_TYPE_STRING, &introspectionXML);
        [_bus send: reply];
        dbus_message_unref(reply);
    } else if (interface != NULL && strcmp(interface, PROPERTIES_INTERFACE) == 0) {
        [self handleProperties: call];
    } else if (interface == NULL || strcmp(interface, ITEM_INTERFACE) == 0) {
        if (strcmp(member, "Activate") == 0)
            [self handleClick: NO];
        else if (strcmp(member, "SecondaryActivate") == 0)
            [self handleClick: YES];
        else if (strcmp(member, "ContextMenu") != 0 &&
                 strcmp(member, "Scroll") != 0) {
            [self replyError: DBUS_ERROR_UNKNOWN_METHOD to: call];
            return;
        }
        [self replyTo: call];
    } else {
        [self replyError: DBUS_ERROR_UNKNOWN_INTERFACE to: call];
    }
}

- (BOOL) dbusMenu: (NSDBusMenu *) menu handleMessage: (DBusMessage *) message {
    switch (dbus_message_get_type(message)) {
    case DBUS_MESSAGE_TYPE_METHOD_CALL: {
        const char *path = dbus_message_get_path(message);

        if (path == NULL || strcmp(path, ITEM_PATH) != 0)
            return NO;
        [self handleItemCall: message];
        return YES;
    }
    case DBUS_MESSAGE_TYPE_SIGNAL:
        if (dbus_message_is_signal(message, "org.freedesktop.DBus",
                                   "NameOwnerChanged"))
            return [self handleWatcherChange: message];
        return NO;
    default:
        return NO;
    }
}

@end
