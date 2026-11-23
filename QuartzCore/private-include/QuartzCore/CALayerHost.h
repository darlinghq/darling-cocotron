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
#import <QuartzCore/LegacyIvarLayout.h>
#import <QuartzCore/CAContext.h>

@class CALayerHostConnection;

#define _NS_SIDE_CALayerHost 0, 1,
@interface CALayerHost : CALayer {
    NS_EXTRA_IVARS_BEGIN(CALayerHost)
        CAContextID _contextId;
        CALayerHostConnection *_connection;
        // The texture state (see -_textureId) of the surface that is not the
        // one on screen: the two surfaces each keep a texture, so that each is
        // bound to its texture once rather than every frame.
        int _activeSlot;
        NSNumber *_otherTextureId;
        id _otherTextureContents;
        uint32_t _otherTextureSeed;
    NS_SIDE_IVARS_END(CALayerHost)
}

// 0, the default, shows nothing. An ID that names no context is kept and
// shows nothing.
@property CAContextID contextId;

@end
