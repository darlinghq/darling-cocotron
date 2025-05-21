/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/NSObject.h>

@class NSArray, NSCustomObject, NSSet, NSDictionary, NSMenu;

@interface NSIBObjectData : NSObject <NSCoding> {
    NSMapTable *_nameTable;
    NSArray *_accessibilityConnectors;
    NSMapTable *_classTable;
    NSMutableArray *_connections;
    id _fontManager;
    NSString *_framework;
    NSUInteger _nextOid;
    NSMapTable *_objectTable;
    NSMapTable *_oidTable;
    NSCustomObject *_fileOwner;
    NSMutableSet *_visibleWindows;
    id _firstResponder;
    BOOL _shouldEncodeDesigntimeData;
    NSMapTable *_instantiatedObjectTable;
}

@property(copy) NSString *targetFramework;
@property NSUInteger nextObjectID;
@property(readonly) NSMapTable *oidTable;
@property(readonly) NSMapTable *objectTable;
@property(readonly) NSMapTable *classTable;
@property(readonly) NSMapTable *nameTable;
@property(strong) id rootObject;
@property(copy) NSArray *connections;
@property(copy) NSSet *visibleWindows;
@property(strong) id firstResponder;
@property BOOL shouldEncodeDesigntimeData;

- (void) buildConnectionsWithNameTable: (NSDictionary *) nameTable;

- (NSSet *) visibleWindows;

- (NSMenu *) mainMenu;
- (NSArray *) topLevelObjects;

@end
