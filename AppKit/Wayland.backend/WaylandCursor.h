/* Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSData, NSImage;

// A cursor of the Wayland backend: the names to look up in the cursor theme, most
// preferred first, an immutable ARGB image, or a blank cursor. Native resources
// belong to the display, so cached cursors can outlive its Wayland connection.
@interface WaylandCursor : NSObject {
    const char *_names[3];
    BOOL _blank;
    NSData *_pixels;
    NSImage *_image;
    uint32_t _pixelScale120;
    NSSize _size;
    NSPoint _hotSpot;
}

- (instancetype) initWithName: (const char *) name fallback: (const char *) fallback;
- (instancetype) initBlank;
- (instancetype) initWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot;
- (NSData *) pixels;
- (NSData *) pixelsForScale: (int32_t) scale;
- (NSData *) pixelsForScale120: (uint32_t) scale120;
- (NSSize) pixelSizeForScale120: (uint32_t) scale120;
- (NSSize) size;
- (NSPoint) hotSpot;

// NULL-terminated.
- (const char *const *) names;
- (BOOL) isBlank;

@end
