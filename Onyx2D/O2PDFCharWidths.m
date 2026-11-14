#include <stdlib.h>
#import <Onyx2D/O2PDFArray.h>
#import <Onyx2D/O2PDFCharWidths.h>

@implementation O2PDFCharWidths

- initWithArray: (O2PDFArray *) array
           firstChar: (int) firstChar
            lastChar: (int) lastChar
        missingWidth: (CGFloat) missingWidth
{
    int i, arrayIndex;

    for (i = 0; i < firstChar; i++)
        _widths[i] = missingWidth;

    for (arrayIndex = 0; i <= lastChar; i++, arrayIndex++) {
        O2PDFReal real = 0;

        [array getNumberAtIndex: arrayIndex value: &real];

        _widths[i] = real / 1000.0;
    }
    for (; i < 256; i++)
        _widths[i] = missingWidth;

    return self;
}

// One entry of a W array: CIDs from first to last get width (in thousandths).
static void setCIDWidths(O2PDFCharWidths *self, O2PDFInteger first,
                         O2PDFInteger last, O2PDFReal width)
{
    O2PDFInteger cid;

    // Only the part of the range the table holds: a range in a damaged W array
    // may span far more CIDs than exist.
    if (first < 0)
        first = 0;
    if (last >= (O2PDFInteger) self->_cidCount)
        last = (O2PDFInteger) self->_cidCount - 1;
    for (cid = first; cid <= last; cid++)
        self->_cidWidths[cid] = width / 1000.0;
}

- initWithCIDWidths: (O2PDFArray *) widths defaultWidth: (CGFloat) defaultWidth {
    NSUInteger i, count = [widths count];

    _isCID = YES;
    _defaultWidth = defaultWidth / 1000.0;

    // Two passes over W: the highest CID it names sizes the table, then the
    // widths are filled in. W holds "c [w1 w2 ...]" (consecutive CIDs from c)
    // and "cfirst clast w" (one width for a range).
    for (int pass = 0; pass < 2; pass++) {
        O2PDFInteger highest = -1;

        for (i = 0; i < count;) {
            O2PDFInteger first, last;
            O2PDFArray *list;
            O2PDFReal width;

            if (![widths getIntegerAtIndex: i value: &first])
                break;
            if ([widths getArrayAtIndex: i + 1 value: &list]) {
                NSUInteger j, n = [list count];

                for (j = 0; j < n; j++)
                    if ([list getNumberAtIndex: j value: &width] && pass == 1)
                        setCIDWidths(self, first + j, first + j, width);
                if (n > 0 && first + (O2PDFInteger) n - 1 > highest)
                    highest = first + n - 1;
                i += 2;
            } else if ([widths getIntegerAtIndex: i + 1 value: &last] &&
                       [widths getNumberAtIndex: i + 2 value: &width]) {
                if (pass == 1)
                    setCIDWidths(self, first, last, width);
                if (last > highest)
                    highest = last;
                i += 3;
            } else
                break;
        }

        if (pass == 0) {
            // CIDs are two bytes: at most 65536 of them.
            _cidCount = (highest < 0) ? 0 : (highest > 0xFFFF ? 0x10000 : (unsigned) highest + 1);
            _cidWidths = malloc(sizeof(O2Float) * (_cidCount ? _cidCount : 1));
            for (i = 0; i < _cidCount; i++)
                _cidWidths[i] = _defaultWidth;
        }
    }
    return self;
}

- (void) dealloc {
    free(_cidWidths);
    [super dealloc];
}

void O2PDFCharWidthsGetAdvances(O2PDFCharWidths *self, O2Size *advances,
                                const uint8_t *bytes, int length)
{
    int i;

    if (self->_isCID) {
        for (i = 0; i < length / 2; i++) {
            unsigned cid = (bytes[i * 2] << 8) | bytes[i * 2 + 1];

            advances[i].width = (cid < self->_cidCount) ? self->_cidWidths[cid] : self->_defaultWidth;
            advances[i].height = 0;
        }
        return;
    }
    for (i = 0; i < length; i++) {
        advances[i].width = self->_widths[bytes[i]];
        advances[i].height = 0;
    }
}

@end
