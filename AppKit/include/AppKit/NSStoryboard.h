/*
 This file is part of Darling.

 Copyright (C) 2021 Lubos Dolezel

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
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/Foundation.h>

typedef NSString *NSStoryboardName NS_SWIFT_BRIDGED_TYPEDEF;
typedef NSString *NSStoryboardSceneIdentifier NS_SWIFT_BRIDGED_TYPEDEF;

@interface NSStoryboard : NSObject {
    NS_EXTRA_IVARS_BEGIN(NSStoryboard)
    NSString *_path;
    NSDictionary *_info;
    NS_EXTRA_IVARS_END(NSStoryboard)
}

@property(class, readonly, strong) NSStoryboard *mainStoryboard;

+ (instancetype) storyboardWithName: (NSStoryboardName) name
                             bundle: (NSBundle *) storyboardBundleOrNil;

- (id) instantiateInitialController;
- (id) instantiateControllerWithIdentifier: (NSStoryboardSceneIdentifier) identifier;

@end
