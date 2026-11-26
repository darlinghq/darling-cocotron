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

// The portal's D-Bus interface is described by the xdg-desktop-portal
// documentation: org.freedesktop.portal.FileChooser (OpenFile, SaveFile) and
// org.freedesktop.portal.Request (Response).

#import "DarlingPortalFileChooser.h"
#import <CoreGraphics/DarlingFileURIList.h>
#import <AppKit/NSDBusMenu.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSBox.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSOpenPanel.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSWindow.h>
#import <CoreServices/CoreServices.h>
#include <dbus/dbus.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#define PORTAL_NAME "org.freedesktop.portal.Desktop"
#define PORTAL_PATH "/org/freedesktop/portal/desktop"
#define FILECHOOSER_INTERFACE "org.freedesktop.portal.FileChooser"
#define REQUEST_INTERFACE "org.freedesktop.portal.Request"
#define REQUEST_PATH_PREFIX "/org/freedesktop/portal/desktop/request/"
#define BUS_NAME "org.freedesktop.DBus"
#define CALL_TIMEOUT_MS 5000
// The most results taken from one response.
#define MAX_RESULT_URIS 4096

static NSString *const HostRoot = @"/Volumes/SystemRoot";

@interface NSObject (DarlingPortalUTType)
- (id) preferredFilenameExtension;
- (id) preferredMIMEType;
@end

@interface NSSavePanel (DarlingPortalPrivate)
- (NSString *) _nameWithAllowedExtension: (NSString *) name;
- (void) _setFilename: (NSString *) filename;
- (void) _setAcceptedPaths: (NSArray *) paths;
@end

#pragma mark - Preference

// DesktopFileChooser: the application's own value wins; otherwise the user's
// org.darlinghq.AppKit domain decides, so that it can be set for all
// applications. NO when unset. Read once per process.
BOOL DarlingPortalFileChooserEnabled(void) {
    static BOOL value;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        CFStringRef key = CFSTR("DesktopFileChooser");
        Boolean valid = false;
        Boolean flag = CFPreferencesGetAppBooleanValue(
                key, kCFPreferencesCurrentApplication, &valid);

        if (!valid)
            flag = CFPreferencesGetAppBooleanValue(
                    key, CFSTR("org.darlinghq.AppKit"), &valid);
        value = valid && flag;
    });
    return value;
}

#pragma mark - Panel to request

// What the panel is asked to do, read from the panel's state. Kept in a
// category so that the panel's own instance variables can be read.
@interface NSSavePanel (DarlingPortalRequest)
- (NSString *) _portalUnsupportedFeature;
- (NSDictionary *) _portalRequest;
- (NSString *) _portalNameWithRequiredExtension: (NSString *) name;
@end

static BOOL isOpenPanel(NSSavePanel *panel) {
    return [panel isKindOfClass: [NSOpenPanel class]];
}

// Adds the extension or MIME type of one allowed type to the lists.
static void addAllowedType(id type, NSMutableArray *extensions,
                           NSMutableArray *mimeTypes) {
    NSMutableArray *newExtensions = [NSMutableArray array];
    NSString *mime = nil;

    if ([type isKindOfClass: [NSString class]]) {
        NSString *string = type;
        if ([string hasPrefix: @"."])
            string = [string substringFromIndex: 1];
        if ([string length] == 0)
            return;
        // A name with a dot is a type identifier, anything else an extension.
        if ([string rangeOfString: @"."].location == NSNotFound) {
            [newExtensions addObject: string];
        } else {
            CFArrayRef tags = UTTypeCopyAllTagsWithClass(
                    (CFStringRef) string, kUTTagClassFilenameExtension);
            if (tags != NULL) {
                [newExtensions addObjectsFromArray: (NSArray *) tags];
                CFRelease(tags);
            }
            CFStringRef tag = UTTypeCopyPreferredTagWithClass(
                    (CFStringRef) string, kUTTagClassMIMEType);
            if (tag != NULL) {
                mime = [(NSString *) tag autorelease];
            }
        }
    } else {
        // A UTType of the UniformTypeIdentifiers framework.
        if ([type respondsToSelector: @selector(preferredFilenameExtension)]) {
            id extension = [type preferredFilenameExtension];
            if ([extension isKindOfClass: [NSString class]] &&
                [extension length] > 0)
                [newExtensions addObject: extension];
        }
        if ([type respondsToSelector: @selector(preferredMIMEType)]) {
            id value = [type preferredMIMEType];
            if ([value isKindOfClass: [NSString class]] && [value length] > 0)
                mime = value;
        }
    }

    for (NSString *extension in newExtensions) {
        if (![extensions containsObject: extension])
            [extensions addObject: extension];
    }
    if (mime != nil && ![mimeTypes containsObject: mime])
        [mimeTypes addObject: mime];
}

// A glob matching an extension whatever the case of its letters, since the
// portal's globs are case sensitive and file names are not by convention.
// Characters with a meaning in a glob are escaped.
static NSString *globForExtension(NSString *extension) {
    NSMutableString *glob = [NSMutableString stringWithString: @"*."];
    for (NSUInteger i = 0; i < [extension length]; i++) {
        unichar c = [extension characterAtIndex: i];
        NSString *character = [NSString stringWithCharacters: &c length: 1];
        NSString *lower = [character lowercaseString];
        NSString *upper = [character uppercaseString];

        if (c == '[' || c == ']' || c == '?' || c == '*' || c == '\\')
            [glob appendFormat: @"\\%@", character];
        else if ([lower length] == 1 && [upper length] == 1 &&
                 ![lower isEqualToString: upper])
            [glob appendFormat: @"[%@%@]", lower, upper];
        else
            [glob appendString: character];
    }
    return glob;
}

@implementation NSSavePanel (DarlingPortalRequest)

