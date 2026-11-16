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

#import <AppKit/NSTextField.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSButtonCell, NSMenu;

@class NSSearchField;

@protocol NSSearchFieldDelegate <NSTextFieldDelegate>
@optional
- (void) searchFieldDidStartSearching: (NSSearchField *) sender;
- (void) searchFieldDidEndSearching: (NSSearchField *) sender;
@end

// Legacy ObjC ABI (i386): instance size must stay 0x74, Apple's; an
// application's subclass is laid out right after it. New state goes to a
// side structure, never to a larger ivar block.
@interface NSSearchField : NSTextField {
    BOOL _searching;
    NS_LEGACY_IVAR_PAD(_NSSearchFieldReserved1, 15)
}

@property(nonatomic, copy) NSArray *recentSearches;
@property(nonatomic, copy) NSString *recentsAutosaveName;
@property(nonatomic) int maximumRecents;
@property(nonatomic) BOOL sendsWholeSearchString;
@property(nonatomic) BOOL sendsSearchStringImmediately;
@property(nonatomic, retain) NSButtonCell *searchButtonCell;
@property(nonatomic, retain) NSButtonCell *cancelButtonCell;
@property(nonatomic, retain) NSMenu *searchMenuTemplate;


@end
