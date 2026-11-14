#import <Foundation/NSObject.h>
#import <Onyx2D/O2Geometry.h>

@class O2PDFArray;

@interface O2PDFCharWidths : NSObject {
    O2Float _widths[256];
    // Widths of a CIDFont (two-byte codes): _cidWidths[cid] for cid below
    // _cidCount, _defaultWidth for the others.
    BOOL _isCID;
    O2Float *_cidWidths;
    unsigned _cidCount;
    O2Float _defaultWidth;
}

- initWithArray: (O2PDFArray *) array
           firstChar: (int) firstChar
            lastChar: (int) lastChar
        missingWidth: (CGFloat) missingWidth;
// The W array of a CIDFont (may be nil) and its DW, both in thousandths of a
// text space unit.
- initWithCIDWidths: (O2PDFArray *) widths defaultWidth: (CGFloat) defaultWidth;

void O2PDFCharWidthsGetAdvances(O2PDFCharWidths *self, O2Size *advances,
                                const uint8_t *bytes, int length);

@end
