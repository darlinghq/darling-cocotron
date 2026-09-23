#import <Foundation/NSObject.h>

@interface NSScrollEdgeEffectStyle : NSObject <NSCopying> {
    NSUInteger _style;
}

+ (instancetype) automaticStyle;
+ (instancetype) hardStyle;
+ (instancetype) softStyle;

@end