- (NSString *) _portalUnsupportedFeature {
    Class panelClass = isOpenPanel(self) ? [NSOpenPanel class]
                                         : [NSSavePanel class];
    // A subclass may override the presentation or the result.
    if ([self class] != panelClass)
        return @"a subclass of the panel class";
    if ([self accessoryView] != nil && DarlingPortalChoicesForAccessoryView([self accessoryView]) == nil)
        return @"an accessory view that is not made of pop-up buttons, check boxes and labels";
    if ([self showsHiddenFiles])
        return @"showsHiddenFiles";
    if ([self treatsFilePackagesAsDirectories])
        return @"treatsFilePackagesAsDirectories";

    id delegate = [self delegate];
    SEL filtering[] = {
        @selector(panel:shouldEnableURL:),
        @selector(panel:validateURL:error:),
        @selector(panel:shouldShowFilename:),
        @selector(panel:isValidFilename:),
        @selector(panel:userEnteredFilename:confirmed:),
        @selector(panel:compareFilename:with:caseSensitive:),
    };
    for (size_t i = 0; delegate != nil && i < sizeof(filtering) / sizeof(*filtering); i++) {
        if ([delegate respondsToSelector: filtering[i]])
            return @"a delegate that filters or validates";
    }

    if (isOpenPanel(self)) {
        NSOpenPanel *open = (NSOpenPanel *) self;
        if ([open canChooseFiles] == [open canChooseDirectories])
            return [open canChooseFiles]
                           ? @"choosing files and folders in one panel"
                           : @"an open panel that chooses nothing";
    }
    return nil;
}

// The save panel gives a name without an allowed extension the first one.
- (NSString *) _portalNameWithRequiredExtension: (NSString *) name {
    return [self _nameWithAllowedExtension: name];
}

- (NSDictionary *) _portalRequest {
    BOOL open = isOpenPanel(self);
    NSMutableDictionary *options = [NSMutableDictionary dictionary];

    NSString *title = [self message];
    if ([title length] == 0)
        title = _dialogTitle;
    if ([title length] == 0)
        title = open ? @"Open" : @"Save";

    if ([[self prompt] length] > 0)
        options[@"accept_label"] = [self prompt];
    options[@"modal"] = @YES;

    if (open) {
        NSOpenPanel *openPanel = (NSOpenPanel *) self;
        options[@"multiple"] = @([openPanel allowsMultipleSelection]);
        // The portal's directory option makes the dialog choose folders only.
        options[@"directory"] = @(![openPanel canChooseFiles]);
    }

    NSMutableArray *extensions = [NSMutableArray array];
    NSMutableArray *mimeTypes = [NSMutableArray array];
    for (id type in [self allowedContentTypes])
        addAllowedType(type, extensions, mimeTypes);
    if ([extensions count] == 0 && [mimeTypes count] == 0) {
        for (id type in [self allowedFileTypes])
            addAllowedType(type, extensions, mimeTypes);
    }
    if ([extensions count] == 0 && [mimeTypes count] == 0 && !open &&
        [_requiredFileType length] > 0)
        addAllowedType(_requiredFileType, extensions, mimeTypes);

    NSMutableArray *filters = [NSMutableArray array];
    if ([extensions count] > 0 || [mimeTypes count] > 0) {
        NSMutableArray *patterns = [NSMutableArray array];
        for (NSString *extension in extensions)
            [patterns addObject: @[ @0, globForExtension(extension) ]];
        for (NSString *mime in mimeTypes)
            [patterns addObject: @[ @1, mime ]];
        NSArray *filter = @[ @"Supported Files", patterns ];
        [filters addObject: filter];
        options[@"current_filter"] = filter;
        // A save panel may be told that other names are fine.
        if (!open && _allowsOtherFileTypes)
            [filters addObject: @[ @"All Files", @[ @[ @0, @"*" ] ] ]];
    }
    if ([filters count] > 0)
        options[@"filters"] = filters;

    NSString *directory = DarlingPortalHostPathForGuestPath([self directory]);
    if (directory != nil) {
        NSMutableData *bytes = [[[directory dataUsingEncoding: NSUTF8StringEncoding]
                mutableCopy] autorelease];
        [bytes appendBytes: "" length: 1];
        options[@"current_folder"] = bytes;
    }

    if ([self accessoryView] != nil) {
        NSMutableArray *choices = [NSMutableArray array];
        for (NSDictionary *choice in DarlingPortalChoicesForAccessoryView([self accessoryView]))
            [choices addObject: @[ choice[@"id"], choice[@"label"], choice[@"options"], choice[@"initial"] ]];
        if ([choices count] > 0)
            options[@"choices"] = choices;
    }

    if (!open) {
        NSString *name = [self nameFieldStringValue];
        if ([name length] == 0)
            name = [[self filename] lastPathComponent];
        if ([name length] > 0)
            options[@"current_name"] = name;
    }

    return @{
        @"method": open ? @"OpenFile" : @"SaveFile",
        @"title": title,
        @"options": options,
    };
}

@end

NSString *DarlingPortalUnsupportedFeature(NSSavePanel *panel) {
    return [panel _portalUnsupportedFeature];
}

NSDictionary *DarlingPortalRequestForPanel(NSSavePanel *panel) {
    return [panel _portalRequest];
}

#pragma mark - Accessory view as choices

// The portal has no place for a view of the application's own. What it can show are "choices": combo boxes
// (a label, a list of options, the initial option) and, as a special case with no options, check boxes. An
// accessory view made only of pop-up buttons and check boxes, with static labels and plain container views around
// them, is shown that way, and the user's answers are put back into the controls. This is a decision of Darling's
// desktop integration, not something macOS does: the built-in panel shows any accessory view that the portal
// cannot express (see DarlingPortalUnsupportedFeature).

