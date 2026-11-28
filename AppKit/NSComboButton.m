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

#import <AppKit/NSComboButton.h>
#import <AppKit/NSMenu.h>
#import <Foundation/NSString.h>

@implementation NSComboButton

@synthesize style = _style;
@synthesize menu = _comboMenu;
@synthesize comboTitle = _comboTitle;

+ (instancetype) comboButtonWithTitle: (NSString *) title
                                 menu: (NSMenu *) menu
                               target: (id) target
                               action: (SEL) action
{
    NSComboButton *button = [[[self alloc] initWithFrame: NSMakeRect(0, 0, 80, 32)]
            autorelease];
    [button setComboTitle: title];
    [button setMenu: menu];
    [button setTarget: target];
    [button setAction: action];
    return button;
}

+ (instancetype) comboButtonWithImage: (NSImage *) image
                                 menu: (NSMenu *) menu
                               target: (id) target
                               action: (SEL) action
{
    NSComboButton *button = [[[self alloc] initWithFrame: NSMakeRect(0, 0, 32, 32)]
            autorelease];
    [button setImage: image];
    [button setMenu: menu];
    [button setTarget: target];
    [button setAction: action];
    return button;
}

+ (instancetype) comboButtonWithTitle: (NSString *) title
                                image: (NSImage *) image
                                 menu: (NSMenu *) menu
                               target: (id) target
                               action: (SEL) action
{
    NSComboButton *button = [self comboButtonWithTitle: title
                                                  menu: menu
                                                target: target
                                                action: action];
    [button setImage: image];
    return button;
}

- (void) dealloc
{
    [_comboMenu release];
    [_comboTitle release];
    [super dealloc];
}

@end
