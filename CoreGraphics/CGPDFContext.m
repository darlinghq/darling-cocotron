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

// GUESS: the documentation pages of these keys (kCGPDFContextSubject,
// kCGPDFContextCreatePDFA, kCGPDFContextOutputIntent, kCGPDFXInfo,
// kCGPDFXOutputConditionIdentifier, kCGPDFXOutputIntentSubtype,
// kCGPDFXDestinationOutputProfile) do not state the string value of the
// constant, so each value is the symbol name. The sibling keys above are mixed:
// Title, Author and the like use the symbol name, the page box keys use the
// PDF dictionary key name. An alternative guess for the four kCGPDFX* keys is
// the PDF key names of the output intent dictionary (/S,
// /OutputConditionIdentifier, /Info, /DestOutputProfile): the
// kCGPDFContextOutputIntent page says that dictionary's keys and values must
// match section 9.10.4 of the PDF 1.4 specification. Nothing in the tree
// reads these strings. Replace with the values printed on a real Mac.
// The keys are declared so callers can bind them; CGPDFContextCreate accepts
// them and does not write them: the subject (like the keywords) is dropped
// because only the title, author and creator reach the file, and the PDF/A and
// PDF/X keys have no effect.
const CFStringRef kCGPDFContextSubject = CFSTR("kCGPDFContextSubject");
const CFStringRef kCGPDFContextCreatePDFA = CFSTR("kCGPDFContextCreatePDFA");
const CFStringRef kCGPDFContextOutputIntent = CFSTR("kCGPDFContextOutputIntent");
const CFStringRef kCGPDFXInfo = CFSTR("kCGPDFXInfo");
const CFStringRef kCGPDFXOutputConditionIdentifier = CFSTR("kCGPDFXOutputConditionIdentifier");
const CFStringRef kCGPDFXOutputIntentSubtype = CFSTR("kCGPDFXOutputIntentSubtype");
const CFStringRef kCGPDFXDestinationOutputProfile = CFSTR("kCGPDFXDestinationOutputProfile");

CGContextRef CGPDFContextCreate(CGDataConsumerRef consumer,
                                const CGRect *mediaBox,
                                CFDictionaryRef auxiliaryInfo)
{
    NSDictionary *info = (NSDictionary *)auxiliaryInfo;
    // The PDF writer cannot encrypt yet. Refuse a request for encryption
    // instead of writing an unprotected file the caller believes is protected.
    if ([info objectForKey:(id)kCGPDFContextUserPassword] ||
        [info objectForKey:(id)kCGPDFContextOwnerPassword] ||
        [info objectForKey:(id)kCGPDFContextEncryptionKeyLength])
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

COREGRAPHICS_EXPORT void CGPDFContextClose(CGContextRef self) {
    [self close];
}

void CGPDFContextBeginPage(CGContextRef self, CFDictionaryRef pageInfo) {
    [(O2PDFContext *)self beginPDFPage:(NSDictionary *)pageInfo];
}

void CGPDFContextEndPage(CGContextRef self) {
    O2ContextEndPage((O2ContextRef)self);
}

// GUESS: limitation, not an outline writer. The documentation page gives the
// signature (the outline may be NULL) but not the dictionary layout, and the
// keys of that layout are separate constants that are not declared here. The
// function returns nothing, so the writer has no way to report this: the
// outline is accepted and NOT written, and the PDF has no /Outlines entry.
void CGPDFContextSetOutline(CGContextRef context, CFDictionaryRef outline) {
    (void)context;
    (void)outline;
}
