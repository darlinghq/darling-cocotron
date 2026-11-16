#import <Foundation/Foundation.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSViewController.h>

typedef NS_ENUM(NSInteger, NSPageControllerTransitionStyle) {
    NSPageControllerTransitionStyleStackHistory,
    NSPageControllerTransitionStyleStackBook,
    NSPageControllerTransitionStyleHorizontalStrip,
};

@interface NSPageController : NSViewController {
    NS_LEGACY_IVAR_PAD(_NSPageControllerReserved, 68)
}

@end

@protocol NSPageControllerDelegate <NSObject>

@end
