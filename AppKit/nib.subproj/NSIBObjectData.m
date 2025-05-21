/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

 Permission is hereby granted, free of charge, to any person obtaining
 a copy of this software and associated documentation files (the
 "Software"), to deal in the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish,
 distribute, sublicense, and/or sell copies of the Software, and to
 permit persons to whom the Software is furnished to do so, subject to
 the following conditions:

 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "NSIBObjectData.h"
#import "NSCustomObject.h"
#import "NSMenuTemplate.h"
#import <AppKit/NSFontManager.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSNibConnector.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSKeyedUnarchiver.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>
#import <AppKit/NSMenuItem.h>

NSString *const IBCocoaFramework = @"IBCocoaFramework";

@interface NSKeyedUnarchiver (private)
- (void) replaceObject: object withObject: replacement;
@end

@interface NSNib (private)
- (NSDictionary *) externalNameTable;
@end

@interface NSMenu (private)
- (NSString *) _name;
@end

@interface NSIBObjectData (private)
- (void) replaceObject: (id) oldObject withObject: (id) newObject;
@end

@implementation NSIBObjectData

@synthesize targetFramework = _framework;
@synthesize nextObjectID = _nextOid;
@synthesize oidTable = _oidTable;
@synthesize objectTable = _objectTable;
@synthesize classTable = _classTable;
@synthesize nameTable = _nameTable;
@synthesize rootObject = _fileOwner;
@synthesize connections = _connections;
@synthesize visibleWindows = _visibleWindows;
@synthesize firstResponder = _firstResponder;
@synthesize shouldEncodeDesigntimeData = _shouldEncodeDesigntimeData;

