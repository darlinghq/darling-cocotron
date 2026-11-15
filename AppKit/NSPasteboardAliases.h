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

#import <AppKit/NSPasteboard.h>

// Pasteboard type names. Each older NSXxxPboardType (10.0 - 10.5) has a UTI counterpart
// (NSPasteboardTypeXxx, 10.6), and the two name the same data: a pasteboard stores its types under
// the UTI, and answers to the older name as well. The display backends keep their types in the
// canonical (UTI) spelling by running every type they are given through NSPasteboardCanonicalType()
// and every list they return through NSPasteboardTypesWithAliases().

// The UTI spelling of an older pasteboard type name; any other type is returned unchanged.
NSPasteboardType NSPasteboardCanonicalType(NSPasteboardType type);

// The older spelling of a UTI type that has one, or nil.
NSPasteboardType NSPasteboardLegacyAliasOfType(NSPasteboardType type);

// The canonical form of every type of the list, each followed by its older spelling, duplicates
// dropped. This is the shape of -[NSPasteboard types].
NSArray<NSPasteboardType> *NSPasteboardTypesWithAliases(NSArray<NSPasteboardType> *types);

// The canonical form of every type of the list, without the older spellings, duplicates dropped.
NSArray<NSPasteboardType> *NSPasteboardCanonicalTypes(NSArray<NSPasteboardType> *types);

// Whether type is the same as, or a subtype of, conformsTo (exact match first, then the UTI hierarchy).
BOOL NSPasteboardTypeConformsTo(NSPasteboardType type, NSPasteboardType conformsTo);
