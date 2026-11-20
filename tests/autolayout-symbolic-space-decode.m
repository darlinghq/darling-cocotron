// Copyright (C) 2026 Lubos Dolezel
// A layout constraint with a standard space (Interface Builder's "standard" spacing, the "-" of
// the visual format language) is archived with the symbolic constant NSSpace and no constant, as
// macOS 26.7.3 archives it. Decoded, its constant is the standard space: 20 to the edge of the
// superview, 8 between siblings, even when the archive also has a constant (macOS 10.14.4 and
// 26.7.3).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) do { if (!(cond)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

@interface ArchivedConstraint : NSObject <NSCoding> {
@public
    NSView *_first, *_second;
    NSLayoutAttribute _firstAttribute, _secondAttribute;
    BOOL _hasConstant;
}
@end

@implementation ArchivedConstraint

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: _first forKey: @"NSFirstItem"];
    [coder encodeInteger: _firstAttribute forKey: @"NSFirstAttribute"];
    [coder encodeInteger: _firstAttribute forKey: @"NSFirstAttributeV2"];
    [coder encodeObject: _second forKey: @"NSSecondItem"];
    [coder encodeInteger: _secondAttribute forKey: @"NSSecondAttribute"];
    [coder encodeInteger: _secondAttribute forKey: @"NSSecondAttributeV2"];
    [coder encodeObject: @"NSSpace" forKey: @"NSSymbolicConstant"];
    if (_hasConstant) {
        [coder encodeDouble: 5 forKey: @"NSConstant"];
        [coder encodeDouble: 5 forKey: @"NSConstantV2"];
    }
    [coder encodeBool: YES forKey: @"NSShouldBeArchived"];
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    return [super init];
}

@end

static ArchivedConstraint *constraint(NSView *first, NSLayoutAttribute firstAttribute, NSView *second,
                                      NSLayoutAttribute secondAttribute, BOOL hasConstant) {
    ArchivedConstraint *c = [[ArchivedConstraint alloc] init];
    c->_first = first;
    c->_firstAttribute = firstAttribute;
    c->_second = second;
    c->_secondAttribute = secondAttribute;
    c->_hasConstant = hasConstant;
    return c;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSView *container = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
        NSView *a = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        NSView *b = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        [container addSubview: a];
        [container addSubview: b];

        NSArray *objects = @[
            container,
            constraint(a, NSLayoutAttributeLeading, container, NSLayoutAttributeLeading, NO),
            constraint(container, NSLayoutAttributeTrailing, b, NSLayoutAttributeTrailing, NO),
            constraint(b, NSLayoutAttributeLeading, a, NSLayoutAttributeTrailing, NO),
            constraint(a, NSLayoutAttributeTop, container, NSLayoutAttributeTop, YES),
        ];

        NSMutableData *data = [NSMutableData data];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData: data];
        [archiver setClassName: @"NSLayoutConstraint" forClass: [ArchivedConstraint class]];
        [archiver encodeObject: objects forKey: @"root"];
        [archiver finishEncoding];

        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData: data];
        NSArray *decoded = [unarchiver decodeObjectForKey: @"root"];
        [unarchiver finishDecoding];

        CHECK([decoded count] == 5, "decoded %lu objects", (unsigned long) [decoded count]);
        for (NSUInteger i = 1; i < [decoded count]; i++)
            CHECK([[decoded objectAtIndex: i] isKindOfClass: [NSLayoutConstraint class]], "object %lu is a constraint", (unsigned long) i);
        if (failures == 0) {
            CGFloat constants[5];
            for (NSUInteger i = 1; i < 5; i++)
                constants[i] = [(NSLayoutConstraint *) [decoded objectAtIndex: i] constant];
            CHECK(constants[1] == 20, "to the superview's leading edge: %g", constants[1]);
            CHECK(constants[2] == 20, "from the superview's trailing edge: %g", constants[2]);
            CHECK(constants[3] == 8, "between siblings: %g", constants[3]);
            CHECK(constants[4] == 20, "the standard space wins over an archived constant: %g", constants[4]);
        }
    }
    if (failures) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("PASS\n");
    return 0;
}