- (instancetype) init {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _connections = [NSMutableArray new];
    _framework = [IBCocoaFramework copy];
    _nextOid = 1;
    _visibleWindows = [NSMutableSet new];
    _shouldEncodeDesigntimeData = YES;

    _nameTable = [[NSMapTable alloc] initWithKeyOptions: NSPointerFunctionsObjectPointerPersonality | NSPointerFunctionsStrongMemory
                                           valueOptions: NSPointerFunctionsObjectPersonality | NSPointerFunctionsStrongMemory
                                               capacity: 0];

    _classTable = [[NSMapTable alloc] initWithKeyOptions: NSPointerFunctionsObjectPointerPersonality | NSPointerFunctionsStrongMemory
                                            valueOptions: NSPointerFunctionsObjectPersonality | NSPointerFunctionsStrongMemory
                                                capacity: 0];

    _objectTable = [[NSMapTable alloc] initWithKeyOptions: NSPointerFunctionsObjectPointerPersonality | NSPointerFunctionsStrongMemory
                                             valueOptions: NSPointerFunctionsObjectPersonality | NSPointerFunctionsStrongMemory
                                                 capacity: 0];

    _oidTable = [[NSMapTable alloc] initWithKeyOptions: NSPointerFunctionsObjectPointerPersonality | NSPointerFunctionsStrongMemory
                                          valueOptions: NSPointerFunctionsIntegerPersonality | NSPointerFunctionsOpaqueMemory
                                              capacity: 0];

    return self;
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [self init];
    if (self == nil) {
        return nil;
    }

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        NSMutableDictionary *nameTable = [NSMutableDictionary
                dictionaryWithDictionary: [[keyed delegate] externalNameTable]];
        int i, count;
        id owner;

        if ((owner = [nameTable objectForKey: NSNibOwner]) != nil)
            [nameTable setObject: owner forKey: @"File's Owner"];

        [nameTable setObject: [NSFontManager sharedFontManager]
                      forKey: @"Font Manager"];

        NSArray *namesValues = [keyed decodeObjectForKey: @"NSNamesValues"];
        NSArray *namedObjects = [keyed decodeObjectForKey: @"NSNamesKeys"];
        count = [namesValues count];
        for (i = 0; i < count; i++) {
            NSString *check = [namesValues objectAtIndex: i];
            id external = [nameTable objectForKey: check];
            id nibObject = [namedObjects objectAtIndex: i];

            if (external != nil) {
                [keyed replaceObject: nibObject withObject: external];
                [_nameTable setObject: check forKey: external];
            } else if ([nibObject isKindOfClass: [NSCustomObject class]]) {
                id replacement = [nibObject createCustomInstance];

                if (replacement == nil) {
                    [_nameTable setObject: check forKey: nibObject];
                } else {
                    [keyed replaceObject: nibObject withObject: replacement];
                    [_nameTable setObject: check forKey: replacement];
                    [replacement release];
                }
            } else {
                [_nameTable setObject: check forKey: nibObject];
            }
        }

        _fileOwner = [[keyed decodeObjectForKey: @"NSRoot"] retain];
        if ([_fileOwner isKindOfClass: [NSCustomObject class]]) {
            if (_fileOwner != owner) {
                id formerFileOwner = [_fileOwner autorelease];
                _fileOwner = [owner retain];
                [keyed replaceObject: formerFileOwner withObject: _fileOwner];
            }
        }

        _accessibilityConnectors = [[keyed
                decodeObjectForKey: @"NSAccessibilityConnectors"] retain];

        NSArray *classesKeys = [keyed decodeObjectForKey: @"NSClassesKeys"];
        NSArray *classesValues = [keyed decodeObjectForKey: @"NSClassesValues"];

        for (NSUInteger i = 0; i < classesKeys.count; ++i) {
            [_classTable setObject: classesValues[i] forKey: classesKeys[i]];
        }

        [_connections setArray: [keyed decodeObjectForKey: @"NSConnections"]];
        _fontManager = [[keyed decodeObjectForKey: @"NSFontManager"] retain];
        self.targetFramework = [keyed decodeObjectForKey: @"NSFramework"];
        _nextOid = [keyed decodeInt64ForKey: @"NSNextOid"];

        NSArray *objectKeys = [keyed decodeObjectForKey: @"NSObjectsKeys"];
        NSArray *objectValues = [keyed decodeObjectForKey: @"NSObjectsValues"];

        // Replace any custom object with the real thing - and update anything
        // tracking them
        // NOTE(facekapow): i'm not really sure why this iterates backwards over the objects,
        //                  but i'm keeping it this way in case it's required for correct functionality.
        for (NSUInteger idxPlusOne = objectValues.count; idxPlusOne > 0; --idxPlusOne) {
            NSUInteger i = idxPlusOne - 1;
            id aKey = objectKeys[i];
            id aValue = objectValues[i];
            id replacement = nil;

            if (aValue == owner && [aKey isKindOfClass: [NSCustomObject class]]) {
                replacement = [aKey createCustomInstance];
            }

            if (replacement != nil) {
                // Tell the decoder we are now using that - that will notify
                // the Nib object
                [keyed replaceObject: aKey withObject: replacement];
                // Update the connections
                [self replaceObject: aKey withObject: replacement];

                [_objectTable setObject: aValue forKey: replacement];
                [replacement release];
            } else {
                [_objectTable setObject: aValue forKey: aKey];
            }
        }

        NSArray *oidKeys = [keyed decodeObjectForKey: @"NSOidsKeys"];
        NSArray *oidValues = [keyed decodeObjectForKey: @"NSOidsValues"];

        for (NSUInteger i = 0; i < oidKeys.count; ++i) {
            // since we're using integers for the values, we should use the C API instead of the ObjC API
            NSMapInsert(_oidTable, oidKeys[i], (const void *)((NSNumber *)oidValues[i]).integerValue);
        }

        NSArray *accessibilityOidKeys = [keyed decodeObjectForKey: @"NSAccessibilityOidsKeys"];
        NSArray *accessibilityOidValues = [keyed decodeObjectForKey: @"NSAccessibilityOidsValues"];

        for (NSUInteger i = 0; i < accessibilityOidKeys.count; ++i) {
            // accessibility OIDs don't override normal OIDs
            NSMapInsertIfAbsent(_oidTable, accessibilityOidKeys[i], (const void *)((NSNumber *)accessibilityOidValues[i]).integerValue);
        }

        [_visibleWindows setSet: [keyed decodeObjectForKey: @"NSVisibleWindows"]];
    } else {
        NSInteger version = [coder versionForClassName: @"NSIBObjectData"];
        int count;

        [coder decodeValueOfObjCType: @encode(id) at: &_fileOwner];

        // Decode objectTable key/value pairs
        [coder decodeValueOfObjCType: @encode(int) at: &count];

        if (version < 16) {
            // Super legacy support
            // read version 0

            NSMutableSet *keySet = [[NSMutableSet alloc] init];

            for (int i = 0; i < count; i++) {
                NSMenuItem *key;
                NSObject *value;

                [coder decodeValuesOfObjCTypes: "@@", &key, &value];
                [_objectTable setObject: value forKey: key];
                [keySet addObject: key];

                if ([key isKindOfClass: [NSMenuItem class]]) {
                    id target = [key target];

                    if ([target isKindOfClass: [NSMenuTemplate class]] &&
                        ![keySet containsObject: target]) {
                        [_objectTable setObject: key forKey: target];
                        [keySet addObject: target];
                    }
                }
                [key release];
                [value release];
            }

            [keySet release];

            // Decode nameTable key/value pairs
            // Old format uses ordinary strings for values
            [coder decodeValueOfObjCType: @encode(int) at: &count];

            for (int i = 0; i < count; i++) {
                NSObject *key;
                char *string;
                NSString *nss;

                [coder decodeValuesOfObjCTypes: "@*", &key, &string];

                // The string encoding is a guess
                nss = [[NSString alloc]
                        initWithBytes: string
                               length: strlen(string)
                             encoding: NSNEXTSTEPStringEncoding];

                [_nameTable setObject: nss forKey: key];

                [nss release];
                [key release];
                free(string);
            }

            // Decode visibleWindows
            [coder decodeValueOfObjCType: @encode(int) at: &count];

            for (int i = 0; i < count; i++) {
                NSObject *key;

                [coder decodeValueOfObjCType: @encode(id) at: &key];
                [_visibleWindows addObject: key];
                [key release];
            }

            if ([coder versionForClassName: @"List"] == 0) {
                int unknown;
                [coder decodeValueOfObjCType: @encode(int) at: &unknown];
            }

            [coder decodeValueOfObjCType: @encode(int) at: &count];

            NSObject **connections =
                    (NSObject **) malloc(sizeof(NSObject *) * count);

            [coder decodeArrayOfObjCType: @encode(id)
                                   count: count
                                      at: connections];
            [_connections setArray: [NSArray arrayWithObjects: connections
                                                        count: count]];

            for (int i = 0; i < count; ++i) {
                [connections[i] release];
            }
            free(connections);

            [coder decodeValueOfObjCType: @encode(id) at: &_fontManager];
        } else {
            for (int i = 0; i < count; i++) {
                NSMenuItem *key;
                NSObject *value;

                [coder decodeValuesOfObjCTypes: "@@", &key, &value];
                [_objectTable setObject: value forKey: key];

                [key release];
                [value release];
            }

            // Decode nameTable key/value pairs
            [coder decodeValueOfObjCType: @encode(int) at: &count];

            for (int i = 0; i < count; i++) {
                NSObject *key, *value;
                [coder decodeValuesOfObjCTypes: "@@", &key, &value];

                [_nameTable setObject: value forKey: key];

                [key release];
                [value release];
            }

            NSSet *visibleWindows = nil;
            NSArray *connections = nil;

            [coder decodeValueOfObjCType: @encode(id) at: &visibleWindows];
            [coder decodeValueOfObjCType: @encode(id) at: &connections];
            [coder decodeValueOfObjCType: @encode(id) at: &_fontManager];

            [_visibleWindows setSet: visibleWindows];
            [visibleWindows release];
            [_connections setArray: connections];
            [connections release];

            // Oid table since version 19
            if (version > 18) {
                [coder decodeValueOfObjCType: @encode(int) at: &count];

                for (int i = 0; i < count; i++) {
                    NSObject *key;
                    int value;

                    [coder decodeValuesOfObjCTypes: "@i", &key, &value];
                    NSMapInsert(_oidTable, key, (const void *)(NSInteger)value);
                    [key release];
                }

                int nextOid;
                [coder decodeValueOfObjCType: @encode(int) at: &nextOid];
                _nextOid = nextOid;
            }

            if (version > 23) {
                [coder decodeValueOfObjCType: @encode(int) at: &count];

                for (int i = 0; i < count; i++) {
                    NSObject *key, *value;

                    [coder decodeValuesOfObjCTypes: "@@", &key, &value];
                    NSMapInsert(_instantiatedObjectTable, key, value);
                }
            }

            if (version <= 223) {
                _framework = [IBCocoaFramework copy];
            } else {
                _framework = [[coder decodeObject] retain];
            }
        }

        if (!NSMapMember(_oidTable, _fileOwner, NULL, NULL)) {
            NSMapInsertKnownAbsent(_oidTable, _fileOwner, (const void *)(_nextOid++));
        }

        for (id objectKey in _objectTable) {
            if (!NSMapMember(_oidTable, objectKey, NULL, NULL)) {
                NSMapInsertKnownAbsent(_oidTable, objectKey, (const void *)(_nextOid++));
            }
        }

        // enumerate connections
        for (id conn in _connections) {
            if (!NSMapMember(_oidTable, conn, NULL, NULL)) {
                NSMapInsertKnownAbsent(_oidTable, conn, (const void *)(_nextOid++));
            }
        }
    }

    return self;
}

