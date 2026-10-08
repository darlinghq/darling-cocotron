#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

// A bitmap context created with kCGImageAlphaPremultipliedLast and no byte-order flag
// stores R, G, B, A bytes in memory (apps upload such bitmaps as RGBA textures).
// The colour is not palindromic: an all-red pixel reads the same in either order.
int main(void) {
 unsigned char pixel[4] = {0, 0, 0, 0};
 CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
 CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
 CGContextSetRGBFillColor(context, 1.0, 128.0 / 255.0, 64.0 / 255.0, 1.0);
 CGContextFillRect(context, CGRectMake(0, 0, 1, 1));
 printf("fill bytes %u %u %u %u (expected 255 128 64 255 as R G B A)\n", pixel[0], pixel[1], pixel[2], pixel[3]);
 return !(pixel[0] == 255 && pixel[1] == 128 && pixel[2] == 64 && pixel[3] == 255);
}
