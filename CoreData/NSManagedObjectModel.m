/* Copyright (c) 2008 Dan Knapp

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
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSManagedObjectModel.h>

#import <Foundation/NSKeyedUnarchiver.h>
#import <Foundation/NSRaise.h>
#import "NSEntityDescription-Private.h"
#import "NSManagedObjectModel-Private.h"

@implementation NSManagedObjectModel

+ (NSManagedObjectModel *) modelByMergingModels: (NSArray *) models {
    NSManagedObjectModel *result = [[NSManagedObjectModel alloc] init];
    NSMutableArray *entities = [NSMutableArray array];

    for (NSManagedObjectModel *merge in models) {
        [entities addObjectsFromArray: [merge entities]];
    }

    [result setEntities: entities];

    return result;
}

+ (NSManagedObjectModel *) mergedModelFromBundles: (NSArray *) bundles {
    NSMutableArray *models = [NSMutableArray array];

    if (bundles == nil)
        bundles = [NSArray arrayWithObject: [NSBundle mainBundle]];

    for (NSBundle *bundle in bundles) {
        NSArray *moms = [bundle pathsForResourcesOfType: @"mom"
                                            inDirectory: nil];

        for (NSString *path in moms) {
            NSURL *url = [NSURL fileURLWithPath: path];
            NSManagedObjectModel *model =
                    [[NSManagedObjectModel alloc] initWithContentsOfURL: url];

            if (model == nil)
                NSLog(@"-[%@ initWithContentsOfURL:] failed. url=%@", self,
                      url);

            if (model != nil)
                [models addObject: model];
        }
    }

    return [self modelByMergingModels: models];
}

- init {
    _entities = [[NSMutableDictionary alloc] init];
    _fetchRequestTemplates = [[NSMutableDictionary alloc] init];
    _configurations = [[NSMutableDictionary alloc] init];
    return self;
}

- initWithCoder: (NSCoder *) coder {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException
                    format: @"%@ can not initWithCoder:%@", [self class],
                            [coder class]];

    NSDictionary *decoded = [coder decodeObjectForKey: @"NSEntities"];
    _entities = [[NSMutableDictionary alloc] init];
    for (NSEntityDescription *entity in [decoded allValues]) {
        if ([[entity name] length]) {
            [_entities setObject:entity forKey:[entity name]];
            [entity _setManagedObjectModel:self];
        }
    }

    _fetchRequestTemplates =
            [[coder decodeObjectForKey: @"NSFetchRequestTemplates"] retain];
    _versionIdentifiers =
            [[coder decodeObjectForKey: @"NSVersionIdentifiers"] retain];

    return self;
}

- initWithContentsOfURL: (NSURL *) url {
    [self dealloc];

    NSData *data = [[NSData alloc] initWithContentsOfURL: url];

    if (data == nil) {
        return nil;
    }

    NSKeyedUnarchiver *unarchiver =
            [[NSKeyedUnarchiver alloc] initForReadingWithData: data];
    NSManagedObjectModel *result =
            [[unarchiver decodeObjectForKey: @"root"] retain];

    [unarchiver release];
    [data release];

    return result;
}

- (NSArray *) entities {
    return [_entities allValues];
}

- copyWithZone: (NSZone *) zone {
    NSManagedObjectModel *copy = [[NSManagedObjectModel allocWithZone: zone] init];
    copy->_entities = [_entities mutableCopyWithZone: zone];
    copy->_fetchRequestTemplates = [_fetchRequestTemplates mutableCopyWithZone: zone];
    copy->_configurations = [_configurations mutableCopyWithZone: zone];
    copy->_localizationDictionary = [_localizationDictionary copyWithZone: zone];
    copy->_versionIdentifiers = [_versionIdentifiers copyWithZone: zone];
    return copy;
}

- (NSDictionary *) entitiesByName {
    return _entities;
}

- (NSDictionary *) localizationDictionary {
    return _localizationDictionary;
}

- (void) setEntities: (NSArray *) entities {
    if (_inUse)
        [NSException raise:NSInvalidArgumentException format:@"The managed object model is in use."];
    NSMutableDictionary *configured = [NSMutableDictionary dictionary];
    for (NSEntityDescription *entity in entities) {
        if (![entity isKindOfClass:[NSEntityDescription class]] || ![[entity name] length] ||
            ([entity managedObjectModel] && [entity managedObjectModel] != self) ||
            [configured objectForKey:[entity name]])
            [NSException raise:NSInvalidArgumentException format:@"Invalid or duplicate model entity."];
        [configured setObject:entity forKey:[entity name]];
    }
    for (NSEntityDescription *entity in [_entities allValues])
        if ([configured objectForKey:[entity name]] != entity)
            [entity _setManagedObjectModel:nil];
    for (NSEntityDescription *entity in [configured allValues])
        [entity _setManagedObjectModel:self];
    [_entities release];
    _entities = [configured retain];
}

- (void)_renameEntity:(NSEntityDescription *)entity from:(NSString *)oldName to:(NSString *)newName {
    NSEntityDescription *existing = [_entities objectForKey:newName];
    if (existing && existing != entity)
        [NSException raise:NSInvalidArgumentException format:@"Entity names must be unique within a model."];
    [_entities setObject:entity forKey:newName];
    if (oldName && ![oldName isEqual:newName])
        [_entities removeObjectForKey:oldName];
}

- (void)_setInUse {
    _inUse = YES;
    for (NSEntityDescription *entity in [_entities allValues])
        [entity _setInUse];
}

- (void) setLocalizationDictionary: (NSDictionary *) dictionary {
    dictionary = [dictionary copy];
    [_localizationDictionary release];
    _localizationDictionary = dictionary;
}

- (NSArray *) configurations {
    return [_configurations allKeys];
}

- (NSArray *) entitiesForConfiguration: (NSString *) configuration {
    return [_configurations objectForKey: configuration];
}

- (void) setEntities: (NSArray *) entities
        forConfiguration: (NSString *) configuration
{
    [_configurations setObject: entities forKey: configuration];
}

- (NSFetchRequest *) fetchRequestTemplateForName: (NSString *) name {
    return [_fetchRequestTemplates objectForKey: name];
}

- (NSFetchRequest *) fetchRequestFromTemplateWithName: (NSString *) name
                                substitutionVariables:
                                        (NSDictionary *) variables
{
    NSUnimplementedMethod();
}

- (void) setFetchRequestTemplate: (NSFetchRequest *) fetchRequest
                         forName: (NSString *) name
{
    [_fetchRequestTemplates setObject: fetchRequest forKey: name];
}

@end
