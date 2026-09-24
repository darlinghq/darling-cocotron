#import "CACoding.h"

static NSString *subkey(NSString *key, NSString *suffix) {
    return [key stringByAppendingString: suffix];
}

static void cannotArchive(NSString *key, NSString *reason) {
    [NSException raise: NSInvalidArchiveOperationException
                format: @"Cannot archive %@: %@", key, reason];
}

static void malformed(NSString *key, NSString *reason) {
    [NSException raise: NSInvalidUnarchiveOperationException
                format: @"Malformed archive for %@: %@", key, reason];
}

void CARequireKeyedCoder(NSCoder *coder) {
    if (![coder allowsKeyedCoding])
        [NSException raise: NSInvalidArgumentException
                    format: @"Core Animation layers need a keyed coder, not %@", [coder class]];
}

void CAEncodeDoubles(NSCoder *coder, const double *values, size_t count, NSString *key) {
    [coder encodeBytes: (const uint8_t *) values length: count * sizeof(double) forKey: key];
}

void CADecodeDoubles(NSCoder *coder, double *values, size_t count, NSString *key) {
    NSUInteger length = 0;
    const uint8_t *bytes = [coder decodeBytesForKey: key returnedLength: &length];
    if (bytes == NULL || length != count * sizeof(double))
        malformed(key, [NSString stringWithFormat: @"expected %zu doubles", count]);
    memcpy(values, bytes, length);
}

void CAEncodePoint(NSCoder *coder, CGPoint point, NSString *key) {
    double v[2] = {point.x, point.y};
    CAEncodeDoubles(coder, v, 2, key);
}

CGPoint CADecodePoint(NSCoder *coder, NSString *key) {
    double v[2];
    CADecodeDoubles(coder, v, 2, key);
    return CGPointMake(v[0], v[1]);
}

void CAEncodeSize(NSCoder *coder, CGSize size, NSString *key) {
    double v[2] = {size.width, size.height};
    CAEncodeDoubles(coder, v, 2, key);
}

CGSize CADecodeSize(NSCoder *coder, NSString *key) {
    double v[2];
    CADecodeDoubles(coder, v, 2, key);
    return CGSizeMake(v[0], v[1]);
}

void CAEncodeRect(NSCoder *coder, CGRect rect, NSString *key) {
    double v[4] = {rect.origin.x, rect.origin.y, rect.size.width, rect.size.height};
    CAEncodeDoubles(coder, v, 4, key);
}

CGRect CADecodeRect(NSCoder *coder, NSString *key) {
    double v[4];
    CADecodeDoubles(coder, v, 4, key);
    return CGRectMake(v[0], v[1], v[2], v[3]);
}

void CAEncodeTransform3D(NSCoder *coder, CATransform3D t, NSString *key) {
    const CGFloat *m = &t.m11;
    double v[16];
    for (int i = 0; i < 16; i++)
        v[i] = m[i];
    CAEncodeDoubles(coder, v, 16, key);
}

CATransform3D CADecodeTransform3D(NSCoder *coder, NSString *key) {
    double v[16];
    CADecodeDoubles(coder, v, 16, key);
    CATransform3D t;
    CGFloat *m = &t.m11;
    for (int i = 0; i < 16; i++)
        m[i] = v[i];
    return t;
}

// A color space is archived by name when it has one, otherwise by its device
// model; anything else (pattern, indexed, DeviceN) has no faithful form here.
static void encodeColorSpace(NSCoder *coder, CGColorSpaceRef space, NSString *key) {
    CFStringRef name = CGColorSpaceGetName(space);
    if (name != NULL) {
        CGColorSpaceRef check = CGColorSpaceCreateWithName(name);
        if (check == NULL)
            cannotArchive(key, [NSString stringWithFormat: @"unknown color space %@", name]);
        CGColorSpaceRelease(check);
        [coder encodeObject: (NSString *) name forKey: subkey(key, @".space")];
        return;
    }
    CGColorSpaceModel model = CGColorSpaceGetModel(space);
    if (model != kCGColorSpaceModelRGB && model != kCGColorSpaceModelMonochrome &&
        model != kCGColorSpaceModelCMYK)
        cannotArchive(key, [NSString stringWithFormat: @"color space model %d", (int) model]);
    [coder encodeInt: model forKey: subkey(key, @".model")];
}

