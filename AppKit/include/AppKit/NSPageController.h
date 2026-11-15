#import <Foundation/Foundation.h>
#import <AppKit/NSViewController.h>

typedef NS_ENUM(NSInteger, NSPageControllerTransitionStyle) {
    NSPageControllerTransitionStyleStackHistory,
    NSPageControllerTransitionStyleStackBook,
    NSPageControllerTransitionStyleHorizontalStrip,
};

@interface NSPageController : NSViewController

@end

@protocol NSPageControllerDelegate <NSObject>

@end
