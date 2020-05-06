#import <AppKit/NSMovie.h>

@implementation NSMovie

+ (NSArray *) movieUnfilteredPasteboardTypes {
    return [[[NSArray alloc] init] autorelease];
}

@end