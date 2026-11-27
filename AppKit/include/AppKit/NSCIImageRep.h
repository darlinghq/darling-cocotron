#import <AppKit/NSImageRep.h>
#import <QuartzCore/CoreImage.h>

@class NSBitmapImageRep;

@interface CIImage (CIImageRepAdditions)
- initWithBitmapImageRep: (NSBitmapImageRep *) bitmapImageRep;
@end
