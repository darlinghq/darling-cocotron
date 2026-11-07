/*
 This file is part of Darling.

 Copyright (C) 2025 Darling Developers

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

// CAContext and its options are SPI: QuartzCore exports them, but the SDK
// headers do not declare them. These are the declarations that applications
// hosting layers across processes (browsers' GPU and renderer processes, view
// services) declare for themselves.
//
// In Darling, a remote context renders its layer tree into IOSurfaces, and a
// CALayerHost in another process (or in this one) that is given the
// context's contextId shows them. See CAContext.m.

#import <Foundation/Foundation.h>
#import <QuartzCore/CABase.h>
#include <mach/port.h>

@class CALayer;

typedef uint32_t CAContextID;

CA_EXTERN NSString *const kCAContextCIFilterBehavior;
CA_EXTERN NSString *const kCAContextDisplayId;
CA_EXTERN NSString *const kCAContextDisplayName;
CA_EXTERN NSString *const kCAContextIgnoresHitTest;
CA_EXTERN NSString *const kCAContextPortNumber;

@class CARemoteLayerContext;

@interface CAContext : NSObject {
    CAContextID _contextId;
    CALayer *_layer;
    CARemoteLayerContext *_renderContext;
    mach_port_t _port;
    void *_source;
    mach_port_t *_subscribers;
    unsigned int _subscriberCount;
    BOOL _registered;
}

// A context whose layer tree other processes can show with a CALayerHost
// given its contextId. The options are accepted and not used.
+ (instancetype) remoteContext;
+ (instancetype) remoteContextWithOptions: (NSDictionary *) options;
// The same as +remoteContextWithOptions:; the connection is not used.
+ (instancetype) contextWithCGSConnection: (CAContextID) connection
                                  options: (NSDictionary *) options;

// Unique among the live contexts of the session; never 0.
@property(readonly) CAContextID contextId;
@property(retain) CALayer *layer;

// Stops serving the context: hosts stop showing it, and the layer is
// released. contextId keeps its value.
- (void) invalidate;

@end
