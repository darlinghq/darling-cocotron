/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Developers

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/AppKitExport.h>
#import <AppKit/NSResponder.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSNotification.h>

@class NSPanel, NSView, NSViewController;
@protocol NSPopoverDelegate;

APPKIT_EXPORT NSNotificationName const NSPopoverDidCloseNotification;
APPKIT_EXPORT NSNotificationName const NSPopoverWillCloseNotification;
APPKIT_EXPORT NSNotificationName const NSPopoverWillShowNotification;
APPKIT_EXPORT NSNotificationName const NSPopoverDidShowNotification;

typedef NS_ENUM(NSInteger, NSPopoverBehavior) {
    NSPopoverBehaviorApplicationDefined = 0,
    NSPopoverBehaviorTransient = 1,
    NSPopoverBehaviorSemitransient = 2,
};

@interface NSPopover : NSResponder <NSCoding> {
    NSPopoverBehavior _behavior;
    BOOL _animates;
    NSSize _contentSize;
    NSViewController *_contentViewController;
    id<NSPopoverDelegate> _delegate;
    NSRect _positioningRect;
    NSPanel *_panel;
}

@property NSPopoverBehavior behavior;
@property BOOL animates;
@property NSSize contentSize;
@property(retain) NSViewController *contentViewController;
@property(assign) id<NSPopoverDelegate> delegate;
@property NSRect positioningRect;
@property(readonly, getter=isShown) BOOL shown;

- (void) showRelativeToRect: (NSRect) positioningRect
                     ofView: (NSView *) positioningView
              preferredEdge: (NSRectEdge) preferredEdge;
- (void) performClose: (id) sender;
- (void) close;

@end

@protocol NSPopoverDelegate <NSObject>
@optional
- (BOOL) popoverShouldClose: (NSPopover *) popover;
- (void) popoverWillShow: (NSNotification *) notification;
- (void) popoverDidShow: (NSNotification *) notification;
- (void) popoverWillClose: (NSNotification *) notification;
- (void) popoverDidClose: (NSNotification *) notification;
@end