static CGColorSpaceRef decodeColorSpace(NSCoder *coder, NSString *key) {
    NSString *name = [coder decodeObjectOfClass: [NSString class] forKey: subkey(key, @".space")];
    CGColorSpaceRef space = NULL;
    if (name != nil) {
        space = CGColorSpaceCreateWithName((CFStringRef) name);
    } else if ([coder containsValueForKey: subkey(key, @".model")]) {
        switch ([coder decodeIntForKey: subkey(key, @".model")]) {
        case kCGColorSpaceModelRGB:
            space = CGColorSpaceCreateDeviceRGB();
            break;
        case kCGColorSpaceModelMonochrome:
            space = CGColorSpaceCreateDeviceGray();
            break;
        case kCGColorSpaceModelCMYK:
            space = CGColorSpaceCreateDeviceCMYK();
            break;
        }
    }
    if (space == NULL)
        malformed(key, @"missing or unknown color space");
    return space;
}

void CAEncodeColor(NSCoder *coder, CGColorRef color, NSString *key) {
    if (color == NULL)
        return;
    if (CGColorGetPattern(color) != NULL)
        cannotArchive(key, @"pattern colors");
    encodeColorSpace(coder, CGColorGetColorSpace(color), key);
    size_t count = CGColorGetNumberOfComponents(color);
    const CGFloat *components = CGColorGetComponents(color);
    double v[count];
    for (size_t i = 0; i < count; i++)
        v[i] = components[i];
    CAEncodeDoubles(coder, v, count, key);
}

CGColorRef CADecodeColor(NSCoder *coder, NSString *key) {
    if (![coder containsValueForKey: key])
        return NULL;
    CGColorSpaceRef space = decodeColorSpace(coder, key);
    size_t count = CGColorSpaceGetNumberOfComponents(space) + 1;
    double v[count];
    CADecodeDoubles(coder, v, count, key);
    CGFloat components[count];
    for (size_t i = 0; i < count; i++)
        components[i] = v[i];
    CGColorRef color = CGColorCreate(space, components);
    CGColorSpaceRelease(space);
    return color;
}

// A path is archived as its elements: each a type followed by its points.
static size_t pointCount(CGPathElementType type) {
    switch (type) {
    case kCGPathElementMoveToPoint:
    case kCGPathElementAddLineToPoint:
        return 1;
    case kCGPathElementAddQuadCurveToPoint:
        return 2;
    case kCGPathElementAddCurveToPoint:
        return 3;
    default:
        return 0;
    }
}

static void appendElement(void *info, const CGPathElement *element) {
    NSMutableData *data = info;
    double type = element->type;
    [data appendBytes: &type length: sizeof(type)];
    for (size_t i = 0; i < pointCount(element->type); i++) {
        double xy[2] = {element->points[i].x, element->points[i].y};
        [data appendBytes: xy length: sizeof(xy)];
    }
}

void CAEncodePath(NSCoder *coder, CGPathRef path, NSString *key) {
    if (path == NULL)
        return;
    NSMutableData *data = [NSMutableData data];
    CGPathApply(path, data, appendElement);
    [coder encodeBytes: [data bytes] length: [data length] forKey: key];
}

CGPathRef CADecodePath(NSCoder *coder, NSString *key) {
    if (![coder containsValueForKey: key])
        return NULL;
    NSUInteger length = 0;
    const uint8_t *bytes = [coder decodeBytesForKey: key returnedLength: &length];
    if (length % sizeof(double) != 0)
        malformed(key, @"truncated path");
    size_t count = length / sizeof(double), i = 0;

    CGMutablePathRef path = CGPathCreateMutable();
    while (i < count) {
        double type, p[6];
        memcpy(&type, bytes + i++ * sizeof(double), sizeof(double));
        if (!(type >= kCGPathElementMoveToPoint && type <= kCGPathElementCloseSubpath) || type != (int) type) {
            CGPathRelease(path);
            malformed(key, @"bad path element");
        }
        size_t n = pointCount((CGPathElementType) type);
        if (i + 2 * n > count) {
            CGPathRelease(path);
            malformed(key, @"truncated path element");
        }
        memcpy(p, bytes + i * sizeof(double), 2 * n * sizeof(double));
        switch ((CGPathElementType) type) {
        case kCGPathElementMoveToPoint:
            CGPathMoveToPoint(path, NULL, p[0], p[1]);
            break;
        case kCGPathElementAddLineToPoint:
            CGPathAddLineToPoint(path, NULL, p[0], p[1]);
            break;
        case kCGPathElementAddQuadCurveToPoint:
            CGPathAddQuadCurveToPoint(path, NULL, p[0], p[1], p[2], p[3]);
            break;
        case kCGPathElementAddCurveToPoint:
            CGPathAddCurveToPoint(path, NULL, p[0], p[1], p[2], p[3], p[4], p[5]);
            break;
        case kCGPathElementCloseSubpath:
            CGPathCloseSubpath(path);
            break;
        }
        i += 2 * n;
    }
    return path;
}

