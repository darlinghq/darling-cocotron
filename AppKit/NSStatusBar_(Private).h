//
//  NSStatusItem (Private).h
//  AppKit
//
//  Created by Rhys Cox on 17/02/2012.
//  Copyright (c) 2012 BP Software. All rights reserved.
//

#import <CoreFoundation/CFBase.h>
#import <Foundation/NSObject.h>

#define NSVariableStatusItemLength (-1)
#define NSSquareStatusItemLength (-2)

#import <AppKit/NSStatusBar.h>

@interface NSStatusBar (Private)
// Whether the application has put any item in the status bar. Does not create
// the status bar.
+ (BOOL) _hasStatusItems;
@end
