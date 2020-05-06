#import <CoreGraphics/CGGeometry.h>
#import <Foundation/Foundation.h>

@interface CGSubWindow : NSObject

- (void *) nativeWindow;

- (void) show;
- (void) hide;

- (void) setFrame: (CGRect) frame;

@end
