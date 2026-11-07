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

#import <AppKit/AppKitExport.h>
#import <Foundation/NSObject.h>

@class NSString;
@class NSAccessibilityCustomAction;

typedef BOOL (^NSAccessibilityCustomActionHandler)(
        NSAccessibilityCustomAction *action);

// An application-defined action of an accessibility element. AppKit only
// holds the name and what to run; an assistive client is what invokes it.

APPKIT_EXPORT
@interface NSAccessibilityCustomAction : NSObject {
    NSString *_name;
    id _target;
    SEL _selector;
    NSAccessibilityCustomActionHandler _handler;
}

- (instancetype) initWithName: (NSString *) name
                      handler: (NSAccessibilityCustomActionHandler) handler;
- (instancetype) initWithName: (NSString *) name
                       target: (id) target
                     selector: (SEL) selector;

@property(copy) NSString *name;
@property(copy) NSAccessibilityCustomActionHandler handler;
// Not retained, like a weak reference.
@property(assign) id target;
@property SEL selector;

@end
