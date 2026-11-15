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

// The classes of the frameworks that -[NSPasteboard writeObjects:] and
// -[NSPasteboard readObjectsForClasses:options:] work with: NSString, NSURL, NSAttributedString,
// NSColor and NSImage adopt NSPasteboardWriting and NSPasteboardReading (the last two in their own files).

#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSPasteboard.h>
#import "NSPasteboardAliases.h"

static NSString *const NSPasteboardTypeUTF16ExternalPlainText = @"public.utf16-external-plain-text";

// The types of text on a pasteboard that are plain text, as read by -[NSString
// initWithPasteboardPropertyList:ofType:].
static NSArray *plainTextTypes(void) {
    return [NSArray arrayWithObjects: NSPasteboardTypeString, NSPasteboardTypeUTF16ExternalPlainText,
                                      @"public.plain-text", nil];
}

static BOOL typeIsPlainText(NSPasteboardType type) {
    return NSPasteboardTypeConformsTo(type, @"public.plain-text");
}

@implementation NSString (NSPasteboardSupport)

- (NSArray<NSPasteboardType> *) writableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return [NSArray arrayWithObject: NSPasteboardTypeString];
}

- (id) pasteboardPropertyListForType: (NSPasteboardType) type {
    return NSPasteboardTypeConformsTo(type, NSPasteboardTypeString) ? [[self copy] autorelease] : nil;
}

+ (NSArray<NSPasteboardType> *) readableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return plainTextTypes();
}

+ (NSPasteboardReadingOptions) readingOptionsForType: (NSPasteboardType) type pasteboard: (NSPasteboard *) pasteboard {
    return NSPasteboardReadingAsString;
}

- (id) initWithPasteboardPropertyList: (id) propertyList ofType: (NSPasteboardType) type {
    if (![propertyList isKindOfClass: [NSString class]]) {
        [self release];
        return nil;
    }
    return [self initWithString: propertyList];
}

@end

@implementation NSURL (NSPasteboardSupport)

// The URL is offered as a URL, and as its text so that a text field can take it too.
- (NSArray<NSPasteboardType> *) writableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return [NSArray arrayWithObjects: [self isFileURL] ? NSPasteboardTypeFileURL : NSPasteboardTypeURL,
                                      NSPasteboardTypeString, nil];
}

- (id) pasteboardPropertyListForType: (NSPasteboardType) type {
    if (NSPasteboardTypeConformsTo(type, NSPasteboardTypeURL) ||
        NSPasteboardTypeConformsTo(type, NSPasteboardTypeString))
        return [self absoluteString];
    // The 10.0 URL type: the URL string and its base.
    if ([type isEqual: NSURLPboardType])
        return [NSArray arrayWithObjects: [self absoluteString], @"", nil];
    return nil;
}

+ (NSArray<NSPasteboardType> *) readableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return [NSArray arrayWithObjects: NSPasteboardTypeFileURL, NSPasteboardTypeURL, NSURLPboardType, nil];
}

+ (NSPasteboardReadingOptions) readingOptionsForType: (NSPasteboardType) type pasteboard: (NSPasteboard *) pasteboard {
    return [type isEqual: NSURLPboardType] ? NSPasteboardReadingAsPropertyList : NSPasteboardReadingAsString;
}

- (id) initWithPasteboardPropertyList: (id) propertyList ofType: (NSPasteboardType) type {
    NSString *string = propertyList;
    if ([propertyList isKindOfClass: [NSArray class]])
        string = [propertyList count] > 0 ? [propertyList objectAtIndex: 0] : nil;
    if (![string isKindOfClass: [NSString class]] || [string length] == 0) {
        [self release];
        return nil;
    }
    return [self initWithString: string];
}

+ (NSURL *) URLFromPasteboard: (NSPasteboard *) pasteboard {
    // The flat types are the first item's, and the 10.0 URL type is its URL: that is what this
    // 10.0 method has always answered with, before the pasteboard had several items.
    NSArray *types = NSPasteboardCanonicalTypes([pasteboard types]);
    // QUIRK: with a web URL first and a file URL after it, macOS (26.7.3 and 10.14.4) answers the
    // file URL, the last file item, not the first item's URL. Not documented.
    // Evidence: black-box observation (tier 2, MAC-EVIDENCE V615, "URLs, files").
    // Test: tests/appkit-pasteboard-api.m (testURLs, URLFromPasteboard)
    NSArray *fileURLs = [pasteboard readObjectsForClasses: [NSArray arrayWithObject: [NSURL class]]
                                                  options: [NSDictionary dictionaryWithObject: [NSNumber numberWithBool: YES]
                                                                                       forKey: NSPasteboardURLReadingFileURLsOnlyKey]];
    if ([fileURLs count] > 0)
        return [fileURLs lastObject];
    for (NSPasteboardType type in [NSArray arrayWithObjects: NSPasteboardTypeFileURL, NSPasteboardTypeURL, nil]) {
        if (![types containsObject: type])
            continue;
        NSString *string = [pasteboard stringForType: type];
        NSURL *url = string != nil ? [NSURL URLWithString: string] : nil;
        if (url != nil)
            return url;
    }
    NSArray *list = [types containsObject: NSURLPboardType] ? [pasteboard propertyListForType: NSURLPboardType] : nil;
    if ([list count] > 0 && [[list objectAtIndex: 0] isKindOfClass: [NSString class]])
        return [NSURL URLWithString: [list objectAtIndex: 0]];

    NSArray *urls = [pasteboard readObjectsForClasses: [NSArray arrayWithObject: [NSURL class]] options: nil];
    return [urls count] > 0 ? [urls objectAtIndex: 0] : nil;
}

- (void) writeToPasteboard: (NSPasteboard *) pasteboard {
    [pasteboard clearContents];
    [pasteboard writeObjects: [NSArray arrayWithObject: self]];
}

@end

@implementation NSAttributedString (NSPasteboardSupport)

- (NSArray<NSPasteboardType> *) writableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return [NSArray arrayWithObjects: NSPasteboardTypeRTF, NSPasteboardTypeString, nil];
}

- (id) pasteboardPropertyListForType: (NSPasteboardType) type {
    if (NSPasteboardTypeConformsTo(type, NSPasteboardTypeRTF))
        return [self RTFFromRange: NSMakeRange(0, [self length]) documentAttributes: nil];
    if (NSPasteboardTypeConformsTo(type, NSPasteboardTypeString))
        return [self string];
    return nil;
}

// +readableTypesForPasteboard: is in NSAttributedString.m.

+ (NSPasteboardReadingOptions) readingOptionsForType: (NSPasteboardType) type pasteboard: (NSPasteboard *) pasteboard {
    return typeIsPlainText(type) ? NSPasteboardReadingAsString : NSPasteboardReadingAsData;
}

- (id) initWithPasteboardPropertyList: (id) propertyList ofType: (NSPasteboardType) type {
    if ([propertyList isKindOfClass: [NSString class]])
        return [self initWithString: propertyList];
    if (![propertyList isKindOfClass: [NSData class]]) {
        [self release];
        return nil;
    }
    if (NSPasteboardTypeConformsTo(type, NSPasteboardTypeRTFD))
        return [self initWithRTFD: propertyList documentAttributes: NULL];
    if (NSPasteboardTypeConformsTo(type, NSPasteboardTypeRTF))
        return [self initWithRTF: propertyList documentAttributes: NULL];
    [self release];
    return nil;
}

@end
