/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/Foundation.h>

#import <AppKit/NSText.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

typedef NSString *NSTextTabOptionKey NS_TYPED_ENUM;
APPKIT_EXPORT NSTextTabOptionKey NSTabColumnTerminatorsAttributeName;

// The primary interface matches Apple's declaration member for member: Clang
// rejects a class that two modules define differently.
@interface NSTextTab : NSObject <NSCopying, NSCoding, NSSecureCoding> {
    NSTextAlignment _alignment;
    CGFloat _location;
    NSDictionary *_options;
}

+ (NSCharacterSet *)columnTerminatorsForLocale:(nullable NSLocale *)aLocale;

@property (readonly, NS_NONATOMIC_IOSONLY) CGFloat location;
@property (readonly, NS_NONATOMIC_IOSONLY) NSDictionary<NSTextTabOptionKey, id> *options;
@end

@interface NSTextTab (NSTextTabAlignment)
- (instancetype)initWithTextAlignment:(NSTextAlignment)alignment location:(CGFloat)loc options:(NSDictionary<NSTextTabOptionKey, id> *)options;
@property (readonly, NS_NONATOMIC_IOSONLY) NSTextAlignment alignment;
- (NSComparisonResult)compare:(NSTextTab *)other;
@end

typedef NS_ENUM(NSUInteger, NSTextTabType) {
    NSLeftTabStopType = 0,
    NSRightTabStopType,
    NSCenterTabStopType,
    NSDecimalTabStopType
};

@interface NSTextTab (NSTextTabDeprecated)
- (instancetype)initWithType:(NSTextTabType)type location:(CGFloat)loc;
@property (readonly) NSTextTabType tabStopType;
@end

NS_HEADER_AUDIT_END(nullability, sendability)
