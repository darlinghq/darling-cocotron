#import <AppKit/AppKitExport.h>
#import <Foundation/NSObject.h>

@class NSArray, NSMutableArray, NSMutableDictionary, NSViewController;

enum {

    NSPrintPanelShowsCopies = 1 << 0,
    NSPrintPanelShowsPageRange = 1 << 1,
    NSPrintPanelShowsPaperSize = 1 << 2,
    NSPrintPanelShowsOrientation = 1 << 3,
    NSPrintPanelShowsScaling = 1 << 4,
    NSPrintPanelShowsPrintSelection = 1 << 5,
    NSPrintPanelShowsPageSetupAccessory = 1 << 8,
    NSPrintPanelShowsPreview = 1 << 17
};

typedef NSInteger NSPrintPanelOptions;

@interface NSPrintPanel : NSObject {
    NSMutableDictionary *_attributes;
    NSInteger _options;
    NSMutableArray *_accessoryControllers;
}

+ (NSPrintPanel *) printPanel;

- (void) setOptions: (NSPrintPanelOptions) options;
- (NSPrintPanelOptions) options;

- (int) runModal;

- (void) updateFromPrintInfo;
- (void) finalWritePrintInfo;

// Stored only: the print panel doesn't show accessory views.
- (NSArray *) accessoryControllers;
- (void) addAccessoryController: (NSViewController *) controller;
- (void) removeAccessoryController: (NSViewController *) controller;

@end

@protocol NSPrintPanelAccessorizing

// TODO

@end

APPKIT_EXPORT NSString *const NSPrintPanelAccessorySummaryItemNameKey;
APPKIT_EXPORT NSString *const NSPrintPanelAccessorySummaryItemDescriptionKey;
