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
#import <AppKit/AppKit.h>
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CGWindowPrivate.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSStatusItem+Private.h>

@implementation NSStatusBar

static NSStatusBar *_statusBar = nil;

+ (NSStatusBar *) systemStatusBar {
    if (_statusBar == nil) {
        _statusBar = [[NSStatusBar alloc] init];
    }
    return _statusBar;
}

+ (BOOL) _hasStatusItems {
    return _statusBar != nil && [_statusBar->_statusItems count] > 0;
}

- (id) init {
    self = [super init];
    if (self) {
        _statusItems = [[NSMutableArray alloc] init];
        [[NSNotificationCenter defaultCenter]
                addObserver: self
                   selector: @selector(handleApplicationClose)
                       name: @"NSApplicationWillTerminateNotification"
                     object: nil];
    }
    return self;
}

- (BOOL) isVertical {
    return NO;
}
- (void) removeStatusItem: (NSStatusItem *) item {
    // The default name of a removed item is free for the next item to take.
    [_statusItems removeObjectIdenticalTo: item];
    [item _detachFromStatusBar];
}

// Default autosave names are "Item-N" with the lowest N no other item holds.
- (NSString *) _unusedDefaultAutosaveName {
    for (NSUInteger index = 0;; index++) {
        NSString *name = [NSString stringWithFormat: @"Item-%lu", (unsigned long) index];
        BOOL taken = NO;
        for (NSStatusItem *other in _statusItems) {
            if ([name isEqualToString: [other _defaultAutosaveName]]) {
                taken = YES;
                break;
            }
        }
        if (!taken)
            return name;
    }
}
- (NSStatusItem *) statusItemWithLength: (CGFloat) length {
    NSStatusItem *item = [[NSStatusItem alloc] init];
    [item setLength: length];
    [item _setDefaultAutosaveName: [self _unusedDefaultAutosaveName]];
    [_statusItems addObject: item];
    [item _attachToStatusBar];
    return [item autorelease];
}
- (CGFloat) thickness {
    // The menu bar's thickness, as observed on macOS 10.14 and 26.
    return 22;
}


- (void) handleApplicationClose {
    // Leaving the tray before the process goes away spares it a stale icon.
    for (NSStatusItem *item in _statusItems)
        [item _detachFromStatusBar];
}

@end
