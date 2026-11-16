#import <Foundation/NSObject.h>
#import <AppKit/AppKitIvarLayout.h>

typedef NS_ENUM(NSInteger, NSTextFinderAction) {
    NSTextFinderActionShowFindInterface = 1,
    NSTextFinderActionNextMatch = 2,
    NSTextFinderActionPreviousMatch = 3,
    NSTextFinderActionReplaceAll = 4,
    NSTextFinderActionReplace = 5,
    NSTextFinderActionReplaceAndFind = 6,
    NSTextFinderActionSetSearchString = 7,
    NSTextFinderActionReplaceAllInSelection = 8,
    NSTextFinderActionSelectAll = 9,
    NSTextFinderActionSelectAllInSelection = 10,
    NSTextFinderActionHideFindInterface = 11,
    NSTextFinderActionShowReplaceInterface = 12,
    NSTextFinderActionHideReplaceInterface = 13,
};

typedef NS_ENUM(NSInteger, NSTextFinderMatchingType) {
    NSTextFinderMatchingTypeContains = 0,
    NSTextFinderMatchingTypeStartsWith = 1,
    NSTextFinderMatchingTypeFullWord = 2,
    NSTextFinderMatchingTypeEndsWith = 3,
};

@protocol NSTextFinderBarContainer <NSObject>

@end

@protocol NSTextFinderClient <NSObject>

@end

@interface NSTextFinder : NSObject {
    NS_LEGACY_IVAR_PAD(_NSTextFinderReserved, 24)
}

@end
