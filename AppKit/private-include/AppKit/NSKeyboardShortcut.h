#import <Foundation/NSObject.h>

@class NSString;

// A key equivalent with its modifiers, as shown to the user (macOS AppKit SPI).
@interface NSKeyboardShortcut : NSObject <NSCopying> {
    NSString *_keyEquivalent;
    NSUInteger _modifierMask;
}
+ (instancetype)shortcutWithKeyEquivalent:(NSString *)keyEquivalent modifierMask:(NSUInteger)modifierMask;
- (instancetype)initWithKeyEquivalent:(NSString *)keyEquivalent modifierMask:(NSUInteger)modifierMask;
@property (readonly) NSString *keyEquivalent;
@property (readonly) NSUInteger modifierMask;
@property (readonly, getter=isEmpty) BOOL empty;
@property (readonly) BOOL isFunctionKey;
@property (readonly) NSString *localizedDisplayName;
@property (readonly) NSString *localizedKeyEquivalentDisplayName;
@property (readonly) NSString *localizedModifierMaskDisplayName;
@end
