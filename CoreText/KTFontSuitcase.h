/* Copyright (C) 2026 Lubos Dolezel */
#import <Foundation/NSObject.h>

@class NSArray, NSData;

// A Mac OS X ".dfont" is a font suitcase, a resource file stored in the data
// fork: its 'sfnt' resources are TrueType/OpenType fonts and a 'FOND'
// resource names the family and lists the faces. This reads the container only.
//
// Returns nil when the data is not a resource file with 'sfnt' resources.
// Otherwise one dictionary per 'sfnt' resource, in the order the 'FOND'
// resources list the faces (their association tables), then the faces no
// record lists, with the keys
//   @"faceIndex"       NSNumber, the face's position among the 'sfnt'
//                      resources of the map (the face index FreeType uses)
//   @"postScriptName"  NSString, only when the family's 'FOND' resource
//                      derives a PostScript name for the face (its style
//                      mapping table: a base name and a style suffix)
// The caller owns the result.
__attribute__((visibility("hidden")))
NSArray *KTFontSuitcaseCopyFaces(NSData *data);
