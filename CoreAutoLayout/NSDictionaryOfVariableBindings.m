/*
 This file is part of Darling.

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
*/

#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#include <stdarg.h>

// Backs the NSDictionaryOfVariableBindings(v1, v2, ...) macro, which expands to
// _NSDictionaryOfVariableBindings(@"v1, v2, ...", v1, v2, ..., nil): each name in the
// comma-separated string maps to the corresponding value.
__attribute__((visibility("default")))
NSDictionary *_NSDictionaryOfVariableBindings(NSString *commaSeparatedKeysString, id firstValue, ...)
{
    NSArray *names = [commaSeparatedKeysString componentsSeparatedByString:@","];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[names count]];

    va_list args;
    va_start(args, firstValue);
    id value = firstValue;
    for (NSString *rawName in names) {
        NSString *name = [rawName stringByTrimmingCharactersInSet:whitespace];
        if ([name length] == 0)
            continue;
        if (value == nil) {
            va_end(args);
            [NSException raise:NSInvalidArgumentException
                        format:@"NSDictionaryOfVariableBindings: value for key '%@' is nil", name];
        }
        [result setObject:value forKey:name];
        value = va_arg(args, id);
    }
    va_end(args);

    return result;
}
