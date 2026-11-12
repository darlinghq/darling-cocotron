/* Copyright (c) 2007 Christopher J. W. Lloyd

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import "NSAnimationContext.h"
#import <Foundation/NSThread.h>

// The documented default duration of an animation group.
static const NSTimeInterval NSAnimationContextDefaultDuration = 0.25;

@implementation NSAnimationContext

- (id) init {
    if ((self = [super init]))
        _duration = NSAnimationContextDefaultDuration;
    return self;
}

- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}

+ (void) runAnimationGroup: (void (^)(NSAnimationContext *context)) changes
         completionHandler: (void (^)(void)) completionHandler
{
    NSAnimationContext *context = [self currentContext];
    NSTimeInterval outerDuration = [context duration];
    [context setDuration: NSAnimationContextDefaultDuration];
    if (changes)
        changes(context);
    [context setDuration: outerDuration];
    if (completionHandler)
        completionHandler();
}

+ (void) beginGrouping {
}

+ (void) endGrouping {
}

+ (NSAnimationContext *) currentContext {
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    NSAnimationContext *context = [threadDictionary objectForKey: @"NSAnimationContext"];
    if (context == nil) {
        context = [[[NSAnimationContext alloc] init] autorelease];
        [threadDictionary setObject: context forKey: @"NSAnimationContext"];
    }
    return context;
}

- (void) setDuration: (NSTimeInterval) duration {
    _duration = duration;
}

- (NSTimeInterval) duration {
    return _duration;
}

@end