static BOOL isCheckBox(NSButton *button) {
    NSButtonCell *cell = [button cell];
    return ![button isKindOfClass: [NSPopUpButton class]] && [cell isKindOfClass: [NSButtonCell class]] &&
           [cell highlightsBy] == NSContentsCellMask && [cell showsStateBy] == NSContentsCellMask &&
           [[[cell image] name] isEqualToString: @"NSSwitch"];
}

// A pop-up button the portal can show: a list of items, one chosen, with usable titles.
static BOOL isSupportedPopUp(NSPopUpButton *popUp) {
    if ([popUp pullsDown] || ![popUp isEnabled])
        return NO;
    for (NSMenuItem *item in [popUp itemArray]) {
        if (![item isSeparatorItem] && [item isEnabled] && [[item title] length] > 0)
            return YES;
    }
    return NO;
}

// Collects the controls and static labels below a view, in the coordinates of the root view; NO when there is
// anything else. Hidden views are not shown and are left out.
static BOOL collectAccessoryControls(NSView *root, NSView *view, NSMutableArray *controls, NSMutableArray *labels) {
    for (NSView *subview in [view subviews]) {
        if ([subview isHidden])
            continue;
        NSRect frame = [root convertRect: [subview bounds] fromView: subview];
        NSDictionary *entry = @{ @"view": subview, @"frame": [NSValue valueWithRect: frame] };
        if ([subview isKindOfClass: [NSPopUpButton class]]) {
            if (!isSupportedPopUp((NSPopUpButton *) subview))
                return NO;
            [controls addObject: entry];
        } else if ([subview isKindOfClass: [NSButton class]]) {
            NSButton *button = (NSButton *) subview;
            if (!isCheckBox(button) || ![button isEnabled] || [[button title] length] == 0 ||
                [button state] == NSMixedState)
                return NO;
            [controls addObject: entry];
        } else if ([subview isKindOfClass: [NSTextField class]]) {
            if ([(NSTextField *) subview isEditable])
                return NO;
            [labels addObject: entry];
        } else if ([subview isMemberOfClass: [NSView class]] || [subview isKindOfClass: [NSBox class]]) {
            if (!collectAccessoryControls(root, subview, controls, labels))
                return NO;
        } else {
            return NO;
        }
    }
    return YES;
}

// A label's text as the portal's label: without the colon that a label before a control ends with.
static NSString *labelText(NSTextField *field) {
    NSString *text = [[field stringValue] stringByTrimmingCharactersInSet:
                                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text hasSuffix: @":"])
        text = [text substringToIndex: [text length] - 1];
    return text;
}

// The label of a pop-up button: the nearest static label on its left in the same row, else the nearest above it.
static NSString *labelForControl(NSRect frame, NSArray *labels, BOOL flipped) {
    NSString *best = nil;
    CGFloat bestDistance = 0;
    for (NSDictionary *entry in labels) {
        NSRect label = [entry[@"frame"] rectValue];
        NSString *text = labelText(entry[@"view"]);
        if ([text length] == 0)
            continue;
        BOOL sameRow = NSMidY(label) >= NSMinY(frame) && NSMidY(label) <= NSMaxY(frame);
        if (sameRow && NSMaxX(label) <= NSMinX(frame) + 4) {
            CGFloat distance = NSMinX(frame) - NSMaxX(label);
            if (best == nil || distance < bestDistance) {
                best = text;
                bestDistance = distance;
            }
        }
    }
    if (best != nil)
        return best;
    for (NSDictionary *entry in labels) {
        NSRect label = [entry[@"frame"] rectValue];
        NSString *text = labelText(entry[@"view"]);
        if ([text length] == 0 || NSMaxX(label) <= NSMinX(frame) || NSMinX(label) >= NSMaxX(frame))
            continue;
        // above: later y in a flipped view, earlier in an unflipped one
        CGFloat distance = flipped ? NSMinY(frame) - NSMaxY(label) : NSMinY(label) - NSMaxY(frame);
        if (distance >= -2 && (best == nil || distance < bestDistance)) {
            best = text;
            bestDistance = distance;
        }
    }
    return best;
}

NSArray *DarlingPortalChoicesForAccessoryView(NSView *view) {
    if (view == nil)
        return nil;
    NSMutableArray *controls = [NSMutableArray array];
    NSMutableArray *labels = [NSMutableArray array];
    if (!collectAccessoryControls(view, view, controls, labels) || [controls count] == 0)
        return nil;

    // top to bottom, then left to right
    BOOL flipped = [view isFlipped];
    [controls sortUsingComparator: ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSRect fa = [a[@"frame"] rectValue], fb = [b[@"frame"] rectValue];
        CGFloat ya = flipped ? NSMinY(fa) : -NSMaxY(fa), yb = flipped ? NSMinY(fb) : -NSMaxY(fb);
        if (fabs(ya - yb) > 2)
            return ya < yb ? NSOrderedAscending : NSOrderedDescending;
        return NSMinX(fa) < NSMinX(fb) ? NSOrderedAscending
               : NSMinX(fa) > NSMinX(fb) ? NSOrderedDescending : NSOrderedSame;
    }];

    NSMutableArray *choices = [NSMutableArray array];
    for (NSDictionary *entry in controls) {
        id control = entry[@"view"];
        NSString *identifier = [NSString stringWithFormat: @"c%lu", (unsigned long) [choices count]];
        if ([control isKindOfClass: [NSPopUpButton class]]) {
            NSPopUpButton *popUp = control;
            NSMutableArray *options = [NSMutableArray array];
            NSMutableArray *indexes = [NSMutableArray array];
            NSString *initial = @"";
            NSInteger selected = [popUp indexOfSelectedItem];
            for (NSInteger i = 0; i < [popUp numberOfItems]; i++) {
                NSMenuItem *item = [popUp itemAtIndex: i];
                if ([item isSeparatorItem] || ![item isEnabled] || [[item title] length] == 0)
                    continue;
                NSString *optionIdentifier = [NSString stringWithFormat: @"%ld", (long) i];
                [options addObject: @[ optionIdentifier, [item title] ]];
                [indexes addObject: @(i)];
                if (i == selected)
                    initial = optionIdentifier;
            }
            NSString *label = labelForControl([entry[@"frame"] rectValue], labels, flipped);
            [choices addObject: @{
                @"id": identifier, @"label": [label length] > 0 ? label : [popUp titleOfSelectedItem],
                @"options": options, @"initial": initial, @"control": popUp, @"itemIndexes": indexes,
            }];
        } else {
            NSButton *button = control;
            [choices addObject: @{
                @"id": identifier, @"label": [button title], @"options": @[],
                @"initial": [button state] == NSOnState ? @"true" : @"false", @"control": button,
            }];
        }
    }
    return choices;
}

