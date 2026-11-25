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


#import "CALayerPlane.h"
#import <QuartzCore/CATransform3D.h>
#import <QuartzCore/CATransformLayer.h>
#import <Foundation/NSArray.h>
#import <objc/runtime.h>

CGRect CALayerPlaneFrameInRoot(CALayer *layer, CALayer *root) {
    CGRect bounds = [layer bounds];
    CGRect rect = CGRectMake(0, 0, bounds.size.width, bounds.size.height);

    while (layer != nil && layer != root) {
        CALayer *parent = [layer superlayer];
        if (parent == nil)
            break;

        CGRect layerBounds = [layer bounds];
        CGPoint position = [layer position];
        CGPoint anchor = [layer anchorPoint];
        CGPoint parentOrigin = [parent bounds].origin;

        rect.origin.x += position.x - anchor.x * layerBounds.size.width - layerBounds.origin.x - parentOrigin.x;
        rect.origin.y += position.y - anchor.y * layerBounds.size.height - layerBounds.origin.y - parentOrigin.y;
        layer = parent;
    }
    return rect;
}

static BOOL colorIsVisible(CGColorRef color) {
    return color != NULL && CGColorGetAlpha(color) > 0;
}

// Whether a layer's class draws something of its own (a text, shape or
// gradient layer, a Metal or OpenGL layer, -drawInContext: overridden).
static BOOL classDrawsItself(Class cls) {
    static IMP baseDraw, baseContents;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        baseDraw = class_getMethodImplementation([CALayer class], @selector(drawInContext:));
        baseContents = class_getMethodImplementation([CALayer class], @selector(_drawLayerContents:opacity:));
    });
    return class_getMethodImplementation(cls, @selector(drawInContext:)) != baseDraw ||
           class_getMethodImplementation(cls, @selector(_drawLayerContents:opacity:)) != baseContents;
}

static BOOL hasEffects(CALayer *layer) {
    return [layer mask] != nil || [[layer filters] count] > 0 || [layer compositingFilter] != nil ||
           [[layer backgroundFilters] count] > 0;
}

// Whether `layer` or anything under it draws anything inside `rect` (root
// coordinates). Unknown extents (transforms) count as covering everything.
static BOOL subtreeDrawsInRect(CALayer *layer, CALayer *root, CGRect rect) {
    if ([layer isHidden] || [layer opacity] <= 0)
        return NO;
    // Animated geometry or effects make the drawn extent unknown.
    if ([[layer animationKeys] count] > 0 || !CATransform3DIsIdentity([layer transform]) ||
        !CATransform3DIsIdentity([layer sublayerTransform]) || hasEffects(layer))
        return YES;

    CGRect frame = CALayerPlaneFrameInRoot(layer, root);
    // A shadow reaches outside the frame.
    if ([layer shadowOpacity] > 0)
        return YES;

    BOOL draws = [layer contents] != nil || colorIsVisible([layer backgroundColor]) ||
                 ([layer borderWidth] > 0 && colorIsVisible([layer borderColor])) ||
                 ([layer needsDisplay] && [layer delegate] != nil) ||
                 ([layer class] != [CALayer class] && ![layer isKindOfClass: [CATransformLayer class]] &&
                  classDrawsItself([layer class]));
    if (draws && CGRectIntersectsRect(frame, rect))
        return YES;

    if ([layer masksToBounds]) {
        rect = CGRectIntersection(rect, frame);
        if (CGRectIsEmpty(rect))
            return NO;
    }

    for (CALayer *child in [layer sublayers])
        if (subtreeDrawsInRect(child, root, rect))
            return YES;
    return NO;
}

// The layer's own state allows it to stand for itself on a plane.
static BOOL layerIsPlain(CALayer *layer) {
    return ![layer isHidden] && [layer opacity] >= 1 && CATransform3DIsIdentity([layer transform]) &&
           ![layer isGeometryFlipped] && [layer zPosition] == 0 && !hasEffects(layer) &&
           [[layer animationKeys] count] == 0;
}

BOOL CALayerCanPresentOnOwnPlane(CALayer *layer, CALayer *root) {
    if (layer == nil || root == nil)
        return NO;

    if (!layerIsPlain(layer) || ![layer isOpaque] ||
        ([layer borderWidth] > 0 && colorIsVisible([layer borderColor])) || [layer shadowOpacity] > 0)
        return NO;

    CGRect frame = CALayerPlaneFrameInRoot(layer, root);
    if (CGRectIsEmpty(frame))
        return NO;

    // What is drawn over the layer: its own sublayers first.
    for (CALayer *child in [layer sublayers])
        if (subtreeDrawsInRect(child, root, frame))
            return NO;

    CALayer *current = layer;
    while (current != root) {
        CALayer *parent = [current superlayer];
        if (parent == nil)
            return NO; // not in root's tree
        if (!layerIsPlain(parent) || !CATransform3DIsIdentity([parent sublayerTransform]))
            return NO;

        // Clipped by the parent's bounds: only a clip that leaves the whole
        // layer visible keeps it on its plane.
        if ([parent masksToBounds] || parent == root) {
            CGRect parentFrame = CALayerPlaneFrameInRoot(parent, root);
            if (!CGRectContainsRect(parentFrame, frame))
                return NO;
        }

        // Siblings after `current` are drawn above it; a z position reorders them,
        // and so does an animation of it, which the renderer follows.
        BOOL above = NO;
        for (CALayer *sibling in [parent sublayers]) {
            if ([sibling zPosition] != 0 || [sibling animationForKey: @"zPosition"] != nil)
                return NO;
            if (sibling == current) {
                above = YES;
                continue;
            }
            if (above && subtreeDrawsInRect(sibling, root, frame))
                return NO;
        }
        current = parent;
    }
    return YES;
}
