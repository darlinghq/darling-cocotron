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

#import <AppKit/NSNibOutletConnector.h>
#import <objc/runtime.h>

@implementation NSNibOutletConnector

- (void) establishConnection {
    NSString *methodName = [NSString
            stringWithFormat: @"set%@%@:",
                              [[_label substringToIndex: 1] uppercaseString],
                              [_label substringFromIndex: 1]];
    SEL selector = NSSelectorFromString(methodName);

    if (selector != NULL) {
        if ([_source respondsToSelector: selector]) {
            [_source performSelector: selector withObject: _destination];
            return;
        }
    }

    if (_source != nil && _label != nil) {
        if (object_setInstanceVariable(_source, [_label UTF8String], _destination) != nil) {
            return;
        }

        NSString *ivarName = [@"_" stringByAppendingString: _label];
        if (object_setInstanceVariable(_source, [ivarName UTF8String], _destination) != nil) {
            return;
        }

        // Key-value coding raises for an outlet the source cannot accept, as it
        // does for any other key; the exception is not swallowed here.
        [_source setValue: _destination forKey: _label];
    }
}

@end