// Puts the portal's answers into the controls. A control whose value changed also sends its action, once, since the
// application would have had it sent while the user changed the value; unknown ids and values are ignored.
static void applyChoices(NSArray *choices, NSDictionary *answers) {
    for (NSDictionary *choice in choices) {
        NSString *answer = answers[choice[@"id"]];
        if (![answer isKindOfClass: [NSString class]])
            continue;
        NSControl *control = choice[@"control"];
        BOOL changed = NO;
        if ([control isKindOfClass: [NSPopUpButton class]]) {
            NSPopUpButton *popUp = (NSPopUpButton *) control;
            NSInteger index = [answer integerValue];
            if (![[answer stringByTrimmingCharactersInSet: [NSCharacterSet decimalDigitCharacterSet]] isEqualToString: @""] ||
                ![choice[@"itemIndexes"] containsObject: @(index)] || index >= [popUp numberOfItems])
                continue;
            changed = index != [popUp indexOfSelectedItem];
            [popUp selectItemAtIndex: index];
        } else {
            NSInteger state;
            if ([answer isEqualToString: @"true"])
                state = NSOnState;
            else if ([answer isEqualToString: @"false"])
                state = NSOffState;
            else
                continue;
            changed = state != [(NSButton *) control state];
            [(NSButton *) control setState: state];
        }
        if (changed && [control action] != NULL)
            [NSApp sendAction: [control action] to: [control target] from: control];
    }
}

#pragma mark - Paths

NSString *DarlingPortalHostPathForGuestPath(NSString *path) {
    NSString *boundary = [HostRoot stringByAppendingString: @"/"];
    if (![path hasPrefix: boundary])
        return nil;
    NSString *host = [path substringFromIndex: [HostRoot length]];
    if ([host length] > 1 && [host hasSuffix: @"/"])
        host = [host substringToIndex: [host length] - 1];
    if ([host rangeOfString: @"\0"].location != NSNotFound ||
        [[host componentsSeparatedByString: @"/"] containsObject: @".."])
        return nil;
    return host;
}

NSArray *DarlingPortalPathsFromURIs(NSArray *uris) {
    if (![uris isKindOfClass: [NSArray class]] || [uris count] == 0 ||
        [uris count] > MAX_RESULT_URIS)
        return nil;
    NSMutableArray *paths = [NSMutableArray arrayWithCapacity: [uris count]];
    NSCharacterSet *breaks =
            [NSCharacterSet characterSetWithCharactersInString: @"\r\n"];
    for (id uri in uris) {
        // Each entry is converted on its own: a line break inside one would
        // otherwise read as several entries, and a leading "#" as a comment.
        if (![uri isKindOfClass: [NSString class]] || [uri hasPrefix: @"#"] ||
            [uri rangeOfCharacterFromSet: breaks].location != NSNotFound)
            return nil;
        NSArray *one = DarlingFilenamesFromURIList(
                [uri dataUsingEncoding: NSUTF8StringEncoding]);
        if ([one count] != 1)
            return nil;
        [paths addObject: one[0]];
    }
    return paths;
}

NSInteger DarlingPortalModalResponseForCode(uint32_t code) {
    return code == 0 ? NSOKButton : NSCancelButton;
}

#pragma mark - Message helpers

// dbus_message_append_args() is variadic and not usable through the wrapper
// library, so everything is built with iterators.
static BOOL appendBasic(DBusMessageIter *iterator, int type, const void *value) {
    return dbus_message_iter_append_basic(iterator, type, value) ? YES : NO;
}

static BOOL appendString(DBusMessageIter *iterator, NSString *string) {
    const char *utf8 = [string UTF8String];
    if (utf8 == NULL)
        utf8 = "";
    return appendBasic(iterator, DBUS_TYPE_STRING, &utf8);
}

// Opens the key and variant of an a{sv} entry; the caller appends the value
// to *variant and closes both.
static BOOL openEntry(DBusMessageIter *array, DBusMessageIter *entry,
                      DBusMessageIter *variant, const char *key,
                      const char *signature)
{
    if (!dbus_message_iter_open_container(array, DBUS_TYPE_DICT_ENTRY, NULL, entry))
        return NO;
    if (!appendBasic(entry, DBUS_TYPE_STRING, &key) ||
        !dbus_message_iter_open_container(entry, DBUS_TYPE_VARIANT, signature, variant)) {
        dbus_message_iter_abandon_container(array, entry);
        return NO;
    }
    return YES;
}

static void closeEntry(DBusMessageIter *array, DBusMessageIter *entry,
                       DBusMessageIter *variant)
{
    dbus_message_iter_close_container(entry, variant);
    dbus_message_iter_close_container(array, entry);
}

