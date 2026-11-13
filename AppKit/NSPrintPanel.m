#import <AppKit/NSDisplay.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSPrintPanel.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>

@implementation NSPrintPanel

+ (NSPrintPanel *) printPanel {
    return [[[self alloc] init] autorelease];
}

- (void) dealloc {
    [_attributes release];
    [_accessoryControllers release];
    [super dealloc];
}

- (NSArray *) accessoryControllers {
    return _accessoryControllers ? [[_accessoryControllers copy] autorelease]
                                 : [NSArray array];
}

- (void) addAccessoryController: (NSViewController *) controller {
    if (controller == nil)
        return;
    if (_accessoryControllers == nil)
        _accessoryControllers = [[NSMutableArray alloc] init];
    if ([_accessoryControllers indexOfObjectIdenticalTo: controller] == NSNotFound)
        [_accessoryControllers addObject: controller];
}

- (void) removeAccessoryController: (NSViewController *) controller {
    [_accessoryControllers removeObjectIdenticalTo: controller];
}

- (void) setOptions: (NSPrintPanelOptions) options {
    _options = options;
}

- (NSPrintPanelOptions) options {
    return _options;
}

- (int) runModal {
    int result;

    [self updateFromPrintInfo];
    result = [[NSDisplay currentDisplay]
            runModalPrintPanelWithPrintInfoDictionary: _attributes];
    if (result == NSOKButton)
        [self finalWritePrintInfo];

    return result;
}

- (void) updateFromPrintInfo {
    NSDictionary *source =
            [[[NSPrintOperation currentOperation] printInfo] dictionary];

    [_attributes release];
    _attributes = [source mutableCopy];
}

- (void) finalWritePrintInfo {
    NSMutableDictionary *destination =
            [[[NSPrintOperation currentOperation] printInfo] dictionary];

    [destination addEntriesFromDictionary: _attributes];
}

@end

NSString *const NSPrintPanelAccessorySummaryItemNameKey =
        @"NSPrintPanelAccessorySummaryItemName";
NSString *const NSPrintPanelAccessorySummaryItemDescriptionKey =
        @"NSPrintPanelAccessorySummaryItemDescription";
