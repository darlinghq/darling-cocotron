#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
static unsigned failures;
static void expect(BOOL value,const char *label) { printf("%s %s\n",value?"PASS":"FAIL",label);if(!value)++failures; }
int main(void) { @autoreleasepool {
 CTFontRef font=CTFontCreateWithName(CFSTR("DejaVu Sans"),20,NULL);const void *key=kCTFontAttributeName,*value=font;
 CFDictionaryRef attributes=CFDictionaryCreate(NULL,&key,&value,1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 CFAttributedStringRef string=CFAttributedStringCreate(NULL,CFSTR("012 hello ABC"),attributes);CTTypesetterRef ts=CTTypesetterCreateWithAttributedString(string);CTLineRef full=CTLineCreateWithAttributedString(string);CFRange whole=CTLineGetStringRange(full);expect(whole.location==0 && whole.length==13,"full-string line range remains unchanged");CFRelease(full);CFRelease(string);CFRelease(attributes);CFRelease(font);
 CTLineRef line=CTTypesetterCreateLine(ts,CFRangeMake(4,5));expect(line!=NULL,"explicit subrange creates line");
 if(line) {
  CFRange range=CTLineGetStringRange(line);expect(range.location==4 && range.length==5,"line retains original source range");
  CFArrayRef runs=CTLineGetGlyphRuns(line);BOOL global=CFArrayGetCount(runs)>0;
  for(CFIndex i=0;i<CFArrayGetCount(runs);++i) { CTRunRef run=CFArrayGetValueAtIndex(runs,i);CFRange r=CTRunGetStringRange(run);if(r.location<4 || r.location+r.length>9)global=NO;const CFIndex *indices=CTRunGetStringIndicesPtr(run);for(CFIndex j=0;j<CTRunGetGlyphCount(run);++j)if(indices[j]<4 || indices[j]>=9)global=NO; }
  expect(global,"run ranges and glyph indices retain global source positions");
  expect(CTLineGetStringIndexForPosition(line,CGPointMake(10000,0))==9,"past-end hit test returns original range end");CFRelease(line);
 }
 line=CTTypesetterCreateLine(ts,CFRangeMake(10,0));if(line){CFRange r=CTLineGetStringRange(line);expect(r.location==10 && r.length==3,"zero length means remaining range from start");CFRelease(line);}else expect(NO,"zero length creates remaining line");
 line=CTTypesetterCreateLine(ts,CFRangeMake(-1,3));expect(!line,"negative range is rejected");if(line)CFRelease(line);
 line=CTTypesetterCreateLine(ts,CFRangeMake(12,5));expect(!line,"out of bounds range is rejected");if(line)CFRelease(line);
 line=CTTypesetterCreateLineWithOffset(ts,CFRangeMake(4,5),0);if(line){CFRange r=CTLineGetStringRange(line);expect(r.location==4 && r.length==5,"zero offset preserves original source range");CFRelease(line);}else expect(NO,"zero offset line exists");
 line=CTTypesetterCreateLine(ts,CFRangeMake(13,0));if(line){CFRange r=CTLineGetStringRange(line);expect(r.location==13 && r.length==0 && CTLineGetGlyphCount(line)==0,"end range creates empty line");CFRelease(line);}else expect(NO,"empty end line exists");
 line=CTTypesetterCreateLine(ts,CFRangeMake(4,-1));expect(!line,"negative length is rejected");if(line)CFRelease(line);
 CFRelease(ts);printf("RESULT failures=%u\n",failures);return failures?1:0;
} }
