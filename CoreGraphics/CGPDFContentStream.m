#import <CoreGraphics/CGPDFContentStream.h>
#import <Onyx2D/O2PDFContentStream.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFObject_const.h>
#import <Onyx2D/O2PDFPage.h>
#import <Onyx2D/O2PDFStream.h>

// GUESS: a NULL page or stream gives NULL; the documentation does not say what either call does
// for them.
CGPDFContentStreamRef CGPDFContentStreamCreateWithPage(CGPDFPageRef page) {
    if (!page)
        return NULL;
    return (CGPDFContentStreamRef)[[O2PDFContentStream alloc] initWithPage:(O2PDFPage *)page];
}

CGPDFContentStreamRef CGPDFContentStreamCreateWithStream(CGPDFStreamRef stream, CGPDFDictionaryRef streamResources, CGPDFContentStreamRef parent) {
    if (!stream)
        return NULL;
    return (CGPDFContentStreamRef)[[O2PDFContentStream alloc] initWithStream:(O2PDFStream *)stream
                                                                   resources:(O2PDFDictionary *)streamResources
                                                                      parent:(O2PDFContentStream *)parent];
}

CGPDFContentStreamRef CGPDFContentStreamRetain(CGPDFContentStreamRef cs) {
    return (CGPDFContentStreamRef)[(O2PDFContentStream *)cs retain];
}

void CGPDFContentStreamRelease(CGPDFContentStreamRef cs) {
    [(O2PDFContentStream *)cs release];
}

// The array belongs to the content stream and is not retained for the caller; its elements are the
// streams, in page order.
// GUESS: an entry of the page's /Contents that is not a stream (a reference to a missing object) is
// not in the array; the documentation says only that it holds the content streams.
CFArrayRef CGPDFContentStreamGetStreams(CGPDFContentStreamRef cs) {
    return (CFArrayRef)[(O2PDFContentStream *)cs streams];
}

// The resource is looked up in the stream's own resource dictionary first, then in its parent's.
// GUESS: nothing is returned (NULL) when the category or name is missing, a NULL argument is
// given, or the entry refers to a missing object; the documentation does not say.
CGPDFObjectRef CGPDFContentStreamGetResource(CGPDFContentStreamRef cs, const char *category, const char *name) {
    if (!cs || !category || !name)
        return NULL;
    O2PDFObject *resource = [(O2PDFContentStream *)cs resourceForCategory:category name:name];
    if (resource == [O2PDFObject_const pdfObjectWithMissingObject])
        return NULL;
    return (CGPDFObjectRef)resource;
}
