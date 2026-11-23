/* Copyright (c) 2009 Christopher J. W. Lloyd <cjwl@objc.net>

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
#import <CoreGraphics/CGPDFContext.h>
#import <Onyx2D/O2PDFContext.h>

#include <CoreFoundation/CFString.h>

// The PDF writer cannot encrypt yet. A request for encryption is refused
// instead of writing an unprotected file the caller believes is protected.
static bool requestsEncryption(NSDictionary *info) {
    return [info objectForKey:(id)kCGPDFContextUserPassword] ||
           [info objectForKey:(id)kCGPDFContextOwnerPassword] ||
           [info objectForKey:(id)kCGPDFContextEncryptionKeyLength];
}

const CFStringRef kCGPDFContextTitle = CFSTR("kCGPDFContextTitle");
const CFStringRef kCGPDFContextAuthor = CFSTR("kCGPDFContextAuthor");
const CFStringRef kCGPDFContextCreator = CFSTR("kCGPDFContextCreator");
const CFStringRef kCGPDFContextKeywords = CFSTR("kCGPDFContextKeywords");
const CFStringRef kCGPDFContextMediaBox = CFSTR("MediaBox");
const CFStringRef kCGPDFContextOwnerPassword = CFSTR("kCGPDFContextOwnerPassword");
const CFStringRef kCGPDFContextUserPassword = CFSTR("kCGPDFContextUserPassword");
const CFStringRef kCGPDFContextEncryptionKeyLength = CFSTR("kCGPDFContextEncryptionKeyLength");
const CFStringRef kCGPDFContextCropBox = CFSTR("CropBox");
const CFStringRef kCGPDFContextBleedBox = CFSTR("BleedBox");
const CFStringRef kCGPDFContextTrimBox = CFSTR("TrimBox");
const CFStringRef kCGPDFContextArtBox = CFSTR("ArtBox");

// The string values of these keys were read on macOS 26.7.3 and Mac OS X 10.14.4 through their public symbols
// (black-box observation, identical on both): Subject and OutputIntent are the symbol names, while the four
// PDF/X keys are the PDF key names of the output intent dictionary (PDF 32000-1 14.11.5), and the PDF/A key
// is the string "CGPDFContextCreatePDFA" (the symbol is absent from 10.14.4, which has no such key; it is
// provided anyway). Test: coregraphics-pdf-context-keys.
// The keys are declared so callers can use them; CGPDFContextCreate accepts them and does not write them: the
// subject (like the keywords) is dropped because only the title, author and creator reach the file, and the
// PDF/A and PDF/X keys have no effect.
const CFStringRef kCGPDFContextSubject = CFSTR("kCGPDFContextSubject");
const CFStringRef kCGPDFContextCreatePDFA = CFSTR("CGPDFContextCreatePDFA");
const CFStringRef kCGPDFContextOutputIntent = CFSTR("kCGPDFContextOutputIntent");
const CFStringRef kCGPDFXInfo = CFSTR("Info");
const CFStringRef kCGPDFXOutputConditionIdentifier = CFSTR("OutputConditionIdentifier");
const CFStringRef kCGPDFXOutputIntentSubtype = CFSTR("S");
const CFStringRef kCGPDFXDestinationOutputProfile = CFSTR("DestOutputProfile");

// The keys of the outline dictionary of CGPDFContextSetOutline and CGPDFDocumentGetOutline (same observation).
const CFStringRef kCGPDFOutlineTitle = CFSTR("Title");
const CFStringRef kCGPDFOutlineChildren = CFSTR("Children");
const CFStringRef kCGPDFOutlineDestination = CFSTR("Destination");
const CFStringRef kCGPDFOutlineDestinationRect = CFSTR("DestinationRect");

CGContextRef CGPDFContextCreate(CGDataConsumerRef consumer,
                                const CGRect *mediaBox,
                                CFDictionaryRef auxiliaryInfo)
{
    NSDictionary *info = (NSDictionary *)auxiliaryInfo;
    if (requestsEncryption(info))
        return NULL;
    const CFStringRef publicKeys[] = {kCGPDFContextTitle, kCGPDFContextAuthor, kCGPDFContextCreator};
    const NSString *backendKeys[] = {kO2PDFContextTitle, kO2PDFContextAuthor, kO2PDFContextCreator};
    NSMutableDictionary *translated = nil;
    for (unsigned i = 0; i < 3; i++) {
        id value = [info objectForKey:(id)publicKeys[i]];
        if (value) {
            if (!translated)
                translated = [[info mutableCopy] autorelease];
            [translated setObject:value forKey:(id)backendKeys[i]];
        }
    }
    if (translated)
        info = translated;
    return (CGContextRef)[[O2PDFContext alloc]
            initWithConsumer: (O2DataConsumer*)consumer
                    mediaBox: mediaBox
               auxiliaryInfo: info];
}

CGContextRef CGPDFContextCreateWithURL(CFURLRef url,
                                       const CGRect *mediaBox,
                                       CFDictionaryRef auxiliaryInfo)
{
    if (!url)
        return NULL;
    // Refuse before the consumer exists: creating it creates the file, replacing
    // the contents of any file already at the URL.
    if (requestsEncryption((NSDictionary *)auxiliaryInfo))
        return NULL;
    // The consumer is the lower layer that owns the file: it creates the file
    // and fails for a URL that is not a file URL or cannot be written.
    CGDataConsumerRef consumer = CGDataConsumerCreateWithURL(url);
    if (!consumer)
        return NULL;
    CGContextRef context = CGPDFContextCreate(consumer, mediaBox, auxiliaryInfo);
    CGDataConsumerRelease(consumer);
    return context;
}

COREGRAPHICS_EXPORT void CGPDFContextClose(CGContextRef self) {
    [self close];
}

void CGPDFContextBeginPage(CGContextRef self, CFDictionaryRef pageInfo) {
    [(O2PDFContext *)self beginPDFPage:(NSDictionary *)pageInfo];
}

void CGPDFContextEndPage(CGContextRef self) {
    O2ContextEndPage((O2ContextRef)self);
}

// The outline is kept by the context and written into the file when the context is closed (the PDF has
// /Outlines then; documents made without an outline have none). Observed on macOS 26.7.3 and Mac OS X
// 10.14.4: after setting any dictionary, even an empty one, the generated document answers
// CGPDFDocumentGetOutline with a non-NULL dictionary of one key. Test: coregraphics-pdf-outline.
// Limitation: only the titles and the nesting of kCGPDFOutlineChildren are written; the destinations are
// not (the layout of a destination dictionary was not observed).
// A NULL outline, or a context that is not a PDF context, is ignored.
void CGPDFContextSetOutline(CGContextRef context, CFDictionaryRef outline) {
    if (context == NULL || ![(id)context isKindOfClass: [O2PDFContext class]])
        return;
    [(O2PDFContext *)context setOutline: (NSDictionary *)outline];
}