- (NSArray *) _sortedAndFilteredMapTableKeys: (NSMapTable *) mapTable {
    NSMutableArray *initialKeys = [[NSAllMapTableKeys(mapTable) mutableCopy] autorelease];

    // remove the firstResponder from the key array, if present.
    // it's never included in the encoded output.
    if (_firstResponder != nil) {
        [initialKeys removeObjectIdenticalTo: _firstResponder];
    }

    // we need map table entries to be sorted in OID order.
    // not sure if it's important, but that's what i've seen in NIBs so that's what we'll do.
    return [initialKeys sortedArrayWithOptions: NSSortStable usingComparator: ^NSComparisonResult(id key1, id key2) {
        // the OID table uses integers directly as values, so we have to use the C API instead of the ObjC API
        NSUInteger oid1 = (NSUInteger)NSMapGet(_oidTable, key1);
        NSUInteger oid2 = (NSUInteger)NSMapGet(_oidTable, key2);
        if (oid1 > oid2) {
            return NSOrderedDescending;
        } else if (oid1 < oid2) {
            return NSOrderedAscending;
        } else {
            // this shouldn't happen
            return NSOrderedSame;
        }
    }];
}

- (void) _encodeObjectMapTable: (NSMapTable *) objectMapTable
                     withCoder: (NSCoder *) coder
                      keysName: (NSString *) keyName
                    valuesName: (NSString *) valueName
{
    // all map tables entries are encoded in ascending order according to their OID
    NSArray *keys = [self _sortedAndFilteredMapTableKeys: objectMapTable];

    NSMutableArray *values = [NSMutableArray arrayWithCapacity: keys.count];
    for (id key in keys) {
        [values addObject: [objectMapTable objectForKey: key]];
    }

    [coder encodeObject: keys forKey: keyName];
    [coder encodeObject: values forKey: valueName];
}

