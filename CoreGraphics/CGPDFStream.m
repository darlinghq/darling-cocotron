#import <CoreGraphics/CGPDFStream.h>
#import <Onyx2D/O2PDFStream.h>

CGPDFDictionaryRef CGPDFStreamGetDictionary(CGPDFStreamRef stream) {
    return (CGPDFDictionaryRef)[(O2PDFStream *)stream dictionary];
}
