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

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/NSNibControlConnector.h>

@implementation NSNibControlConnector

- (instancetype) initWithCoder: (NSCoder *) coder {
    self = [super initWithCoder: coder];

    if (self != nil && ![coder allowsKeyedCoding]) {
        // Reading an archive made by NSArchiver leaves the action name in
        // selector form (with its trailing colon), as seen on macOS when
        // decoding a name without one (MC-NSCODER-3).
        NSUInteger length = [_label length];

        if (length > 0 && [_label characterAtIndex: length - 1] != ':') {
            NSString *selectorName = [_label stringByAppendingString: @":"];

            [_label release];
            _label = [selectorName retain];
        }
    }

    return self;
}

- (void) establishConnection {
    NSString *selectorName = _label;
    NSUInteger length = [selectorName length];
    SEL selector;

    if (length > 0 && [selectorName characterAtIndex: length - 1] != ':')
        selectorName = [selectorName stringByAppendingString: @":"];

    selector = NSSelectorFromString(selectorName);

    if (selector == NULL)
        [NSException
                 raise: NSInvalidArgumentException
                format: @"-[%@ %s] selector %@ does not exist:", [self class],
                        sel_getName(_cmd), selectorName];

    if ([_source respondsToSelector: @selector(setAction:)])
        [_source setAction: selector];
    else {
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] _source does not respond to setAction:",
                            [self class], sel_getName(_cmd)];
    }

    if ([_source respondsToSelector: @selector(setTarget:)])
        [_source performSelector: @selector(setTarget:)
                      withObject: _destination];
    else {
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] _source does not respond to setTarget:",
                            [self class], sel_getName(_cmd)];
    }
}

@end
