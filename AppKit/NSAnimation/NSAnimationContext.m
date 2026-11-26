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

#import <AppKit/NSAnimationContext.h>
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

- (void) dealloc {
    [NS_EXTRA(NSAnimationContext, self)->_completionHandler release];
    [NS_EXTRA(NSAnimationContext, self)->_timingFunction release];
    NS_EXTRA_FREE(NSAnimationContext, self);
    [super dealloc];
}

// The contexts of the groups being run on this thread, innermost last; the base context, which exists
// outside any group, is not on it.
static NSMutableArray *NSAnimationContextStack(void) {
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    NSMutableArray *stack = [threadDictionary objectForKey: @"NSAnimationContextStack"];
    if (stack == nil) {
        stack = [NSMutableArray array];
        [threadDictionary setObject: stack forKey: @"NSAnimationContextStack"];
    }
    return stack;
}

+ (void) runAnimationGroup: (void (^)(NSAnimationContext *context)) changes {
    [self runAnimationGroup: changes completionHandler: nil];
}

+ (void) runAnimationGroup: (void (^)(NSAnimationContext *context)) changes
         completionHandler: (void (^)(void)) completionHandler
{
    [self beginGrouping];
    NSAnimationContext *context = [self currentContext];
    [context setDuration: NSAnimationContextDefaultDuration];
    if (completionHandler)
        [context setCompletionHandler: completionHandler];
    if (changes)
        changes(context);
    [self endGrouping];
}

+ (void) beginGrouping {
    NSAnimationContext *outer = [self currentContext];
    NSAnimationContext *context = [[NSAnimationContext alloc] init];
    [context setDuration: [outer duration]];
    [context setTimingFunction: [outer timingFunction]];
    [NSAnimationContextStack() addObject: context];
    [context release];
}

+ (void) endGrouping {
    NSMutableArray *stack = NSAnimationContextStack();
    if ([stack count] == 0)
        return;
    NSAnimationContext *context = [[stack lastObject] retain];
    [stack removeLastObject];
    // The group's changes have been applied by now; nothing runs after them, so it is over.
    void (^handler)(void) = [[context completionHandler] retain];
    [context setCompletionHandler: nil];
    if (handler) {
        handler();
        [handler release];
    }
    [context release];
}

+ (NSAnimationContext *) currentContext {
    NSMutableArray *stack = NSAnimationContextStack();
    if ([stack count] > 0)
        return [stack lastObject];
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    NSAnimationContext *context = [threadDictionary objectForKey: @"NSAnimationContext"];
    if (context == nil) {
        context = [[[NSAnimationContext alloc] init] autorelease];
        [threadDictionary setObject: context forKey: @"NSAnimationContext"];
    }
    return context;
}

- (void) setCompletionHandler: (void (^)(void)) handler {
    void (^copied)(void) = [handler copy];
    [NS_EXTRA(NSAnimationContext, self)->_completionHandler release];
    NS_EXTRA(NSAnimationContext, self)->_completionHandler = copied;
}

- (void (^)(void)) completionHandler {
    return NS_EXTRA(NSAnimationContext, self)->_completionHandler;
}

- (void) setAllowsImplicitAnimation: (BOOL) allows {
    NS_EXTRA(NSAnimationContext, self)->_allowsImplicitAnimation = allows;
}

- (BOOL) allowsImplicitAnimation {
    return NS_EXTRA(NSAnimationContext, self)->_allowsImplicitAnimation;
}

- (void) setTimingFunction: (CAMediaTimingFunction *) timingFunction {
    [timingFunction retain];
    [NS_EXTRA(NSAnimationContext, self)->_timingFunction release];
    NS_EXTRA(NSAnimationContext, self)->_timingFunction = timingFunction;
}

- (CAMediaTimingFunction *) timingFunction {
    return NS_EXTRA(NSAnimationContext, self)->_timingFunction;
}

- (void) setDuration: (NSTimeInterval) duration {
    _duration = duration;
}

- (NSTimeInterval) duration {
    return _duration;
}

@end
