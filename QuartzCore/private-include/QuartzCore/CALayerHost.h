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

// CALayerHost is SPI (see CAContext.h). It shows the layer tree of the
// CAContext whose contextId it is given, from any process of the session.

#import <QuartzCore/CALayer.h>
#import <QuartzCore/CAContext.h>

@class CALayerHostConnection;

@interface CALayerHost : CALayer {
    CAContextID _contextId;
    CALayerHostConnection *_connection;
}

// 0, the default, shows nothing. An ID that names no context is kept and
// shows nothing.
@property CAContextID contextId;

@end
