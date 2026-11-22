/* Copyright(c) 2008 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files(the "Software"), to deal in the
Software without restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreGraphics/CoreGraphics.h>
#import <Onyx2D/O2PDFDocument.h>
#import <Onyx2D/O2PDFDictionary.h>
#import <Onyx2D/O2PDFxref.h>
#import <Onyx2D/O2PDFString.h>
#import <objc/runtime.h>

CGPDFDocumentRef CGPDFDocumentRetain(CGPDFDocumentRef self) {
    return (CGPDFDocumentRef)[self retain];
}

void CGPDFDocumentRelease(CGPDFDocumentRef self) {
    [self release];
}

CGPDFDocumentRef CGPDFDocumentCreateWithProvider(CGDataProviderRef provider) {
    return (CGPDFDocumentRef)[[O2PDFDocument alloc] initWithDataProvider: (O2DataProvider*)provider];
}

CGPDFDocumentRef CGPDFDocumentCreateWithURL(CFURLRef url) {
    return (CGPDFDocumentRef)[[O2PDFDocument alloc] initWithURL: (NSURL*)url];
}

size_t CGPDFDocumentGetNumberOfPages(CGPDFDocumentRef self) {
    return [self pageCount];
}

CGPDFPageRef CGPDFDocumentGetPage(CGPDFDocumentRef self, size_t pageNumber) {
    return (CGPDFPageRef)[self pageAtNumber: pageNumber];
}

CGPDFDictionaryRef CGPDFDocumentGetInfo(CGPDFDocumentRef self) {
    return (CGPDFDictionaryRef)[(O2PDFDocument *)self infoDictionary];
}

// Reads the /Outlines tree of the catalog: NULL when the catalog has none (observed on macOS 26.7.3 and
// Mac OS X 10.14.4, as is NULL for a NULL document), else a dictionary with one key, kCGPDFOutlineChildren,
// an array of dictionaries with kCGPDFOutlineTitle and, for an item with sub-items, kCGPDFOutlineChildren.
// The one-key shape of the root is the observed count; that the key is Children is inferred from the
// documented outline layout (an outline is a tree of children). Test: coregraphics-pdf-outline.
// Limitation: destinations (kCGPDFOutlineDestination) are not read.
// The result is owned by the document, as for the other Get functions, and lives as long as it.
static const char outlineKey;
static const int maxOutlineDepth = 32;

static NSArray *outlineItems(O2PDFDictionary *parent, int depth) {
    NSMutableArray *items = [NSMutableArray array];
    O2PDFDictionary *item;
    // A damaged file may link the siblings in a loop, so the number of items is bounded.
    NSUInteger budget = 100000;

    if (depth > maxOutlineDepth || ![parent getDictionaryForKey: "First" value: &item])
        return items;
    while (item != nil && budget-- > 0) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        O2PDFString *title;

        if ([item getStringForKey: "Title" value: &title]) {
            CFStringRef text = CGPDFStringCopyTextString((CGPDFStringRef) title);

            if (text != NULL) {
                [entry setObject: (NSString *) text forKey: (NSString *) kCGPDFOutlineTitle];
                CFRelease(text);
            }
        }
        NSArray *children = outlineItems(item, depth + 1);

        if ([children count] > 0)
            [entry setObject: children forKey: (NSString *) kCGPDFOutlineChildren];
        [items addObject: entry];
        if (![item getDictionaryForKey: "Next" value: &item])
            break;
    }
    return items;
}

CFDictionaryRef CGPDFDocumentGetOutline(CGPDFDocumentRef document) {
    if (document == NULL)
        return NULL;
    O2PDFDocument *pdf = (O2PDFDocument *) document;
    NSDictionary *cached = objc_getAssociatedObject(pdf, &outlineKey);

    if (cached != nil)
        return (CFDictionaryRef) cached;

    O2PDFDictionary *root;

    if (![[pdf catalog] getDictionaryForKey: "Outlines" value: &root])
        return NULL;
    cached = [NSDictionary dictionaryWithObject: outlineItems(root, 0)
                                         forKey: (NSString *) kCGPDFOutlineChildren];
    objc_setAssociatedObject(pdf, &outlineKey, cached, OBJC_ASSOCIATION_RETAIN);
    return (CFDictionaryRef) cached;
}

bool CGPDFDocumentIsEncrypted(CGPDFDocumentRef self) {
    return [(O2PDFDocument *)self encryptDictionary] != nil;
}

// Onyx2D does not implement PDF decryption (there is no CGPDFDocumentUnlockWithPassword),
// so an encrypted document can never be unlocked here: only an unencrypted one is.
bool CGPDFDocumentIsUnlocked(CGPDFDocumentRef self) {
    return !CGPDFDocumentIsEncrypted(self);
}

bool CGPDFDocumentAllowsCopying(CGPDFDocumentRef self) {
    O2PDFDictionary *trailer = [[(O2PDFDocument *)self xref] trailer];
    if (!trailer)
        return false;
    O2PDFObject *encryption = nil;
    if (![trailer getObjectForKey:"Encrypt" value:&encryption])
        return true;
    return [encryption objectType] == kO2PDFObjectTypeNull;
}