// An image is archived as its pixel data and the parameters CGImageCreate
// needs to rebuild it. Masks and images with a decode array are rejected.
void CAEncodeImage(NSCoder *coder, CGImageRef image, NSString *key) {
    if (image == NULL)
        return;
    if (CGImageIsMask(image))
        cannotArchive(key, @"image masks");
    if (CGImageGetDecode(image) != NULL)
        cannotArchive(key, @"images with a decode array");
    CGDataProviderRef provider = CGImageGetDataProvider(image);
    CFDataRef data = provider ? CGDataProviderCopyData(provider) : NULL;
    if (data == NULL)
        cannotArchive(key, @"the image's pixel data is not available");
    size_t height = CGImageGetHeight(image), bytesPerRow = CGImageGetBytesPerRow(image);
    if ((size_t) CFDataGetLength(data) < height * bytesPerRow) {
        CFRelease(data);
        cannotArchive(key, @"the image's pixel data is shorter than its size");
    }
    encodeColorSpace(coder, CGImageGetColorSpace(image), key);
    [coder encodeInt64: CGImageGetWidth(image) forKey: subkey(key, @".width")];
    [coder encodeInt64: height forKey: subkey(key, @".height")];
    [coder encodeInt64: CGImageGetBitsPerComponent(image) forKey: subkey(key, @".bitsPerComponent")];
    [coder encodeInt64: CGImageGetBitsPerPixel(image) forKey: subkey(key, @".bitsPerPixel")];
    [coder encodeInt64: bytesPerRow forKey: subkey(key, @".bytesPerRow")];
    [coder encodeInt64: CGImageGetBitmapInfo(image) forKey: subkey(key, @".bitmapInfo")];
    [coder encodeBool: CGImageGetShouldInterpolate(image) forKey: subkey(key, @".interpolate")];
    [coder encodeInt: CGImageGetRenderingIntent(image) forKey: subkey(key, @".intent")];
    [coder encodeBytes: CFDataGetBytePtr(data) length: height * bytesPerRow forKey: key];
    CFRelease(data);
}

CGImageRef CADecodeImage(NSCoder *coder, NSString *key) {
    if (![coder containsValueForKey: key])
        return NULL;
    CGColorSpaceRef space = decodeColorSpace(coder, key);
    int64_t width = [coder decodeInt64ForKey: subkey(key, @".width")];
    int64_t height = [coder decodeInt64ForKey: subkey(key, @".height")];
    int64_t bpc = [coder decodeInt64ForKey: subkey(key, @".bitsPerComponent")];
    int64_t bpp = [coder decodeInt64ForKey: subkey(key, @".bitsPerPixel")];
    int64_t bytesPerRow = [coder decodeInt64ForKey: subkey(key, @".bytesPerRow")];
    NSUInteger length = 0;
    const uint8_t *bytes = [coder decodeBytesForKey: key returnedLength: &length];
    if (width <= 0 || height <= 0 || bpc <= 0 || bpp < bpc || bpp > 128 || bytesPerRow <= 0 ||
        length % height != 0 || (int64_t)(length / height) != bytesPerRow || width > bytesPerRow * 8 / bpp) {
        CGColorSpaceRelease(space);
        malformed(key, @"inconsistent image size");
    }
    NSData *pixels = [NSData dataWithBytes: bytes length: length];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef) pixels);
    CGImageRef image = CGImageCreate(width, height, bpc, bpp, bytesPerRow, space,
                                     (CGBitmapInfo)[coder decodeInt64ForKey: subkey(key, @".bitmapInfo")],
                                     provider, NULL, [coder decodeBoolForKey: subkey(key, @".interpolate")],
                                     (CGColorRenderingIntent)[coder decodeIntForKey: subkey(key, @".intent")]);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(space);
    if (image == NULL)
        malformed(key, @"CGImageCreate failed");
    return image;
}
