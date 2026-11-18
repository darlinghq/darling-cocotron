/*
 * This file is part of Darling.
 *
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */


// Whether a layer whose pixels come from its own native surface (a plane above
// the window's composited layer tree) can show them there instead of having
// them composited, and still look exactly as the tree would draw it.

#import <QuartzCore/CALayer.h>

#ifdef __cplusplus
extern "C" {
#endif

// The rectangle `layer` covers in `root`'s coordinates (points, origin at the
// lower left of root's bounds), from position, anchor point and bounds alone.
CGRect CALayerPlaneFrameInRoot(CALayer *layer, CALayer *root);

// YES when `layer`, in the tree under `root`, may be shown on a plane of its
// own: the plane always sits above the whole composited tree, is opaque and is
// cut only by the edges of the window. That holds when
// - the layer and its ancestors are visible, not transformed, fully opaque
//   (opacity 1, and the layer itself opaque), without mask, filters, z
//   position or running animations, and the layer has no border;
// - no ancestor's bounds clip it (masksToBounds) and it lies within root;
// - nothing that is drawn after it (its sublayers, the sublayers above it and
//   above each ancestor, with their sublayers) draws anything over it.
// Otherwise the layer must be composited with the tree.
BOOL CALayerCanPresentOnOwnPlane(CALayer *layer, CALayer *root);

#ifdef __cplusplus
}
#endif