static BOOL appendStringEntry(DBusMessageIter *array, const char *key, NSString *value) {
    DBusMessageIter entry, variant;
    if (!openEntry(array, &entry, &variant, key, "s"))
        return NO;
    BOOL ok = appendString(&variant, value);
    closeEntry(array, &entry, &variant);
    return ok;
}

static BOOL appendBooleanEntry(DBusMessageIter *array, const char *key, BOOL value) {
    DBusMessageIter entry, variant;
    if (!openEntry(array, &entry, &variant, key, "b"))
        return NO;
    dbus_bool_t flag = value ? TRUE : FALSE;
    BOOL ok = appendBasic(&variant, DBUS_TYPE_BOOLEAN, &flag);
    closeEntry(array, &entry, &variant);
    return ok;
}

static BOOL appendBytesEntry(DBusMessageIter *array, const char *key, NSData *value) {
    DBusMessageIter entry, variant, bytes;
    if (!openEntry(array, &entry, &variant, key, "ay"))
        return NO;
    const unsigned char *data = [value bytes];
    BOOL ok = dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "y", &bytes);
    if (ok) {
        ok = dbus_message_iter_append_fixed_array(&bytes, DBUS_TYPE_BYTE, &data,
                                                  (int) [value length]) ? YES : NO;
        dbus_message_iter_close_container(&variant, &bytes);
    }
    closeEntry(array, &entry, &variant);
    return ok;
}

// A filter is the structure (sa(us)).
static BOOL appendFilter(DBusMessageIter *parent, NSArray *filter) {
    DBusMessageIter structure, patterns;
    if (!dbus_message_iter_open_container(parent, DBUS_TYPE_STRUCT, NULL, &structure))
        return NO;
    BOOL ok = appendString(&structure, filter[0]);
    ok = ok && dbus_message_iter_open_container(&structure, DBUS_TYPE_ARRAY, "(us)", &patterns);
    if (ok) {
        for (NSArray *pattern in filter[1]) {
            DBusMessageIter item;
            if (!dbus_message_iter_open_container(&patterns, DBUS_TYPE_STRUCT, NULL, &item)) {
                ok = NO;
                break;
            }
            dbus_uint32_t kind = (dbus_uint32_t) [pattern[0] unsignedIntValue];
            ok = appendBasic(&item, DBUS_TYPE_UINT32, &kind) &&
                 appendString(&item, pattern[1]);
            dbus_message_iter_close_container(&patterns, &item);
            if (!ok)
                break;
        }
        dbus_message_iter_close_container(&structure, &patterns);
    }
    dbus_message_iter_close_container(parent, &structure);
    return ok;
}

static BOOL appendFiltersEntry(DBusMessageIter *array, NSArray *filters) {
    DBusMessageIter entry, variant, list;
    if (!openEntry(array, &entry, &variant, "filters", "a(sa(us))"))
        return NO;
    BOOL ok = dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "(sa(us))", &list);
    if (ok) {
        for (NSArray *filter in filters) {
            if (!(ok = appendFilter(&list, filter)))
                break;
        }
        dbus_message_iter_close_container(&variant, &list);
    }
    closeEntry(array, &entry, &variant);
    return ok;
}

static BOOL appendCurrentFilterEntry(DBusMessageIter *array, NSArray *filter) {
    DBusMessageIter entry, variant;
    if (!openEntry(array, &entry, &variant, "current_filter", "(sa(us))"))
        return NO;
    BOOL ok = appendFilter(&variant, filter);
    closeEntry(array, &entry, &variant);
    return ok;
}

// The choices are the array a(ssa(ss)s).
static BOOL appendChoicesEntry(DBusMessageIter *array, NSArray *choices) {
    DBusMessageIter entry, variant, list;
    if (!openEntry(array, &entry, &variant, "choices", "a(ssa(ss)s)"))
        return NO;
    BOOL ok = dbus_message_iter_open_container(&variant, DBUS_TYPE_ARRAY, "(ssa(ss)s)", &list);
    if (ok) {
        for (NSArray *choice in choices) {
            DBusMessageIter structure, options;
            ok = dbus_message_iter_open_container(&list, DBUS_TYPE_STRUCT, NULL, &structure) &&
                 appendString(&structure, choice[0]) && appendString(&structure, choice[1]) &&
                 dbus_message_iter_open_container(&structure, DBUS_TYPE_ARRAY, "(ss)", &options);
            if (!ok)
                break;
            for (NSArray *option in choice[2]) {
                DBusMessageIter pair;
                if (!dbus_message_iter_open_container(&options, DBUS_TYPE_STRUCT, NULL, &pair)) {
                    ok = NO;
                    break;
                }
                ok = appendString(&pair, option[0]) && appendString(&pair, option[1]);
                dbus_message_iter_close_container(&options, &pair);
                if (!ok)
                    break;
            }
            dbus_message_iter_close_container(&structure, &options);
            ok = ok && appendString(&structure, choice[3]);
            dbus_message_iter_close_container(&list, &structure);
            if (!ok)
                break;
        }
        dbus_message_iter_close_container(&variant, &list);
    }
    closeEntry(array, &entry, &variant);
    return ok;
}

