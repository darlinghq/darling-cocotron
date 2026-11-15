#import <AppKit/AppKitExport.h>
#import <AppKit/NSControl.h>
#import <Foundation/NSString.h>

APPKIT_EXPORT NSString *const NSRuleEditorRowsDidChangeNotification;

typedef NS_ENUM(NSUInteger, NSRuleEditorNestingMode) {
    NSRuleEditorNestingModeSingle,
    NSRuleEditorNestingModeList,
    NSRuleEditorNestingModeCompound,
    NSRuleEditorNestingModeSimple,
};

typedef NS_ENUM(NSUInteger, NSRuleEditorRowType) {
    NSRuleEditorRowTypeSimple,
    NSRuleEditorRowTypeCompound,
};

@interface NSRuleEditor : NSControl <NSCoding>

@end

@protocol NSRuleEditorDelegate <NSObject>

// TODO

@end
