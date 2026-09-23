#import <AppKit/NSScrollEdgeEffectStyle.h>

enum {
    NSScrollEdgeAutomatic = 0,
    NSScrollEdgeHard = 1,
    NSScrollEdgeSoft = 2,
};

@interface NSScrollEdgeEffectStyle ()
- (instancetype) initWithStyle: (NSUInteger) style;
@end

@implementation NSScrollEdgeEffectStyle

- (instancetype) init {
    return [self initWithStyle: NSScrollEdgeAutomatic];
}

- (instancetype) initWithStyle: (NSUInteger) style {
    if ((self = [super init]))
        _style = style;
    return self;
}

+ (instancetype) automaticStyle {
    static NSScrollEdgeEffectStyle *style = nil;
    @synchronized(self) {
        if (style == nil)
            style = [[self alloc] initWithStyle: NSScrollEdgeAutomatic];
    }
    return style;
}

+ (instancetype) hardStyle {
    static NSScrollEdgeEffectStyle *style = nil;
    @synchronized(self) {
        if (style == nil)
            style = [[self alloc] initWithStyle: NSScrollEdgeHard];
    }
    return style;
}

+ (instancetype) softStyle {
    static NSScrollEdgeEffectStyle *style = nil;
    @synchronized(self) {
        if (style == nil)
            style = [[self alloc] initWithStyle: NSScrollEdgeSoft];
    }
    return style;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

- (BOOL) isEqual: (id) other {
    return self == other || ([other isKindOfClass: [NSScrollEdgeEffectStyle class]] &&
                             _style == ((NSScrollEdgeEffectStyle *) other)->_style);
}

- (NSUInteger) hash {
    return _style;
}

@end
