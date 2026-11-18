/* Copyright (C) 2026 Lubos Dolezel

Private. Document type names as AppKit reports them: a CFBundleDocumentTypes entry that declares
LSItemContentTypes is named by those uniform type identifiers, any other entry by its CFBundleTypeName. */
#import <Foundation/Foundation.h>

// Every type name of an entry; the first one is the entry's primary name.
static inline NSArray *NSDocumentTypeNamesForInfo(NSDictionary *info) {
    NSArray *contentTypes = [info objectForKey: @"LSItemContentTypes"];
    if ([contentTypes count] > 0)
        return contentTypes;
    NSString *name = [info objectForKey: @"CFBundleTypeName"];
    return name != nil ? [NSArray arrayWithObject: name] : [NSArray array];
}

static inline NSString *NSDocumentTypeNameForInfo(NSDictionary *info) {
    return [NSDocumentTypeNamesForInfo(info) firstObject];
}

static inline BOOL NSDocumentInfoHasTypeName(NSDictionary *info, NSString *type) {
    return type != nil && [NSDocumentTypeNamesForInfo(info) containsObject: type];
}
