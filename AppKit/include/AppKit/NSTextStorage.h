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

#import <AppKit/AppKitExport.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/Foundation.h>

@class NSLayoutManager, NSFont;

NS_ASSUME_NONNULL_BEGIN

enum {
    NSTextStorageEditedCharacters = 0x01,
    NSTextStorageEditedAttributes = 0x02,
};

APPKIT_EXPORT NSString *const NSTextStorageWillProcessEditingNotification;
APPKIT_EXPORT NSString *const NSTextStorageDidProcessEditingNotification;

// Legacy ObjC ABI (i386): instance size must stay 0x1c, Apple's; the ivars
// before the extras sit in the same words on every ABI. Add new state to the
// extra struct, never as an ivar.
@interface NSTextStorage : NSMutableAttributedString <NSCoding> {
    id _delegate;
    NSMutableArray *_layoutManagers;
    int _changeInLength;
    unsigned _editedMask;
    int _beginEditing;
    NS_EXTRA_IVARS_BEGIN(NSTextStorage)
        NSRange _editedRange;
    NS_EXTRA_IVARS_END(NSTextStorage)
}

- (null_unspecified id) delegate;
- (null_unspecified NSArray *) layoutManagers;

- (int) changeInLength;
- (unsigned) editedMask;
- (NSRange) editedRange;

- (void) setDelegate: (null_unspecified id) delegate;
- (void) addLayoutManager: (null_unspecified NSLayoutManager *) layoutManager;
- (void) removeLayoutManager: (null_unspecified NSLayoutManager *) layoutManager;

- (void) processEditing;

- (void) edited: (unsigned) editedMask
                 range: (NSRange) range
        changeInLength: (int) delta;

- (void) setFont: (nullable NSFont *) font;

@end

@protocol NSTextStorageDelegate <NSObject>
- (void) textStorageWillProcessEditing: (NSNotification *) note;
- (void) textStorageDidProcessEditing: (NSNotification *) note;
@end

NS_ASSUME_NONNULL_END
