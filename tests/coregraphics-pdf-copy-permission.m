/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CGPDFDocumentAllowsCopying: true for a document without encryption, false
 * for one that has an Encrypt entry the reader cannot unlock. A null Encrypt
 * value (direct, indirect or an undefined reference) means the entry is absent
 * (PDF 1.7, 3.2.6 and 3.2.9). The documents are generated here; the Encrypt
 * dictionaries are never decrypted, only detected.
 */
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <stdio.h>

static NSData *documentData(NSString *encryptEntry, NSString *extraObject)
{
	NSMutableArray *objects = [NSMutableArray arrayWithObjects:
		@"<< /Type /Catalog /Pages 2 0 R >>",
		@"<< /Type /Pages /Kids [] /Count 0 >>", nil];
	if (extraObject)
		[objects addObject:extraObject]; /* object 3 */
	NSMutableData *data = [NSMutableData dataWithData:[@"%PDF-1.4\n" dataUsingEncoding:NSASCIIStringEncoding]];
	NSMutableArray *offsets = [NSMutableArray array];
	for (NSUInteger i = 0; i < [objects count]; i++) {
		[offsets addObject:@([data length])];
		[data appendData:[[NSString stringWithFormat:@"%lu 0 obj\n%@\nendobj\n", (unsigned long)i + 1, objects[i]]
			dataUsingEncoding:NSASCIIStringEncoding]];
	}
	NSUInteger xref = [data length];
	[data appendData:[[NSString stringWithFormat:@"xref\n0 %lu\n0000000000 65535 f \n", (unsigned long)[objects count] + 1]
		dataUsingEncoding:NSASCIIStringEncoding]];
	for (NSNumber *offset in offsets)
		[data appendData:[[NSString stringWithFormat:@"%010lu 00000 n \n", (unsigned long)[offset unsignedLongValue]]
			dataUsingEncoding:NSASCIIStringEncoding]];
	[data appendData:[[NSString stringWithFormat:@"trailer\n<< /Size %lu /Root 1 0 R %@ >>\nstartxref\n%lu\n%%%%EOF\n",
		(unsigned long)[objects count] + 1, encryptEntry, (unsigned long)xref] dataUsingEncoding:NSASCIIStringEncoding]];
	return data;
}

int main(void)
{
	NSString *standard = @"<< /Filter /Standard /V 1 /R 2 /Length 40 /P %d "
		"/O <0000000000000000000000000000000000000000000000000000000000000000> "
		"/U <0000000000000000000000000000000000000000000000000000000000000000> >>";
	struct { const char *name; NSString *trailer; NSString *object; bool allows; } cases[] = {
		{ "plain", @"", nil, true },
		{ "direct-null", @"/Encrypt null", nil, true },
		{ "indirect-null", @"/Encrypt 3 0 R", @"null", true },
		{ "undefined-reference", @"/Encrypt 9 0 R", nil, true },
		{ "encrypted-restricted", @"/Encrypt 3 0 R", [NSString stringWithFormat:standard, -3904], false },
		{ "encrypted-permitted", @"/Encrypt 3 0 R", [NSString stringWithFormat:standard, -4], false },
		{ "wrong-type", @"/Encrypt 3 0 R", @"42", false },
	};
	bool (*allowsCopying)(CGPDFDocumentRef) = dlsym(RTLD_DEFAULT, "CGPDFDocumentAllowsCopying");
	if (!allowsCopying) {
		printf("FAIL: CGPDFDocumentAllowsCopying is not exported\n");
		return 1;
	}
	int failures = 0;
	@autoreleasepool {
		for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
			CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)documentData(cases[i].trailer, cases[i].object));
			CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
			CGDataProviderRelease(provider);
			if (!document) {
				printf("FAIL %s: document not created\n", cases[i].name);
				failures++;
				continue;
			}
			if (allowsCopying(document) != cases[i].allows) {
				printf("FAIL %s: allowsCopying %d, expected %d\n", cases[i].name, allowsCopying(document), cases[i].allows);
				failures++;
			}
			CGPDFDocumentRelease(document);
		}
	}
	printf(failures ? "FAILED %d\n" : "PASS\n", failures);
	return failures != 0;
}
