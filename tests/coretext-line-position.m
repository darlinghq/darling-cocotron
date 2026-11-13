#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <stdio.h>
int main(void) { @autoreleasepool {
 CTFontRef font=CTFontCreateWithName(CFSTR("DejaVu Sans"),20,NULL);
 const void *keys[]={kCTFontAttributeName,kCTForegroundColorFromContextAttributeName};const void *values[]={font,kCFBooleanTrue};
 CFDictionaryRef attrs=CFDictionaryCreate(NULL,keys,values,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 CFMutableAttributedStringRef text=CFAttributedStringCreateMutable(NULL,0);CFAttributedStringReplaceString(text,CFRangeMake(0,0),CFSTR("Dodge Danger"));CFAttributedStringSetAttributes(text,CFRangeMake(0,12),attrs,true);
 CTFontRef second=CTFontCreateWithName(CFSTR("DejaVu Sans"),18,NULL);CFAttributedStringSetAttribute(text,CFRangeMake(6,6),kCTFontAttributeName,second);CFRelease(second);
 CTLineRef line=CTLineCreateWithAttributedString(text);
 CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();CGContextRef ctx=CGBitmapContextCreate(NULL,240,100,8,960,rgb,kCGImageAlphaPremultipliedLast);
 CGContextSetRGBFillColor(ctx,1,1,1,1);CGContextSetTextPosition(ctx,40,45);CTLineDraw(line,ctx);
 unsigned char *bytes=CGBitmapContextGetData(ctx);size_t pixels=0,left=0;
 for(size_t y=0;y<100;++y)for(size_t x=0;x<240;++x)if(bytes[y*960+x*4] || bytes[y*960+x*4+1] || bytes[y*960+x*4+2] || bytes[y*960+x*4+3]) { ++pixels;if(x<40)++left; }
 CGContextRef control=CGBitmapContextCreate(NULL,240,100,8,960,rgb,kCGImageAlphaPremultipliedLast);CGContextSetRGBFillColor(control,1,1,1,1);CGContextSetTextPosition(control,0,45);CTLineDraw(line,control);
 unsigned char *reference=CGBitmapContextGetData(control);size_t mismatch=0;
 for(size_t y=0;y<100;++y)for(size_t x=0;x<200;++x)for(size_t c=0;c<4;++c)if(reference[y*960+x*4+c]!=bytes[y*960+(x+40)*4+c])++mismatch;
 BOOL pass=pixels>0 && left==0 && mismatch==0 && CFArrayGetCount(CTLineGetGlyphRuns(line))==2;printf("translation mismatches=%zu runs=%ld\n",mismatch,(long)CFArrayGetCount(CTLineGetGlyphRuns(line)));CGContextRelease(control);printf("%s translated line pixels=%zu left=%zu\n",pass?"PASS":"FAIL",pixels,left);
 CGContextRelease(ctx);CGColorSpaceRelease(rgb);CFRelease(line);CFRelease(text);CFRelease(attrs);CFRelease(font);return pass?0:1;
} }