- (void) encodeWithCoder: (NSCoder *) coder {
    if (coder.allowsKeyedCoding) {
        // we can't use `_encodeObjectMapTable` to encode the OID table since its values aren't objects
        NSArray *oidKeys = [self _sortedAndFilteredMapTableKeys: _oidTable];

        NSMutableArray *oidValues = [NSMutableArray arrayWithCapacity: oidKeys.count];
        for (id oidKey in oidKeys) {
            [oidValues addObject: [NSNumber numberWithInteger: (NSUInteger)NSMapGet(_oidTable, oidKey)]];
        }
        NSArray *oidValuesImmutable = [[oidValues copy] autorelease];

        [coder encodeObject: oidKeys forKey: @"NSOidsKeys"];
        [coder encodeObject: oidValuesImmutable forKey: @"NSOidsValues"];

        [self _encodeObjectMapTable: _objectTable
                          withCoder: coder
                           keysName: @"NSObjectsKeys"
                         valuesName: @"NSObjectsValues"];

        [coder encodeObject: _fileOwner forKey: @"NSRoot"];
        [coder encodeObject: _accessibilityConnectors forKey: @"NSAccessibilityConnectors"];

        // just encode empty arrays here for now
        [coder encodeObject: [NSArray array] forKey: @"NSAccessibilityOidsKeys"];
        [coder encodeObject: [NSArray array] forKey: @"NSAccessibilityOidsValues"];

        // note that these *have* to be encoded as mutable arrays
        [coder encodeObject: _connections forKey: @"NSConnections"];
        [coder encodeObject: _visibleWindows forKey: @"NSVisibleWindows"];

        // this is all considered "design-time" data and only encoded if `shouldEncodeDesigntimeData` is true.
        if (self.shouldEncodeDesigntimeData) {
            [self _encodeObjectMapTable: _nameTable
                              withCoder: coder
                               keysName: @"NSNamesKeys"
                             valuesName: @"NSNamesValues"];
            [self _encodeObjectMapTable: _classTable
                              withCoder: coder
                               keysName: @"NSClassesKeys"
                             valuesName: @"NSClassesValues"];

            [coder encodeObject: _fontManager forKey: @"NSFontManager"];
            [coder encodeObject: _framework forKey: @"NSFramework"];
            [coder encodeInt64: _nextOid forKey: @"NSNextOid"];
        }
    } else {
        [NSException raise: NSInvalidArchiveOperationException
                    format: @"TODO: support unkeyed encoding in NSIBObjectData"];
    }
}

