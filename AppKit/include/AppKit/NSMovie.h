#import <Foundation/Foundation.h>
#import <AppKit/AppKitIvarLayout.h>

@interface NSMovie : NSObject {
    NS_LEGACY_IVAR_PAD(_NSMovieReserved, 20)
}

+ (NSArray *) movieUnfilteredPasteboardTypes;

@end