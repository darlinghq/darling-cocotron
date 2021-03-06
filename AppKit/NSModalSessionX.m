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

#import <AppKit/NSApplication.h>
#import <AppKit/NSModalSessionX.h>

@implementation NSModalSessionX

- (instancetype) initWithWindow: (NSWindow *) window {
    _window = [window retain];
    _unprocessedEvents = [[NSMutableArray alloc] init];
    _stopCode = NSRunContinuesResponse;
    return self;
}

- (void) dealloc {
    [_window release];
    [_unprocessedEvents release];
    [super dealloc];
}

+ (instancetype) sessionWithWindow: (NSWindow *) window {
    return [[[self alloc] initWithWindow: window] autorelease];
}

- (void) stopModalWithCode: (NSModalResponse) code {
    _stopCode = code;
}

- (NSWindow *) modalWindow {
    return _window;
}

- (NSModalResponse) stopCode {
    return _stopCode;
}

- (void) addUnprocessedEvent: (NSEvent *) event {
    [_unprocessedEvents addObject: event];
}

- (NSArray *) unprocessedEvents {
    return _unprocessedEvents;
}

@end
