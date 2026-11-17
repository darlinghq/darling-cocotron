/* Copyright (C) 2026 Lubos Dolezel

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

// A QuickDraw picture (PICT version 2) is a frame rectangle followed by a stream of
// drawing opcodes. Only the opcodes that carry bitmaps (BitsRect, BitsRgn, PackBitsRect,
// PackBitsRgn, DirectBitsRect, DirectBitsRgn) draw anything here; the clip rectangle is
// honoured, other opcodes (lines, shapes, text, patterns, comments) are skipped, and clip
// and mask regions are reduced to their bounding rectangle. A picture that holds anything
// that cannot be walked (compressed QuickTime images, pixel patterns) is drawn up to that
// opcode. The layout of the format is described in "Imaging With QuickDraw".

#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSPICTImageRep.h>
#import <AppKit/NSPasteboard.h>
#import <ApplicationServices/ApplicationServices.h>

// One bitmap drawn by the picture: the decoded pixels cover pixelBounds (picture
// coordinates, y down); srcRect of them are drawn into dstRect, inside clipRect.
@interface NSPICTBitmap : NSObject {
@public
    CGImageRef image;
    CGRect pixelBounds;
    CGRect srcRect;
    CGRect dstRect;
    CGRect clipRect;
}
@end

@implementation NSPICTBitmap
- (void) dealloc {
    CGImageRelease(image);
    [super dealloc];
}
@end

typedef struct {
    int top, left, bottom, right;
} PICTRect;

typedef struct {
    const uint8_t *bytes;
    size_t length;
    size_t pos;
    BOOL failed;
} PICTReader;

static uint8_t readU8(PICTReader *r) {
    if (r->pos + 1 > r->length) {
        r->failed = YES;
        return 0;
    }
    return r->bytes[r->pos++];
}

static uint16_t readU16(PICTReader *r) {
    if (r->pos + 2 > r->length) {
        r->failed = YES;
        r->pos = r->length;
        return 0;
    }
    uint16_t v = (r->bytes[r->pos] << 8) | r->bytes[r->pos + 1];
    r->pos += 2;
    return v;
}

static void skipBytes(PICTReader *r, size_t count) {
    if (count > r->length - r->pos) {
        r->failed = YES;
        r->pos = r->length;
        return;
    }
    r->pos += count;
}

static PICTRect readRect(PICTReader *r) {
    PICTRect rect;

    rect.top = (int16_t) readU16(r);
    rect.left = (int16_t) readU16(r);
    rect.bottom = (int16_t) readU16(r);
    rect.right = (int16_t) readU16(r);
    return rect;
}

static CGRect cgRect(PICTRect r) {
    return CGRectMake(r.left, r.top, r.right - r.left, r.bottom - r.top);
}

// Where the picture data starts: files have 512 bytes of header in front of the picture,
// data from a pasteboard or a resource does not. Returns NSNotFound for anything that
// does not begin with a version 2 picture.
static size_t pictStart(const uint8_t *bytes, size_t length) {
    static const size_t candidates[] = {0, 512};
    int i;

    for (i = 0; i < 2; i++) {
        size_t start = candidates[i];

        // size (2), frame (8), version opcode (2) and version (2), header opcode (2)
        if (length < start + 10 + 6)
            continue;
        const uint8_t *v = bytes + start + 10;

        if (v[0] == 0x00 && v[1] == 0x11 && v[2] == 0x02 && v[3] == 0xff)
            return start;
    }
    return NSNotFound;
}

// PackBits: a count byte n >= 0 copies n+1 units, n < 0 repeats the next unit 1-n times.
// Returns the number of units written, stops at the end of either buffer.
static size_t unpackBits(const uint8_t *in, size_t inLength, uint8_t *out, size_t outUnits,
                         size_t unit) {
    size_t i = 0, o = 0;

    while (i < inLength && o < outUnits) {
        int8_t n = (int8_t) in[i++];

        if (n >= 0) {
            size_t count = (size_t) n + 1;

            while (count-- > 0 && o < outUnits && i + unit <= inLength) {
                memcpy(out + o * unit, in + i, unit);
                i += unit;
                o++;
            }
        } else {
            size_t count = (size_t) (1 - n);

            if (i + unit > inLength)
                break;
            while (count-- > 0 && o < outUnits) {
                memcpy(out + o * unit, in + i, unit);
                o++;
            }
            i += unit;
        }
    }
    return o;
}

static void releaseBuffer(void *info, const void *data, size_t size) {
    free((void *) data);
}

// Wraps premultiplied RGBA pixels (alpha always 255 here) in an image; takes the buffer.
static CGImageRef imageFromRGBA(uint8_t *pixels, int width, int height) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(
            NULL, pixels, (size_t) width * height * 4, releaseBuffer);
    CGImageRef image = CGImageCreate(width, height, 8, 32, (size_t) width * 4, space,
                                     kCGImageAlphaPremultipliedLast, provider, NULL, NO,
                                     kCGRenderingIntentDefault);

    CGDataProviderRelease(provider);
    CGColorSpaceRelease(space);
    return image;
}

typedef struct {
    int rowBytes;
    PICTRect bounds;
    int packType;
    int pixelSize;
    int cmpCount;
    uint8_t palette[256][3];
    int paletteCount;
    BOOL direct;
} PICTPixMap;

// Reads the pixel rows of one bitmap opcode into RGBA.
static uint8_t *decodePixels(PICTReader *r, const PICTPixMap *pm, int width, int height) {
    if (width <= 0 || height <= 0 || width > 16384 || height > 16384)
        return NULL;

    size_t rowBytes = (size_t) pm->rowBytes;
    uint8_t *rgba = calloc((size_t) width * height, 4);
    size_t planesBytes = (size_t) width * (pm->cmpCount > 4 ? 4 : (pm->cmpCount < 3 ? 3 : pm->cmpCount));
    size_t scanSize = rowBytes > planesBytes ? rowBytes : planesBytes;
    uint8_t *scan = malloc(scanSize > 0 ? scanSize : 1);
    int packType = pm->packType;
    int row;

    // Rows narrower than 8 bytes are never packed; pack type 0 means whatever suits the depth.
    BOOL packed = rowBytes >= 8 && packType != 1 && packType != 2;

    if (packType == 0)
        packType = pm->pixelSize == 32 ? 4 : (pm->pixelSize == 16 ? 3 : 0);

    for (row = 0; row < height && !r->failed; row++) {
        size_t cmpBytes = planesBytes;
        uint8_t *line = scan;

        memset(scan, 0, scanSize);
        if (packed) {
            size_t packedLength = rowBytes > 250 ? readU16(r) : readU8(r);

            if (r->failed || packedLength > r->length - r->pos) {
                r->failed = YES;
                break;
            }
            if (packType == 4) {
                unpackBits(r->bytes + r->pos, packedLength, scan, cmpBytes, 1);
            } else if (packType == 3) {
                unpackBits(r->bytes + r->pos, packedLength, scan, rowBytes / 2, 2);
            } else {
                unpackBits(r->bytes + r->pos, packedLength, scan, rowBytes, 1);
            }
            r->pos += packedLength;
        } else {
            size_t take = packType == 2 ? (size_t) width * 3 : rowBytes;

            if (take > r->length - r->pos) {
                r->failed = YES;
                break;
            }
            if (packType == 2) {
                // 32-bit pixels with the pad byte removed: R, G, B per pixel
                int x;

                for (x = 0; x < width; x++) {
                    scan[x * 4 + 1] = r->bytes[r->pos + x * 3];
                    scan[x * 4 + 2] = r->bytes[r->pos + x * 3 + 1];
                    scan[x * 4 + 3] = r->bytes[r->pos + x * 3 + 2];
                }
            } else {
                memcpy(scan, r->bytes + r->pos, take);
            }
            r->pos += take;
        }

        uint8_t *out = rgba + (size_t) row * width * 4;
        int x;

        for (x = 0; x < width; x++) {
            uint8_t red = 0, green = 0, blue = 0;

            if (pm->pixelSize == 16) {
                if ((size_t) x * 2 + 1 >= scanSize)
                    break;
                unsigned v = (line[x * 2] << 8) | line[x * 2 + 1];

                // 1-5-5-5; the 5-bit values are scaled to 8 bits rounding down
                red = ((v >> 10) & 31) * 255 / 31;
                green = ((v >> 5) & 31) * 255 / 31;
                blue = (v & 31) * 255 / 31;
            } else if (pm->pixelSize == 32) {
                if (packType == 4) {
                    // component planes: [alpha,] red, green, blue, each width bytes
                    int first = pm->cmpCount == 4 ? 1 : 0;

                    red = line[(size_t) (first + 0) * width + x];
                    green = line[(size_t) (first + 1) * width + x];
                    blue = line[(size_t) (first + 2) * width + x];
                } else {
                    // x, R, G, B per pixel
                    if ((size_t) x * 4 + 3 >= scanSize)
                        break;
                    red = line[x * 4 + 1];
                    green = line[x * 4 + 2];
                    blue = line[x * 4 + 3];
                }
            } else if (!pm->direct) {
                int depth = pm->pixelSize;
                size_t bit = (size_t) x * depth;
                size_t byte = bit / 8;

                if (byte >= rowBytes)
                    break;
                int shift = 8 - depth - (int) (bit % 8);
                int index = (line[byte] >> shift) & ((1 << depth) - 1);

                if (index < pm->paletteCount) {
                    red = pm->palette[index][0];
                    green = pm->palette[index][1];
                    blue = pm->palette[index][2];
                }
            }
            out[x * 4] = red;
            out[x * 4 + 1] = green;
            out[x * 4 + 2] = blue;
            out[x * 4 + 3] = 255;
        }
    }
    free(scan);
    return rgba;
}

// Adds the bitmap of a bitmap opcode (the opcode is already read). Returns NO when the
// picture cannot be walked any further.
static BOOL readBitmapOp(PICTReader *r, uint16_t op, CGRect clip, NSMutableArray *bitmaps) {
    PICTPixMap pm;
    BOOL hasRegion = (op == 0x91 || op == 0x99 || op == 0x9b);
    BOOL indexed = (op == 0x98 || op == 0x99);
    BOOL directOp = (op == 0x9a || op == 0x9b);

    memset(&pm, 0, sizeof(pm));
    if (directOp)
        skipBytes(r, 4); // base address, unused in a picture
    pm.rowBytes = readU16(r);
    BOOL isPixMap = (pm.rowBytes & 0x8000) != 0;

    pm.rowBytes &= 0x3fff;
    pm.bounds = readRect(r);
    if (isPixMap) {
        skipBytes(r, 2); // pmVersion
        pm.packType = (int16_t) readU16(r);
        skipBytes(r, 4 + 4 + 4); // packSize, hRes, vRes
        skipBytes(r, 2); // pixelType
        pm.pixelSize = (int16_t) readU16(r);
        pm.cmpCount = (int16_t) readU16(r);
        skipBytes(r, 2 + 4 + 4 + 4); // cmpSize, planeBytes, pmTable, pmReserved
        pm.direct = pm.pixelSize >= 16;
    } else {
        pm.pixelSize = 1;
        pm.palette[0][0] = pm.palette[0][1] = pm.palette[0][2] = 255;
        pm.paletteCount = 2; // 0 is white, 1 is black
    }
    if (isPixMap && indexed) {
        int count, i;

        skipBytes(r, 4); // seed
        int flags = readU16(r);

        count = (int16_t) readU16(r) + 1;
        for (i = 0; i < count && !r->failed; i++) {
            int value = readU16(r);
            uint8_t red = readU16(r) >> 8;
            uint8_t green = readU16(r) >> 8;
            uint8_t blue = readU16(r) >> 8;
            // In a device table the position is the index and the value field is not.
            int index = (flags & 0x8000) ? i : value;

            if (index >= 0 && index < 256) {
                pm.palette[index][0] = red;
                pm.palette[index][1] = green;
                pm.palette[index][2] = blue;
                if (index + 1 > pm.paletteCount)
                    pm.paletteCount = index + 1;
            }
        }
    }

    PICTRect src = readRect(r);
    PICTRect dst = readRect(r);

    skipBytes(r, 2); // transfer mode: always drawn as a copy
    if (hasRegion) {
        size_t regionSize = readU16(r);

        if (regionSize >= 2)
            skipBytes(r, regionSize - 2);
        else
            r->failed = YES;
    }
    if (r->failed)
        return NO;
    if (isPixMap && pm.pixelSize != 1 && pm.pixelSize != 2 && pm.pixelSize != 4 &&
        pm.pixelSize != 8 && pm.pixelSize != 16 && pm.pixelSize != 32)
        return NO;

    int width = pm.bounds.right - pm.bounds.left;
    int height = pm.bounds.bottom - pm.bounds.top;
    uint8_t *rgba = decodePixels(r, &pm, width, height);

    if (rgba == NULL)
        return NO;

    NSPICTBitmap *bitmap = [[NSPICTBitmap alloc] init];

    bitmap->image = imageFromRGBA(rgba, width, height);
    bitmap->pixelBounds = cgRect(pm.bounds);
    bitmap->srcRect = cgRect(src);
    bitmap->dstRect = cgRect(dst);
    bitmap->clipRect = clip;
    [bitmaps addObject: bitmap];
    [bitmap release];
    return !r->failed;
}

// Number of bytes that follow an opcode this decoder does not draw, or -1 when the opcode
// has a variable length that is not described by a leading size, so it cannot be walked.
static long skipLength(PICTReader *r, uint16_t op) {
    if (op < 0x0100) {
        switch (op) {
        case 0x00: case 0x1c: case 0x1e: case 0x17: case 0x18: case 0x19:
            return 0;
        case 0x11:
            return 1;
        case 0x03: case 0x05: case 0x08: case 0x0d: case 0x15: case 0x16:
            return 2;
        case 0x04:
            return 1;
        case 0x06: case 0x07: case 0x0b: case 0x0c: case 0x0e: case 0x0f: case 0x21:
            return 4;
        case 0x22:
        case 0x1a: case 0x1b: case 0x1d: case 0x1f:
            return 6;
        case 0x23:
            return 2;
        case 0x02: case 0x09: case 0x0a: case 0x10: case 0x20: case 0x2e:
            return 8;
        case 0x2d:
            return 10;
        case 0x12: case 0x13: case 0x14:
            return -1; // pixel patterns
        case 0x28: // LongText: point, count byte, text
        {
            if (r->pos + 5 > r->length)
                return -1;
            return 4 + 1 + r->bytes[r->pos + 4];
        }
        case 0x29: case 0x2a: // DHText, DVText: offset byte, count byte, text
        {
            if (r->pos + 2 > r->length)
                return -1;
            return 2 + r->bytes[r->pos + 1];
        }
        case 0x2b: // DHDVText
        {
            if (r->pos + 3 > r->length)
                return -1;
            return 3 + r->bytes[r->pos + 2];
        }
        case 0x2c: // FontName: size, old font id, name length, name
        {
            if (r->pos + 2 > r->length)
                return -1;
            return 2 + ((r->bytes[r->pos] << 8) | r->bytes[r->pos + 1]);
        }
        case 0xa0:
            return 2;
        case 0xa1: // LongComment: kind, size, data
        {
            if (r->pos + 4 > r->length)
                return -1;
            return 4 + ((r->bytes[r->pos + 2] << 8) | r->bytes[r->pos + 3]);
        }
        case 0xff:
            return 0;
        }
        if (op >= 0x30 && op <= 0x37)
            return 8; // rectangles
        if (op >= 0x38 && op <= 0x3f)
            return 0;
        if (op >= 0x40 && op <= 0x47)
            return 8; // rounded rectangles
        if (op >= 0x48 && op <= 0x4f)
            return 0;
        if (op >= 0x50 && op <= 0x57)
            return 8; // ovals
        if (op >= 0x58 && op <= 0x5f)
            return 0;
        if (op >= 0x60 && op <= 0x67)
            return 12; // arcs
        if (op >= 0x68 && op <= 0x6f)
            return 4;
        if ((op >= 0x24 && op <= 0x27) || op == 0x2f || (op >= 0x70 && op <= 0x7f) ||
            (op >= 0x80 && op <= 0x8f) || (op >= 0x92 && op <= 0x97) ||
            (op >= 0x9c && op <= 0x9f) || (op >= 0xa2 && op <= 0xaf)) {
            // polygons, regions and reserved opcodes with a two byte size that counts itself
            if (op >= 0x78 && op <= 0x7f)
                return 0;
            if (op >= 0x88 && op <= 0x8f)
                return 0;
            if (r->pos + 2 > r->length)
                return -1;
            long size = (r->bytes[r->pos] << 8) | r->bytes[r->pos + 1];

            return (op >= 0x24 && op <= 0x27) || op == 0x2f || (op >= 0x92 && op <= 0x97) ||
                           (op >= 0x9c && op <= 0x9f) || (op >= 0xa2 && op <= 0xaf)
                    ? 2 + size
                    : size;
        }
        if (op >= 0xb0 && op <= 0xcf)
            return 0;
        if (op >= 0xd0)
            goto longSized;
        return -1;
    }
    if (op < 0x8000)
        return (op >> 8) * 2; // reserved: the high byte is the length in words
    if (op < 0x8100)
        return 0;
longSized:
    if (r->pos + 4 > r->length)
        return -1;
    return 4 + (long) (((uint32_t) r->bytes[r->pos] << 24) | (r->bytes[r->pos + 1] << 16) |
                       (r->bytes[r->pos + 2] << 8) | r->bytes[r->pos + 3]);
}

@implementation NSPICTImageRep

+ (NSArray *) imageUnfilteredFileTypes {
    return [NSArray arrayWithObjects: @"pict", @"PICT", @"pct", @"PCT", @"pic", @"PIC",
                                      @"'PICT'", nil];
}

+ (NSArray *) imageUnfilteredPasteboardTypes {
    return [NSArray arrayWithObject: NSPICTPboardType];
}

+ (BOOL) canInitWithData: (NSData *) data {
    return pictStart([data bytes], [data length]) != NSNotFound;
}

+ (NSArray *) imageRepsWithData: (NSData *) data {
    id result = [self imageRepWithData: data];

    if (result == nil)
        return nil;

    return [NSArray arrayWithObject: result];
}

+ imageRepWithData: (NSData *) data {
    return [[[self alloc] initWithData: data] autorelease];
}

+ (NSArray *) imageRepsWithContentsOfFile: (NSString *) path {
    NSData *data = [NSData dataWithContentsOfFile: path];

    if (data == nil)
        return nil;
    return [self imageRepsWithData: data];
}

- initWithData: (NSData *) data {
    const uint8_t *bytes = [data bytes];
    size_t length = [data length];
    size_t start = pictStart(bytes, length);

    if (start == NSNotFound) {
        [self release];
        return nil;
    }
    if ((self = [super init]) == nil)
        return nil;

    // The representation is the picture without the file header.
    NS_EXTRA(NSPICTImageRep, self)->_pict = [[data subdataWithRange: NSMakeRange(start, length - start)] retain];
    bytes = [NS_EXTRA(NSPICTImageRep, self)->_pict bytes];
    length = [NS_EXTRA(NSPICTImageRep, self)->_pict length];

    PICTReader reader = {bytes, length, 2, NO};
    PICTRect frame = readRect(&reader);

    NS_EXTRA(NSPICTImageRep, self)->_boundingBox = NSMakeRect(frame.left, frame.top, frame.right - frame.left,
                              frame.bottom - frame.top);
    _size = NS_EXTRA(NSPICTImageRep, self)->_boundingBox.size;
    _pixelsWide = (int) _size.width;
    _pixelsHigh = (int) _size.height;
    _colorSpaceName = [NSDeviceRGBColorSpace copy];
    _hasAlpha = NO;
    _isOpaque = NO;
    _bitsPerSample = 8;

    NS_EXTRA(NSPICTImageRep, self)->_bitmaps = [[NSMutableArray alloc] init];

    CGRect clip = cgRect(frame);

    skipBytes(&reader, 4); // version opcode and version 2
    readU16(&reader); // header opcode
    skipBytes(&reader, 24);
    while (!reader.failed && reader.pos + 2 <= length) {
        if (reader.pos & 1)
            reader.pos++; // opcodes start on a word boundary
        uint16_t op = readU16(&reader);

        if (op == 0xff)
            break;
        if (op == 0x01) {
            // Clip: a region, whose bounding rectangle is used
            size_t size = readU16(&reader);

            if (size >= 10) {
                PICTRect box = readRect(&reader);

                clip = CGRectIntersection(cgRect(frame), cgRect(box));
                skipBytes(&reader, size - 10);
            } else if (size >= 2) {
                skipBytes(&reader, size - 2);
            } else {
                break;
            }
            continue;
        }
        if (op == 0x90 || op == 0x91 || op == 0x98 || op == 0x99 || op == 0x9a ||
            op == 0x9b) {
            if (!readBitmapOp(&reader, op, clip, NS_EXTRA(NSPICTImageRep, self)->_bitmaps))
                break;
            continue;
        }

        long skip = skipLength(&reader, op);

        if (skip < 0)
            break;
        skipBytes(&reader, (size_t) skip);
    }
    return self;
}

- (void) dealloc {
    [NS_EXTRA(NSPICTImageRep, self)->_pict release];
    [NS_EXTRA(NSPICTImageRep, self)->_bitmaps release];
    NS_EXTRA_FREE(NSPICTImageRep, self);
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSPICTImageRep *result = [super copyWithZone: zone];
    NS_EXTRA_COPY(NSPICTImageRep, result, self);

    NS_EXTRA(NSPICTImageRep, result)->_pict = [NS_EXTRA(NSPICTImageRep, self)->_pict retain];
    NS_EXTRA(NSPICTImageRep, result)->_bitmaps = [NS_EXTRA(NSPICTImageRep, self)->_bitmaps retain];
    return result;
}

- (NSData *) PICTRepresentation {
    return NS_EXTRA(NSPICTImageRep, self)->_pict;
}

- (NSRect) boundingBox {
    return NS_EXTRA(NSPICTImageRep, self)->_boundingBox;
}

- (BOOL) draw {
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    NSSize size = NS_EXTRA(NSPICTImageRep, self)->_boundingBox.size;

    if (context == NULL)
        return NO;
    if (size.width <= 0 || size.height <= 0)
        return NO;

    CGContextSaveGState(context);
    // Picture coordinates have y pointing down from the frame's top left corner.
    CGContextTranslateCTM(context, -NS_EXTRA(NSPICTImageRep, self)->_boundingBox.origin.x,
                          NS_EXTRA(NSPICTImageRep, self)->_boundingBox.origin.y + size.height);
    CGContextScaleCTM(context, 1, -1);
    for (NSPICTBitmap *bitmap in NS_EXTRA(NSPICTImageRep, self)->_bitmaps) {
        CGRect pixels = bitmap->pixelBounds;
        CGRect src = bitmap->srcRect;
        CGRect dst = bitmap->dstRect;

        if (src.size.width <= 0 || src.size.height <= 0 || dst.size.width <= 0 ||
            dst.size.height <= 0)
            continue;

        // The source rectangle is scaled to the destination rectangle, which places the
        // whole bitmap; only the part inside the source rectangle (and the clip) shows.
        double sx = dst.size.width / src.size.width;
        double sy = dst.size.height / src.size.height;
        CGRect whole = CGRectMake(dst.origin.x + (pixels.origin.x - src.origin.x) * sx,
                                  dst.origin.y + (pixels.origin.y - src.origin.y) * sy,
                                  pixels.size.width * sx, pixels.size.height * sy);
        CGRect visible = CGRectIntersection(CGRectIntersection(whole, dst), bitmap->clipRect);

        if (CGRectIsNull(visible) || CGRectIsEmpty(visible))
            continue;

        CGContextSaveGState(context);
        if (!CGRectEqualToRect(visible, whole))
            CGContextClipToRect(context, visible);
        // The context is flipped, so the image is drawn flipped back around its own rectangle.
        CGContextTranslateCTM(context, 0, whole.origin.y * 2 + whole.size.height);
        CGContextScaleCTM(context, 1, -1);
        CGContextSetInterpolationQuality(context, kCGInterpolationNone);
        CGContextDrawImage(context, whole, bitmap->image);
        CGContextRestoreGState(context);
    }
    CGContextRestoreGState(context);
    return YES;
}

@end
