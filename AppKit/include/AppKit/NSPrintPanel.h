#import <AppKit/AppKitExport.h>
#import <Foundation/NSObject.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSArray, NSMutableArray, NSMutableDictionary, NSViewController;

typedef NS_OPTIONS(NSInteger, NSPrintPanelOptions) {

    NSPrintPanelShowsCopies = 1 << 0,
    NSPrintPanelShowsPageRange = 1 << 1,
    NSPrintPanelShowsPaperSize = 1 << 2,
    NSPrintPanelShowsOrientation = 1 << 3,
    NSPrintPanelShowsScaling = 1 << 4,
    NSPrintPanelShowsPrintSelection = 1 << 5,
    NSPrintPanelShowsPageSetupAccessory = 1 << 8,
    NSPrintPanelShowsPreview = 1 << 17
};

typedef NS_ENUM(NSInteger, NSPrintPanelResult) {
    NSPrintPanelResultCancelled = 0,
    NSPrintPanelResultPrinted,
};

@interface NSPrintPanel : NSObject {
    NSMutableDictionary *_attributes;
    NSInteger _options;
    NSMutableArray *_accessoryControllers;
    NS_LEGACY_IVAR_PAD(_NSPrintPanelReserved, 232)
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
