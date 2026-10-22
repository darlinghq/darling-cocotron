/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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
#import <Foundation/NSObject.h>

typedef NSString *NSSharingServiceName;

APPKIT_EXPORT NSSharingServiceName const NSSharingServiceNameAddToIPhoto;
APPKIT_EXPORT NSSharingServiceName const NSSharingServiceNameAddToSafariReadingList;
APPKIT_EXPORT NSSharingServiceName const NSSharingServiceNameComposeEmail;
APPKIT_EXPORT NSSharingServiceName const NSSharingServiceNameComposeMessage;

/* Deprecated */
APPKIT_EXPORT NSSharingServiceName const NSSharingServiceNamePostOnFacebook;
APPKIT_EXPORT NSSharingServiceName const NSSharingServiceNamePostOnLinkedIn;
APPKIT_EXPORT NSSharingServiceName const NSSharingServiceNamePostOnSinaWeibo;
APPKIT_EXPORT NSSharingServiceName const NSSharingServiceNamePostOnTencentWeibo;
APPKIT_EXPORT NSSharingServiceName const NSSharingServiceNamePostOnTwitter;

@class NSImage, NSArray, NSMenu, NSView;
@protocol NSSharingServiceDelegate, NSSharingServicePickerDelegate;

@interface NSSharingService : NSObject {
    NSString *_title;
    NSImage *_image;
    NSImage *_alternateImage;
    NSString *_menuItemTitle;
    id <NSSharingServiceDelegate> _delegate;
}

@property (readonly, copy) NSString *title;
@property (readonly, retain) NSImage *image;
@property (readonly, retain) NSImage *alternateImage;
@property (copy) NSString *menuItemTitle;
@property (assign) id <NSSharingServiceDelegate> delegate;

+ (NSArray<NSSharingService *> *) sharingServicesForItems: (NSArray *) items;
+ (NSSharingService *) sharingServiceNamed: (NSSharingServiceName) serviceName;

- (instancetype) initWithTitle: (NSString *) title image: (NSImage *) image alternateImage: (NSImage *) alternateImage handler: (void (^)(void)) block;
- (BOOL) canPerformWithItems: (NSArray *) items;
- (void) performWithItems: (NSArray *) items;

@end

@interface NSSharingServicePicker : NSObject {
    NSArray *_items;
    id <NSSharingServicePickerDelegate> _delegate;
}

@property (assign) id <NSSharingServicePickerDelegate> delegate;

- (instancetype) initWithItems: (NSArray *) items;
- (NSMenu *) menu;
- (void) showRelativeToRect: (NSRect) rect ofView: (NSView *) view preferredEdge: (NSRectEdge) preferredEdge;

@end

@protocol NSSharingServiceDelegate <NSObject>

@end

@protocol NSSharingServicePickerDelegate <NSObject>

@end

// @interface NSItemProvider (NSCloudKitSharing)
// @end