// The options of a request as the a{sv} argument, with the handle token.
static BOOL appendOptions(DBusMessage *message, NSDictionary *request, NSString *token) {
    DBusMessageIter iterator, array;
    dbus_message_iter_init_append(message, &iterator);
    NSString *parent = request[@"parent_window"];
    if (!appendString(&iterator, parent != nil ? parent : @"") ||
        !appendString(&iterator, request[@"title"]))
        return NO;
    if (!dbus_message_iter_open_container(&iterator, DBUS_TYPE_ARRAY, "{sv}", &array))
        return NO;

    NSDictionary *values = request[@"options"];
    BOOL ok = appendStringEntry(&array, "handle_token", token);
    for (NSString *key in @[ @"accept_label", @"current_name" ]) {
        if (ok && values[key] != nil)
            ok = appendStringEntry(&array, [key UTF8String], values[key]);
    }
    for (NSString *key in @[ @"modal", @"multiple", @"directory" ]) {
        if (ok && values[key] != nil)
            ok = appendBooleanEntry(&array, [key UTF8String], [values[key] boolValue]);
    }
    if (ok && values[@"filters"] != nil)
        ok = appendFiltersEntry(&array, values[@"filters"]);
    if (ok && values[@"current_filter"] != nil)
        ok = appendCurrentFilterEntry(&array, values[@"current_filter"]);
    if (ok && values[@"choices"] != nil)
        ok = appendChoicesEntry(&array, values[@"choices"]);
    if (ok && values[@"current_folder"] != nil)
        ok = appendBytesEntry(&array, "current_folder", values[@"current_folder"]);
    dbus_message_iter_close_container(&iterator, &array);
    return ok;
}

// The uris of a Response signal and its code, or NO when it is not a well
// formed Response.
static BOOL parseResponse(DBusMessage *message, uint32_t *code, NSArray **uris, NSDictionary **choices) {
    DBusMessageIter iterator, array;
    dbus_uint32_t response = 2;

    if (!dbus_message_iter_init(message, &iterator) ||
        dbus_message_iter_get_arg_type(&iterator) != DBUS_TYPE_UINT32)
        return NO;
    dbus_message_iter_get_basic(&iterator, &response);
    *code = response;
    *uris = nil;
    *choices = nil;
    if (!dbus_message_iter_next(&iterator) ||
        dbus_message_iter_get_arg_type(&iterator) != DBUS_TYPE_ARRAY)
        return YES;

    dbus_message_iter_recurse(&iterator, &array);
    while (dbus_message_iter_get_arg_type(&array) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter entry, variant, list;
        const char *key = NULL;

        dbus_message_iter_recurse(&array, &entry);
        if (dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_STRING) {
            dbus_message_iter_get_basic(&entry, &key);
            if (key != NULL && strcmp(key, "uris") == 0 &&
                dbus_message_iter_next(&entry) &&
                dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_VARIANT) {
                dbus_message_iter_recurse(&entry, &variant);
                if (dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_ARRAY &&
                    dbus_message_iter_get_element_type(&variant) == DBUS_TYPE_STRING) {
                    NSMutableArray *result = [NSMutableArray array];
                    dbus_message_iter_recurse(&variant, &list);
                    while (dbus_message_iter_get_arg_type(&list) == DBUS_TYPE_STRING &&
                           [result count] <= MAX_RESULT_URIS) {
                        const char *uri = NULL;
                        dbus_message_iter_get_basic(&list, &uri);
                        NSString *string = uri != NULL ? [NSString stringWithUTF8String: uri] : nil;
                        if (string == nil) {
                            // An undecodable entry spoils the whole list.
                            *uris = @[];
                            return YES;
                        }
                        [result addObject: string];
                        dbus_message_iter_next(&list);
                    }
                    *uris = result;
                }
            } else if (key != NULL && strcmp(key, "choices") == 0 &&
                       dbus_message_iter_next(&entry) &&
                       dbus_message_iter_get_arg_type(&entry) == DBUS_TYPE_VARIANT) {
                // a(ss): the id of each choice that was passed in and the option the user ended with
                dbus_message_iter_recurse(&entry, &variant);
                if (dbus_message_iter_get_arg_type(&variant) == DBUS_TYPE_ARRAY &&
                    dbus_message_iter_get_element_type(&variant) == DBUS_TYPE_STRUCT) {
                    NSMutableDictionary *result = [NSMutableDictionary dictionary];
                    dbus_message_iter_recurse(&variant, &list);
                    while (dbus_message_iter_get_arg_type(&list) == DBUS_TYPE_STRUCT &&
                           [result count] < MAX_RESULT_URIS) {
                        DBusMessageIter pair;
                        const char *choice = NULL, *selected = NULL;
                        dbus_message_iter_recurse(&list, &pair);
                        if (dbus_message_iter_get_arg_type(&pair) == DBUS_TYPE_STRING) {
                            dbus_message_iter_get_basic(&pair, &choice);
                            if (dbus_message_iter_next(&pair) &&
                                dbus_message_iter_get_arg_type(&pair) == DBUS_TYPE_STRING)
                                dbus_message_iter_get_basic(&pair, &selected);
                        }
                        NSString *name = choice != NULL ? [NSString stringWithUTF8String: choice] : nil;
                        NSString *value = selected != NULL ? [NSString stringWithUTF8String: selected] : nil;
                        if (name != nil && value != nil)
                            result[name] = value;
                        dbus_message_iter_next(&list);
                    }
                    *choices = result;
                }
            }
        }
        dbus_message_iter_next(&array);
    }
    return YES;
}

// Whether a NameOwnerChanged signal says that the portal's name has left
// the given owner.
static BOOL ownerLeft(DBusMessage *message, NSString *owner) {
    const char *name = NULL, *oldOwner = NULL, *newOwner = NULL;
    DBusMessageIter iterator;

    if (!dbus_message_iter_init(message, &iterator))
        return NO;
    const char **fields[] = { &name, &oldOwner, &newOwner };
    for (int i = 0; i < 3; i++) {
        if (dbus_message_iter_get_arg_type(&iterator) != DBUS_TYPE_STRING)
            return NO;
        dbus_message_iter_get_basic(&iterator, fields[i]);
        if (i < 2 && !dbus_message_iter_next(&iterator))
            return NO;
    }
    return strcmp(name, PORTAL_NAME) == 0 &&
           strcmp(oldOwner, [owner UTF8String]) == 0 &&
           strcmp(newOwner, oldOwner) != 0;
}

#pragma mark - Request

