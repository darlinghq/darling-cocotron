/* Copyright (c) 2026 Darling Developers

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

#import <AppKit/NSAccessibilityCustomAction.h>
#import <Foundation/NSString.h>

@implementation NSAccessibilityCustomAction

@synthesize name = _name;
@synthesize handler = _handler;
@synthesize target = _target;
@synthesize selector = _selector;

- (instancetype) initWithName: (NSString *) name
                      handler: (NSAccessibilityCustomActionHandler) handler
{
    self = [super init];
    if (self == nil)
        return nil;

    _name = [name copy];
    _handler = [handler copy];
    return self;
}

- (instancetype) initWithName: (NSString *) name
                       target: (id) target
                     selector: (SEL) selector
{
    self = [super init];
    if (self == nil)
        return nil;

    _name = [name copy];
    _target = target;
    _selector = selector;
    return self;
}

- (void) dealloc {
    [_name release];
    [_handler release];
    [super dealloc];
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@[%p] name: %@>", [self class],
                                       self, _name];
}

@end
