#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>
#include <dlfcn.h>
static unsigned failures;
static void expect(BOOL value,const char *label) { printf("%s %s\n",value?"PASS":"FAIL",label);if(!value)++failures; }
int main(void) { @autoreleasepool {
 CTFontRef font=CTFontCreateWithName(CFSTR("DejaVu Sans"),20,NULL);
 const void *keys[]={kCTFontAttributeName,kCTForegroundColorFromContextAttributeName};const void *values[]={font,kCFBooleanTrue};
 CFDictionaryRef attributes=CFDictionaryCreate(NULL,keys,values,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 CFAttributedStringRef string=CFAttributedStringCreate(NULL,CFSTR("Dodge Danger"),attributes);
 CTLineRef line=CTLineCreateWithAttributedString(string);CGFloat ascent,descent,leading;double width=CTLineGetTypographicBounds(line,&ascent,&descent,&leading);
 expect(width>0 && ascent>0,"existing line metric control is nonzero");
 CFTypeID (*frameTypeID)(void)=dlsym(RTLD_DEFAULT,"CTFrameGetTypeID");
 CTFramesetterRef fs=CTFramesetterCreateWithAttributedString(string);expect(fs!=NULL,"framesetter creation returns owned object");
 if(fs) {
  CFRange fit={-1,-1};CGSize size=CTFramesetterSuggestFrameSizeWithConstraints(fs,CFRangeMake(0,0),NULL,CGSizeMake(CGFLOAT_MAX,CGFLOAT_MAX),&fit);
  expect(size.width>=width && size.width<width+1 && size.height>=ascent+descent,"unconstrained frame fits measured single line");
  expect(fit.location==0 && fit.length==12,"fit range includes entire string");
  CGPathRef path=CGPathCreateWithRect(CGRectMake(0,0,ceil(size.width),ceil(size.height)),NULL);CTFrameRef frame=CTFramesetterCreateFrame(fs,CFRangeMake(0,0),path,NULL);
  expect(frame!=NULL,"frame creation returns owned object");
  if(frame) {
   expect(CFArrayGetCount(CTFrameGetLines(frame))==1,"single line frame exposes one line");
   CFRange visible=CTFrameGetVisibleStringRange(frame);expect(visible.location==0 && visible.length==12,"frame exposes fitted range");
   CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(NULL,ceil(size.width),ceil(size.height),8,ceil(size.width)*4,rgb,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(rgb);
   expect(context!=NULL,"positive measured size creates bitmap");
   if(context) { CGContextSetRGBFillColor(context,1,1,1,1);CTFrameDraw(frame,context);unsigned char *bytes=CGBitmapContextGetData(context);size_t count=CGBitmapContextGetBytesPerRow(context)*CGBitmapContextGetHeight(context),nonzero=0;for(size_t i=0;i<count;++i)if(bytes[i])++nonzero;expect(nonzero>0,"frame draw writes actual glyph pixels");CGContextRelease(context); }
   CFRelease(frame);
  }
  CGPathRelease(path);
  expect(CFGetTypeID(fs)==CTFramesetterGetTypeID() && frameTypeID && CTFramesetterGetTypeID()!=frameTypeID(),"framesetter has distinct registered CF type");
  CFAttributedStringRef paragraph=CFAttributedStringCreate(NULL,CFSTR("Dodge Danger Dodge Danger"),attributes);
  CTFramesetterRef wrapped=CTFramesetterCreateWithAttributedString(paragraph);CFRelease(paragraph);
  CGFloat rowHeight=ascent+descent+leading;
  CFRange limitedFit;
  CGSize limited=CTFramesetterSuggestFrameSizeWithConstraints(wrapped,CFRangeMake(0,0),NULL,CGSizeMake(width+1,rowHeight+0.1),&limitedFit);
  expect(limitedFit.length>0 && limitedFit.length<25 && limited.height<=rowHeight+0.1,"finite height reports partial fitted range");
  CGMutablePathRef offsetPath=CGPathCreateMutable();CGPathAddRect(offsetPath,NULL,CGRectMake(17,23,width+1,rowHeight*3));
  CFMutableDictionaryRef empty=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
  CTFrameRef wrappedFrame=CTFramesetterCreateFrame(wrapped,CFRangeMake(6,0),offsetPath,empty);
  CGPathAddRect(offsetPath,NULL,CGRectMake(200,200,2,2));CGPathRelease(offsetPath);CFRelease(empty);CFRelease(wrapped);
  expect(wrappedFrame!=NULL,"frame survives released framesetter and copied inputs");
  if(wrappedFrame) {
   expect(frameTypeID && CFGetTypeID(wrappedFrame)==frameTypeID(),"frame has registered CF type");
   CGRect rect;expect(CGPathIsRect(CTFrameGetPath(wrappedFrame),&rect) && rect.origin.x==17 && rect.origin.y==23,"frame owns unchanged rectangular path copy");
   expect(CTFrameGetFrameAttributes(wrappedFrame)!=NULL && CFDictionaryGetCount(CTFrameGetFrameAttributes(wrappedFrame))==0,"frame retains copied empty attributes");
   CFArrayRef lines=CTFrameGetLines(wrappedFrame);CFIndex count=CFArrayGetCount(lines);expect(count>=2,"constrained width wraps into multiple lines");
   CGPoint origins[8];CTFrameGetLineOrigins(wrappedFrame,CFRangeMake(0,0),origins);
   expect(origins[0].x==0 && origins[0].y>0 && (count<2 || origins[1].y<origins[0].y),"line origins are path-relative descending baselines");
   expect(CTLineGetStringRange(CFArrayGetValueAtIndex(lines,0)).location==6,"frame lines retain original source indices");
   CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();CGContextRef canvas=CGBitmapContextCreate(NULL,256,160,8,1024,rgb,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(rgb);
   if(canvas) {
    CGContextSetRGBFillColor(canvas,1,1,1,1);CTFrameDraw(wrappedFrame,canvas);
    unsigned char *pixels=CGBitmapContextGetData(canvas);size_t drawn=0,outside=0;
    for(size_t y=0;y<160;++y)for(size_t x=0;x<256;++x)if(pixels[y*1024+x*4] || pixels[y*1024+x*4+1] || pixels[y*1024+x*4+2] || pixels[y*1024+x*4+3]) { ++drawn;if(x<17 || x>=ceil(17+width+1))++outside; }
    printf("pixels drawn=%zu outside=%zu\n",drawn,outside);
    expect(drawn>0 && outside==0,"translated frame draws within path horizontal bounds");CGContextRelease(canvas);
   } else expect(NO,"translated frame bitmap creation");
   CFRelease(wrappedFrame);
  }
  CFRelease(fs);
 }
 CFRelease(line);CFRelease(string);CFRelease(attributes);CFRelease(font);printf("RESULT failures=%u\n",failures);return failures?1:0;
} }