// One FileChooser call and the wait for its Response signal. All of it runs
// on the main thread's run loop.
@interface DarlingPortalRequest : NSObject {
    DBusConnection *_connection;
    CFSocketRef _socket;
    CFRunLoopSourceRef _source;
    NSSavePanel *_panel;
    NSString *_requestPath;
    // The unique name of the portal that answered the call; only its signals
    // are believed.
    NSString *_portalOwner;
    void (^_handler)(NSModalResponse);
    // The accessory view's controls that were sent as choices, see DarlingPortalChoicesForAccessoryView.
    NSArray *_choices;
    BOOL _finished;
    NSModalResponse _response;
}
- (instancetype) initWithPanel: (NSSavePanel *) panel
                        parent: (NSWindow *) parent
                       handler: (void (^)(NSModalResponse)) handler;
- (BOOL) isFinished;
- (NSModalResponse) response;
- (void) readyToRead;
- (void) processMessages;
- (void) invalidate;
@end

static NSMutableSet *activeRequests(void) {
    static NSMutableSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSMutableSet new];
    });
    return set;
}

static void requestSocketCallback(CFSocketRef s, CFSocketCallBackType type,
                                  CFDataRef address, const void *data, void *info)
{
    [(DarlingPortalRequest *) info readyToRead];
}

@implementation DarlingPortalRequest

// The portal, or NULL: the connection is private, so that the application's
// own use of D-Bus is not affected, and the portal must be on the bus or
// activatable.
static DBusConnection *connectToPortal(void) {
    NSString *address = DarlingSessionBusAddress();
    DBusError error;
    dbus_error_init(&error);

    DBusConnection *connection =
            address != nil ? dbus_connection_open_private([address UTF8String], &error)
                           : NULL;
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
    dbus_error_free(&error);
    return connection;
}

static unsigned long long requestCounter;

- (instancetype) initWithPanel: (NSSavePanel *) panel
                        parent: (NSWindow *) parent
                       handler: (void (^)(NSModalResponse)) handler
{
    if ((self = [super init]) == nil)
        return nil;

    _connection = connectToPortal();
    if (_connection == NULL) {
        [self release];
        return nil;
    }

    NSMutableDictionary *request =
            [NSMutableDictionary dictionaryWithDictionary: [panel _portalRequest]];
    NSString *handle = parent != nil
            ? [[NSDisplay currentDisplay] portalParentHandleForWindow: parent]
            : nil;
    if (handle != nil)
        request[@"parent_window"] = handle;

    // The reply names the Request object, and its Response can come before the
    // reply, so the object's path is worked out from the token and listened to
    // first: the unique name without its colon and with underscores for dots.
    // The token only has to be unique among this connection's requests (the
    // connection is new for each request); it is not a secret, since anyone
    // on the bus can see the request path. Trust comes from the sender check
    // in -processMessages.
    NSString *token = [NSString stringWithFormat: @"darling_%d_%llu", (int) getpid(),
                                                   ++requestCounter];
    const char *uniqueName = dbus_bus_get_unique_name(_connection);
    if (uniqueName == NULL || uniqueName[0] != ':') {
        [self release];
        return nil;
    }
    NSString *sender = [[NSString stringWithUTF8String: uniqueName + 1]
            stringByReplacingOccurrencesOfString: @"." withString: @"_"];
    _requestPath = [[NSString stringWithFormat: @REQUEST_PATH_PREFIX "%@/%@", sender, token]
            retain];

    NSString *rule = [NSString
            stringWithFormat: @"type='signal',interface='" REQUEST_INTERFACE
                               "',member='Response',path='%@'", _requestPath];
    dbus_bus_add_match(_connection, [rule UTF8String], NULL);
    // The portal leaving the bus ends the request: its Response cannot come.
    dbus_bus_add_match(_connection,
                       "type='signal',sender='" BUS_NAME "',interface='" BUS_NAME
                       "',member='NameOwnerChanged',arg0='" PORTAL_NAME "'",
                       NULL);

    DBusMessage *call = dbus_message_new_method_call(
            PORTAL_NAME, PORTAL_PATH, FILECHOOSER_INTERFACE,
            [request[@"method"] UTF8String]);
    if (call == NULL || !appendOptions(call, request, token)) {
        if (call != NULL)
            dbus_message_unref(call);
        [self release];
        return nil;
    }

    DBusError error;
    dbus_error_init(&error);
    DBusMessage *reply = dbus_connection_send_with_reply_and_block(
            _connection, call, CALL_TIMEOUT_MS, &error);
    dbus_message_unref(call);
    BOOL ok = reply != NULL &&
              dbus_message_get_type(reply) == DBUS_MESSAGE_TYPE_METHOD_RETURN &&
              dbus_message_get_sender(reply) != NULL;
    if (ok) {
        // The bus fills in the sender, so this is the portal's unique name.
        _portalOwner = [[NSString alloc] initWithUTF8String: dbus_message_get_sender(reply)];
        DBusMessageIter iterator;
        const char *path = NULL;
        if (dbus_message_iter_init(reply, &iterator) &&
            dbus_message_iter_get_arg_type(&iterator) == DBUS_TYPE_OBJECT_PATH) {
            dbus_message_iter_get_basic(&iterator, &path);
            // An old portal ignores the token; listen to the path it chose.
            if (path != NULL && ![_requestPath isEqualToString: [NSString stringWithUTF8String: path]]) {
                [_requestPath release];
                _requestPath = [[NSString stringWithUTF8String: path] retain];
                rule = [NSString
                        stringWithFormat: @"type='signal',interface='" REQUEST_INTERFACE
                                           "',member='Response',path='%@'", _requestPath];
                dbus_bus_add_match(_connection, [rule UTF8String], NULL);
            }
        }
    }
    if (reply != NULL)
        dbus_message_unref(reply);
    dbus_error_free(&error);
    if (!ok) {
        [self release];
        return nil;
    }

    int descriptor = -1;
    if (!dbus_connection_get_unix_fd(_connection, &descriptor)) {
        [self release];
        return nil;
    }

    _panel = [panel retain];
    _choices = [DarlingPortalChoicesForAccessoryView([panel accessoryView]) retain];
    _handler = [handler copy];
    CFSocketContext context = {.version = 0, .info = self};
    _socket = CFSocketCreateWithNative(kCFAllocatorDefault, descriptor,
                                       kCFSocketReadCallBack, requestSocketCallback,
                                       &context);
    // The descriptor stays the connection's.
    CFSocketSetSocketFlags(_socket, CFSocketGetSocketFlags(_socket) &
                                            ~kCFSocketCloseOnInvalidate);
    _source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    [activeRequests() addObject: self];
    // The Response may be in the buffer already.
    [self processMessages];
    return self;
}

