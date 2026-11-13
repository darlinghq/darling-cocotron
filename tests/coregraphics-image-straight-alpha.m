#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
static void pixel(unsigned alpha, BOOL little, BOOL premultiplied) {
    unsigned red=premultiplied?alpha:255;
    unsigned char bytes[4];
    if(little) { bytes[0]=alpha; bytes[1]=0; bytes[2]=0; bytes[3]=red; }
    else { bytes[0]=red; bytes[1]=0; bytes[2]=0; bytes[3]=alpha; }
    unsigned char original[4]; memcpy(original,bytes,4);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,bytes,4,NULL);
    CGImageRef image=CGImageCreate(1,1,8,32,4,space,
        (premultiplied?kCGImageAlphaPremultipliedLast:kCGImageAlphaLast) |
        (little?kCGBitmapByteOrder32Little:kCGBitmapByteOrder32Big),provider,NULL,NO,kCGRenderingIntentDefault);
    unsigned char output[4]={0};
    CGContextRef context=CGBitmapContextCreate(output,1,1,8,4,space,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
    CGContextSetInterpolationQuality(context,kCGInterpolationNone);
    CGContextDrawImage(context,CGRectMake(0,0,1,1),image);
    BOOL ok=output[0]==0 && output[1]==0 && output[2]==alpha && output[3]==alpha && !memcmp(original,bytes,4);
    printf("%s alpha=%u endian=%s premultiplied=%d result=%u,%u,%u,%u source-unchanged=%d\n",ok?"PASS":"FAIL",alpha,little?"little":"big",premultiplied,output[0],output[1],output[2],output[3],!memcmp(original,bytes,4));
    failures+=!ok;
    CGContextRelease(context); CGImageRelease(image); CGDataProviderRelease(provider); CGColorSpaceRelease(space);
}
int main(void) {
 @autoreleasepool {
  unsigned alphas[]={0,1,128,254,255};
  for(int premult=0;premult<2;premult++) for(int little=0;little<2;little++) for(int i=0;i<5;i++) pixel(alphas[i],little,premult);
 }
 printf("failures=%d\n",failures); return failures?1:0;
}
