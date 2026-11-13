#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
static unsigned failures;
static void expect(BOOL value,const char *label) { printf("%s %s\n",value?"PASS":"FAIL",label);if(!value)++failures; }
static CTTypesetterRef typesetter(CFStringRef text,CTFontRef font) { const void *key=kCTFontAttributeName,*value=font;CFDictionaryRef attributes=CFDictionaryCreate(NULL,&key,&value,1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);CFAttributedStringRef string=CFAttributedStringCreate(NULL,text,attributes);CTTypesetterRef result=CTTypesetterCreateWithAttributedString(string);CFRelease(string);CFRelease(attributes);return result; }
int main(void) { @autoreleasepool {
 CTFontRef font=CTFontCreateWithName(CFSTR("DejaVu Sans"),20,NULL);
 CTTypesetterRef ts=typesetter(CFSTR("one two three"),font);
 CTLineRef first=CTTypesetterCreateLine(ts,CFRangeMake(0,4));double width=CTLineGetTypographicBounds(first,NULL,NULL,NULL)+1;CFRelease(first);
 CFIndex count=CTTypesetterSuggestLineBreak(ts,0,width);
 expect(count==4,"word break respects measured width");
 expect(CTTypesetterSuggestLineBreakWithOffset(ts,0,width,0)==4,"zero-offset line break matches documented API");
 expect(CTTypesetterSuggestLineBreak(ts,0,0)==0,"zero width fits no characters");
 expect(CTTypesetterSuggestLineBreak(ts,13,width)==0,"end of string has no break");
 expect(CTTypesetterSuggestLineBreak(ts,-1,width)==0,"negative start is rejected");
 CFRelease(ts);
 ts=typesetter(CFSTR("one\ntwo"),font);
 expect(CTTypesetterSuggestLineBreak(ts,0,1000)==4,"mandatory newline ends first line");
 expect(CTTypesetterSuggestLineBreak(ts,4,1000)==3,"break starts at requested offset");CFRelease(ts);
 ts=typesetter(CFSTR("e\u0301XYZ"),font);first=CTTypesetterCreateLine(ts,CFRangeMake(0,2));width=CTLineGetTypographicBounds(first,NULL,NULL,NULL)+1;CFRelease(first);
 expect(CTTypesetterSuggestClusterBreak(ts,0,width)==2,"cluster break preserves combining sequence");
 expect(CTTypesetterSuggestClusterBreakWithOffset(ts,0,width,0)==2,"zero-offset cluster break matches documented API");CFRelease(ts);
 ts=typesetter(CFSTR("one\r\ntwo"),font);
 expect(CTTypesetterSuggestLineBreak(ts,0,1000)==5,"CRLF is one mandatory break");CFRelease(ts);
 ts=typesetter(CFSTR("\U0001F600XYZ"),font);first=CTTypesetterCreateLine(ts,CFRangeMake(0,2));width=CTLineGetTypographicBounds(first,NULL,NULL,NULL)+1;CFRelease(first);
 expect(CTTypesetterSuggestClusterBreak(ts,0,width)==2,"cluster break preserves surrogate pair");CFRelease(ts);
 ts=typesetter(CFSTR("abcdefghijk"),font);first=CTTypesetterCreateLine(ts,CFRangeMake(0,3));width=CTLineGetTypographicBounds(first,NULL,NULL,NULL)+1;CFRelease(first);
 expect(CTTypesetterSuggestLineBreak(ts,0,width)==3,"long word uses fitting cluster break");CFRelease(ts);
 ts=typesetter(CFSTR(""),font);expect(CTTypesetterSuggestLineBreak(ts,0,100)==0,"empty string has no break");CFRelease(ts);
 CFRelease(font);printf("RESULT failures=%u\n",failures);return failures?1:0;
} }
