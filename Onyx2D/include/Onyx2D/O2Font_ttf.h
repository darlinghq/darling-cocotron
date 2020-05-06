#import <Onyx2D/O2Font.h>

@class NSMapTable;

@interface O2Font_ttf : O2Font {
    NSMapTable *_nameToGlyph;
    NSInteger *_glyphLocations;
}

- initWithDataProvider: (O2DataProviderRef) provider;

@end
