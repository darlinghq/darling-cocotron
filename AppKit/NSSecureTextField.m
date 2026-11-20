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
#import <AppKit/NSSecureTextField.h>
#import <AppKit/NSSecureTextFieldCell.h>
#import <AppKit/NSColor.h>

@implementation NSSecureTextField

+ (Class) cellClass {
    return [NSSecureTextFieldCell class];
}

// QUIRK: a new secure text field draws its background in
// controlBackgroundColor, not textBackgroundColor. Not documented. Evidence:
// black-box observation on macOS 10.14.4 and 26.7.3 (tier 2), probe
// mac-probes/aqua-metric-followups.m of the research notes.
// Test: appkit-text-field-defaults.m (test_quirk_field_defaults)
- (void) _setDefaultBackground {
    [[self cell] setDrawsBackground: YES];
    [[self cell] setBackgroundColor: [NSColor controlBackgroundColor]];
}

// QUIRK: an archive (a nib compiled by the Interface Builder tools, for one)
// may store the cell of a secure text field as a plain NSTextFieldCell; macOS
// still gives the decoded field a secure cell (bullets, secure field editor).
// So that archived class is read as NSSecureTextFieldCell; other cell classes,
// such as subclasses, are kept. Not documented. Evidence: black-box
// observation on macOS 10.14.4 (tier 2). Test: tests/appkit-secure-text-field.m.
- initWithCoder: (NSCoder *) coder {
    static NSString *const plainCellName = @"NSTextFieldCell";
    // The keyed unarchiver and the decoder of compiled nibs both map the class
    // names of an archive to classes.
    BOOL mapsClasses = [coder allowsKeyedCoding] &&
                       [coder respondsToSelector: @selector(setClass:forClassName:)] &&
                       [coder respondsToSelector: @selector(classForClassName:)];
    Class previous = Nil;

    if (mapsClasses) {
        previous = [(NSKeyedUnarchiver *) coder classForClassName: plainCellName];
        [(NSKeyedUnarchiver *) coder setClass: [NSSecureTextFieldCell class]
                                 forClassName: plainCellName];
    }

    self = [super initWithCoder: coder];

    if (mapsClasses) {
        // Mappings of other classes of the same decoder stay as they were.
        [(NSKeyedUnarchiver *) coder setClass: previous forClassName: plainCellName];
    }
    return self;
}

- (BOOL) echosBullets {
    return [[self cell] echosBullets];
}

- (void) setEchosBullets: (BOOL) yorn {
    return [[self cell] setEchosBullets: yorn];
}

@end