- (void) dealloc {
    [_accessibilityConnectors release];
    [_classTable release];
    [_connections release];
    [_fontManager release];
    [_framework release];
    [_nameTable release];
    [_objectTable release];
    [_oidTable release];
    [_fileOwner release];
    [_visibleWindows release];
    [_firstResponder release];
    [super dealloc];
}

- (NSMenu *) mainMenu {
    for (id aKey in _objectTable) {
        id aValue = [_objectTable objectForKey: aKey];
        if (aValue == _fileOwner) {
            if ([aKey isKindOfClass: [NSMenu class]] &&
                [[(NSMenu *) aKey _name] isEqual: @"_NSMainMenu"]) {
                return aKey;
            }
        }
    }
    return nil;
}

- (void) replaceObject: oldObject withObject: newObject {
    int i, count = [_connections count];
    for (i = 0; i < count; i++)
        [[_connections objectAtIndex: i] replaceObject: oldObject
                                            withObject: newObject];
}

- (void) establishConnections {
    int i, count = [_connections count];

    for (i = 0; i < count; i++) {
        NS_DURING[[_connections objectAtIndex: i] establishConnection];
        NS_HANDLER
        if (NSDebugEnabled)
            NSLog(@"Exception during -establishConnection %@", localException);
        NS_ENDHANDLER
    }
}

- (void) buildConnectionsWithNameTable: (NSDictionary *) nameTable {
    id owner = [nameTable objectForKey: NSNibOwner];
    if (_fileOwner != owner) {
        [self replaceObject: _fileOwner withObject: owner];
        id formerOwner = [_fileOwner autorelease];
        _fileOwner = [owner retain];

        NSArray *keys = NSAllMapTableKeys(_objectTable);
        for (id aKey in keys) {
            id aValue = [_objectTable objectForKey: aKey];
            if (aValue == formerOwner) {
                [_objectTable setObject: _fileOwner forKey: aKey];
            }
        }
    }
    [self establishConnections];
}

/*!
 * @result  All top-level objects in the nib, except the File's Owner
 (and the virtual First Responder)
 */
- (NSArray *) topLevelObjects {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    NSMutableArray *topLevelObjects = [NSMutableArray array];

    for (id anObject in _objectTable) {
        id eachObject = [_objectTable objectForKey: anObject];

        if (eachObject == _fileOwner && anObject != _fileOwner)
            [topLevelObjects addObject: anObject];
    }

    return topLevelObjects;
}

@end