- (void) dealloc {
    [self invalidate];
    [_panel release];
    [_choices release];
    [_requestPath release];
    [_portalOwner release];
    [_handler release];
    [super dealloc];
}

- (void) invalidate {
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
}

- (BOOL) isFinished {
    return _finished;
}

- (NSModalResponse) response {
    return _response;
}

- (NSSavePanel *) panel {
    return _panel;
}

// Takes the dialog's outcome: a successful response sets the panel's result.
- (void) finishWithCode: (uint32_t) code uris: (NSArray *) uris choices: (NSDictionary *) answers {
    NSModalResponse response = DarlingPortalModalResponseForCode(code);
    if (response == NSOKButton) {
        NSArray *paths = DarlingPortalPathsFromURIs(uris);
        // One result unless several were asked for; anything else is not a
        // well formed answer to this request.
        BOOL several = isOpenPanel(_panel) &&
                       [(NSOpenPanel *) _panel allowsMultipleSelection];
        if (paths == nil || ([paths count] > 1 && !several)) {
            response = NSCancelButton;
        } else {
            // The controls get the user's answers first: their actions may change what the panel accepts,
            // such as the allowed file types that name the extension below.
            applyChoices(_choices, answers);
            if (isOpenPanel(_panel)) {
                [_panel _setAcceptedPaths: paths];
            } else {
                NSString *path = paths[0];
                // The portal returns the name as typed; the panel adds the first
                // allowed extension, like its own.
                [_panel _setFilename: [[path stringByDeletingLastPathComponent]
                                              stringByAppendingPathComponent:
                                                      [_panel _portalNameWithRequiredExtension:
                                                                      [path lastPathComponent]]]];
            }
        }
    }
    _response = response;
    _finished = YES;
    [self invalidate];

    void (^handler)(NSModalResponse) = _handler;
    _handler = nil;
    [self retain];
    [activeRequests() removeObject: self];
    if (handler != nil) {
        handler(response);
        [handler release];
    }
    [self release];
}

- (void) readyToRead {
    if (_connection == NULL)
        return;
    dbus_connection_read_write(_connection, 0);
    [self processMessages];
}

- (void) processMessages {
    for (;;) {
        if (_connection == NULL || _finished)
            return;
        DBusMessage *message = dbus_connection_pop_message(_connection);
        if (message == NULL)
            break;
        uint32_t code = 2;
        NSArray *uris = nil;
        NSDictionary *answers = nil;
        const char *path = dbus_message_get_path(message);
        const char *sender = dbus_message_get_sender(message);
        BOOL fromPortal = sender != NULL && strcmp(sender, [_portalOwner UTF8String]) == 0;
        BOOL isResponse = fromPortal &&
                          dbus_message_is_signal(message, REQUEST_INTERFACE, "Response") &&
                          path != NULL && strcmp(path, [_requestPath UTF8String]) == 0;
        BOOL parsed = isResponse && parseResponse(message, &code, &uris, &answers);
        BOOL portalGone = sender != NULL && strcmp(sender, BUS_NAME) == 0 &&
                          dbus_message_is_signal(message, BUS_NAME, "NameOwnerChanged") &&
                          ownerLeft(message, _portalOwner);
        dbus_message_unref(message);
        if (parsed) {
            [self finishWithCode: code uris: uris choices: answers];
            return;
        }
        if (portalGone) {
            [self finishWithCode: 2 uris: nil choices: nil];
            return;
        }
    }

    // The bus went away: the dialog's result can no longer arrive.
    if (_connection != NULL && !dbus_connection_get_is_connected(_connection))
        [self finishWithCode: 2 uris: nil choices: nil];
}

@end

#pragma mark - Entry points

// The portal is used from the main thread only, which is where the display
// and the run loop sources are.
static BOOL portalUsable(NSSavePanel *panel) {
    return DarlingPortalFileChooserEnabled() && pthread_main_np() &&
           [DarlingPortalUnsupportedFeature(panel) length] == 0;
}

BOOL DarlingPortalBegin(NSSavePanel *panel, NSWindow *parent,
                        void (^handler)(NSModalResponse response))
{
    if (!portalUsable(panel))
        return NO;
    DarlingPortalRequest *request =
            [[DarlingPortalRequest alloc] initWithPanel: panel
                                                 parent: parent
                                                handler: handler];
    [request autorelease];
    return request != nil;
}

BOOL DarlingPortalRunModal(NSSavePanel *panel, NSModalResponse *response) {
    if (!portalUsable(panel))
        return NO;
    DarlingPortalRequest *request =
            [[[DarlingPortalRequest alloc] initWithPanel: panel
                                                  parent: [NSApp keyWindow]
                                                 handler: nil] autorelease];
    if (request == nil)
        return NO;
    while (![request isFinished])
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                 beforeDate: [NSDate distantFuture]];
    *response = [request response];
    return YES;
}
