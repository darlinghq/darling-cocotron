/* Copyright (c) 2026 Darling developers

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

// NIBArchive layout (all integers little-endian):
//   "NIBArchive", uint32 formatVersion, uint32 coderVersion,
//   uint32 objectCount, objectsOffset, keyCount, keysOffset, valueCount, valuesOffset,
//          classNameCount, classNamesOffset
//   object:    varint classNameIndex, varint firstValueIndex, varint valueCount
//   key:       varint length, bytes
//   value:     varint keyIndex, uint8 type, payload (see NibValueType)
//   className: varint length, varint extraCount, int32 extras[extraCount], bytes (NUL-terminated)
// Varints store 7 bits per byte, least significant group first; the high bit marks the LAST byte.
// Object 0 is the root. Collections store their elements as repeated "UINibEncoderEmptyKey" values
// (dictionaries alternate key and value).

#import "NSNibArchive.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/NSString.h>
#include <string.h>

// CoreFoundation SPI (CFKeyedArchiverUIDRef comes from CoreFoundation's private headers).
extern CFKeyedArchiverUIDRef _CFKeyedArchiverUIDCreate(CFAllocatorRef allocator, uint32_t value);

enum NibValueType {
    NibValueInt8 = 0,
    NibValueInt16 = 1,
    NibValueInt32 = 2,
    NibValueInt64 = 3,
    NibValueTrue = 4,
    NibValueFalse = 5,
    NibValueFloat = 6,
    NibValueDouble = 7,
    NibValueData = 8,
    NibValueNil = 9,
    NibValueObject = 10,
};

typedef struct {
    CFIndex keyIndex;
    uint8_t type;
    int64_t integer;
    double real;
    const uint8_t *bytes;
    CFIndex length;
    uint32_t object;
} NibValue;

typedef struct {
    CFIndex classIndex;
    CFIndex firstValue;
    CFIndex valueCount;
} NibObject;

typedef struct {
    const uint8_t *bytes;
    size_t length;
    CFIndex objectCount, keyCount, valueCount, classCount;
    NibObject *objects;
    CFStringRef *keys;
    NibValue *values;
    CFStringRef *classNames;
} NibArchive;

static const char kNibArchiveMagic[] = "NIBArchive";

BOOL NSNibArchiveDataIsNibArchive(NSData *data)
{
    return [data length] >= 50 && memcmp([data bytes], kNibArchiveMagic, 10) == 0;
}

static BOOL readVarint(const NibArchive *nib, size_t *offset, CFIndex *result)
{
    uint64_t value = 0;
    for (unsigned shift = 0; shift < 63; shift += 7) {
        if (*offset >= nib->length)
            return NO;
        uint8_t byte = nib->bytes[(*offset)++];
        value |= (uint64_t) (byte & 0x7f) << shift;
        if (byte & 0x80) {
            if (value > (uint64_t) LONG_MAX)
                return NO;
            *result = (CFIndex) value;
            return YES;
        }
    }
    return NO;
}

static BOOL readFixed(const NibArchive *nib, size_t *offset, void *out, size_t size)
{
    if (*offset > nib->length || nib->length - *offset < size)
        return NO;
    memcpy(out, nib->bytes + *offset, size);
    *offset += size;
    return YES;
}

static void freeNibArchive(NibArchive *nib)
{
    for (CFIndex i = 0; nib->keys && i < nib->keyCount; i++)
        if (nib->keys[i])
            CFRelease(nib->keys[i]);
    for (CFIndex i = 0; nib->classNames && i < nib->classCount; i++)
        if (nib->classNames[i])
            CFRelease(nib->classNames[i]);
    free(nib->objects);
    free(nib->keys);
    free(nib->values);
    free(nib->classNames);
}

static BOOL parseNibArchive(NibArchive *nib)
{
    uint32_t header[10];
    size_t offset = 10;
    if (!readFixed(nib, &offset, header, sizeof(header)))
        return NO;

    uint32_t objectsOffset = header[3], keysOffset = header[5], valuesOffset = header[7], classesOffset = header[9];
    nib->objectCount = header[2];
    nib->keyCount = header[4];
    nib->valueCount = header[6];
    nib->classCount = header[8];

    // Each record takes at least 1-3 bytes, which bounds the counts by the file size.
    if ((size_t) nib->objectCount > nib->length || (size_t) nib->keyCount > nib->length ||
        (size_t) nib->valueCount > nib->length || (size_t) nib->classCount > nib->length || nib->objectCount == 0)
        return NO;

    nib->objects = calloc(nib->objectCount, sizeof(NibObject));
    nib->keys = calloc(nib->keyCount ? nib->keyCount : 1, sizeof(CFStringRef));
    nib->values = calloc(nib->valueCount ? nib->valueCount : 1, sizeof(NibValue));
    nib->classNames = calloc(nib->classCount ? nib->classCount : 1, sizeof(CFStringRef));
    if (!nib->objects || !nib->keys || !nib->values || !nib->classNames)
        return NO;

    offset = keysOffset;
    for (CFIndex i = 0; i < nib->keyCount; i++) {
        CFIndex length;
        if (!readVarint(nib, &offset, &length) || (size_t) length > nib->length - offset)
            return NO;
        nib->keys[i] = CFStringCreateWithBytes(kCFAllocatorDefault, nib->bytes + offset, length, kCFStringEncodingUTF8, false);
        if (!nib->keys[i])
            return NO;
        offset += length;
    }

    offset = classesOffset;
    for (CFIndex i = 0; i < nib->classCount; i++) {
        CFIndex length, extraCount;
        if (!readVarint(nib, &offset, &length) || !readVarint(nib, &offset, &extraCount))
            return NO;
        if ((size_t) extraCount > (nib->length - offset) / 4)
            return NO;
        offset += 4 * extraCount;
        if ((size_t) length > nib->length - offset)
            return NO;
        CFIndex nameLength = length;
        while (nameLength > 0 && nib->bytes[offset + nameLength - 1] == 0)
            nameLength--;
        nib->classNames[i] = CFStringCreateWithBytes(kCFAllocatorDefault, nib->bytes + offset, nameLength, kCFStringEncodingUTF8, false);
        if (!nib->classNames[i])
            return NO;
        offset += length;
    }

    offset = valuesOffset;
    for (CFIndex i = 0; i < nib->valueCount; i++) {
        NibValue *value = &nib->values[i];
        if (!readVarint(nib, &offset, &value->keyIndex) || value->keyIndex >= nib->keyCount)
            return NO;
        if (!readFixed(nib, &offset, &value->type, 1))
            return NO;
        switch (value->type) {
        case NibValueInt8: {
            int8_t v;
            if (!readFixed(nib, &offset, &v, sizeof(v)))
                return NO;
            value->integer = v;
            break;
        }
        case NibValueInt16: {
            int16_t v;
            if (!readFixed(nib, &offset, &v, sizeof(v)))
                return NO;
            value->integer = v;
            break;
        }
        case NibValueInt32: {
            int32_t v;
            if (!readFixed(nib, &offset, &v, sizeof(v)))
                return NO;
            value->integer = v;
            break;
        }
        case NibValueInt64:
            if (!readFixed(nib, &offset, &value->integer, sizeof(int64_t)))
                return NO;
            break;
        case NibValueTrue:
        case NibValueFalse:
        case NibValueNil:
            break;
        case NibValueFloat: {
            float v;
            if (!readFixed(nib, &offset, &v, sizeof(v)))
                return NO;
            value->real = v;
            break;
        }
        case NibValueDouble:
            if (!readFixed(nib, &offset, &value->real, sizeof(double)))
                return NO;
            break;
        case NibValueData:
            if (!readVarint(nib, &offset, &value->length) || (size_t) value->length > nib->length - offset)
                return NO;
            value->bytes = nib->bytes + offset;
            offset += value->length;
            break;
        case NibValueObject:
            if (!readFixed(nib, &offset, &value->object, sizeof(uint32_t)) || value->object >= (uint32_t) nib->objectCount)
                return NO;
            break;
        default:
            return NO;
        }
    }

    offset = objectsOffset;
    for (CFIndex i = 0; i < nib->objectCount; i++) {
        NibObject *object = &nib->objects[i];
        if (!readVarint(nib, &offset, &object->classIndex) || !readVarint(nib, &offset, &object->firstValue) ||
            !readVarint(nib, &offset, &object->valueCount))
            return NO;
        if (object->classIndex >= nib->classCount || object->firstValue > nib->valueCount ||
            object->valueCount > nib->valueCount - object->firstValue)
            return NO;
    }
    return YES;
}

typedef struct {
    NibArchive *nib;
    CFMutableArrayRef objects;       // the keyed archive's $objects
    CFMutableDictionaryRef classes;  // class name -> $objects index of its class description
} Converter;

static CFTypeRef createUID(CFIndex index)
{
    return (CFTypeRef) _CFKeyedArchiverUIDCreate(kCFAllocatorDefault, (uint32_t) index);
}

// $objects index of NIB object `index`: slot 0 is "$null", NIB objects follow in order.
static CFIndex slotForObject(uint32_t index)
{
    return (CFIndex) index + 1;
}

static CFIndex classSlot(Converter *c, CFStringRef className)
{
    CFNumberRef existing = CFDictionaryGetValue(c->classes, className);
    CFIndex slot;
    if (existing) {
        CFNumberGetValue(existing, kCFNumberCFIndexType, &slot);
        return slot;
    }

    CFMutableDictionaryRef description = CFDictionaryCreateMutable(kCFAllocatorDefault, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(description, CFSTR("$classname"), className);
    CFStringRef hierarchy[2] = { className, CFSTR("NSObject") };
    CFArrayRef classes = CFArrayCreate(kCFAllocatorDefault, (const void **) hierarchy, 2, &kCFTypeArrayCallBacks);
    CFDictionarySetValue(description, CFSTR("$classes"), classes);
    CFRelease(classes);

    slot = CFArrayGetCount(c->objects);
    CFArrayAppendValue(c->objects, description);
    CFRelease(description);

    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberCFIndexType, &slot);
    CFDictionarySetValue(c->classes, className, number);
    CFRelease(number);
    return slot;
}

// Plist representation of a primitive value, as NSKeyedArchiver stores it inline.
static CFTypeRef createPrimitive(const NibValue *value)
{
    switch (value->type) {
    case NibValueInt8:
    case NibValueInt16:
    case NibValueInt32:
    case NibValueInt64:
        return CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &value->integer);
    case NibValueTrue:
        return CFRetain(kCFBooleanTrue);
    case NibValueFalse:
        return CFRetain(kCFBooleanFalse);
    case NibValueFloat:
    case NibValueDouble:
        return CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &value->real);
    case NibValueData:
        return CFDataCreate(kCFAllocatorDefault, value->bytes, value->length);
    default:
        return NULL;
    }
}

// Value for a key of a keyed-archive object dictionary.
static CFTypeRef createMember(const NibValue *value)
{
    if (value->type == NibValueObject)
        return createUID(slotForObject(value->object));
    if (value->type == NibValueNil)
        return createUID(0);
    return createPrimitive(value);
}

// UID of an element of a collection, which must reference an entry of $objects.
static CFTypeRef createElementUID(Converter *c, const NibValue *value)
{
    if (value->type == NibValueObject)
        return createUID(slotForObject(value->object));
    CFTypeRef primitive = createPrimitive(value);
    if (!primitive)
        return createUID(0);
    CFIndex slot = CFArrayGetCount(c->objects);
    CFArrayAppendValue(c->objects, primitive);
    CFRelease(primitive);
    return createUID(slot);
}

static const NibValue *findValue(const NibArchive *nib, const NibObject *object, CFStringRef key)
{
    const NibValue *found = NULL;
    for (CFIndex i = 0; i < object->valueCount; i++) {
        const NibValue *value = &nib->values[object->firstValue + i];
        if (CFEqual(nib->keys[value->keyIndex], key))
            found = value;
    }
    return found;
}

static BOOL classIsOneOf(CFStringRef className, const char *const names[])
{
    for (int i = 0; names[i]; i++) {
        CFStringRef name = CFStringCreateWithCString(kCFAllocatorDefault, names[i], kCFStringEncodingASCII);
        Boolean equal = CFEqual(className, name);
        CFRelease(name);
        if (equal)
            return YES;
    }
    return NO;
}

static CFTypeRef createConvertedObject(Converter *c, CFIndex index)
{
    NibArchive *nib = c->nib;
    const NibObject *object = &nib->objects[index];
    CFStringRef className = nib->classNames[object->classIndex];

    static const char *const stringClasses[] = { "NSString", "NSMutableString", "NSLocalizableString", NULL };
    static const char *const dataClasses[] = { "NSData", "NSMutableData", NULL };
    static const char *const numberClasses[] = { "NSNumber", NULL };
    static const char *const listClasses[] = { "NSArray", "NSMutableArray", "NSSet", "NSMutableSet", "NSOrderedSet", "NSMutableOrderedSet", NULL };
    static const char *const dictionaryClasses[] = { "NSDictionary", "NSMutableDictionary", NULL };

    // Strings, data and numbers are stored inline in a keyed archive.
    if (classIsOneOf(className, stringClasses)) {
        const NibValue *bytes = findValue(nib, object, CFSTR("NS.bytes"));
        if (bytes && bytes->type == NibValueData) {
            CFStringRef string = CFStringCreateWithBytes(kCFAllocatorDefault, bytes->bytes, bytes->length, kCFStringEncodingUTF8, false);
            if (string)
                return string;
        }
    } else if (classIsOneOf(className, dataClasses)) {
        const NibValue *bytes = findValue(nib, object, CFSTR("NS.bytes"));
        if (bytes && bytes->type == NibValueData)
            return CFDataCreate(kCFAllocatorDefault, bytes->bytes, bytes->length);
    } else if (classIsOneOf(className, numberClasses) && object->valueCount == 1) {
        const NibValue *value = &nib->values[object->firstValue];
        CFTypeRef primitive = createPrimitive(value);
        if (primitive)
            return primitive;
    }

    CFMutableDictionaryRef result = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFTypeRef classUID = createUID(classSlot(c, className));
    CFDictionarySetValue(result, CFSTR("$class"), classUID);
    CFRelease(classUID);

    BOOL isList = classIsOneOf(className, listClasses);
    BOOL isDictionary = classIsOneOf(className, dictionaryClasses);
    CFMutableArrayRef elements = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    CFMutableArrayRef elementKeys = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    BOOL nextIsKey = YES;

    for (CFIndex i = 0; i < object->valueCount; i++) {
        const NibValue *value = &nib->values[object->firstValue + i];
        CFStringRef key = nib->keys[value->keyIndex];

        if ((isList || isDictionary) && CFEqual(key, CFSTR("UINibEncoderEmptyKey"))) {
            CFTypeRef uid = createElementUID(c, value);
            CFArrayAppendValue(isDictionary && nextIsKey ? elementKeys : elements, uid);
            CFRelease(uid);
            nextIsKey = !nextIsKey;
            continue;
        }
        if (CFEqual(key, CFSTR("NSInlinedValue")))
            continue;

        CFTypeRef member = createMember(value);
        if (member) {
            CFDictionarySetValue(result, key, member);
            CFRelease(member);
        }
    }

    // Dictionaries alternate keys and values. With an unpaired key, NSDictionary's
    // -initWithObjects:forKeys: would raise while the nib is decoded, so reject the nib instead.
    if (isDictionary && CFArrayGetCount(elementKeys) != CFArrayGetCount(elements)) {
        CFRelease(elements);
        CFRelease(elementKeys);
        CFRelease(result);
        return NULL;
    }

    if (isList || isDictionary)
        CFDictionarySetValue(result, CFSTR("NS.objects"), elements);
    if (isDictionary)
        CFDictionarySetValue(result, CFSTR("NS.keys"), elementKeys);
    CFRelease(elements);
    CFRelease(elementKeys);
    return result;
}

NSData *NSKeyedArchiveDataFromNibArchiveData(NSData *data)
{
    if (!NSNibArchiveDataIsNibArchive(data))
        return nil;

    NibArchive nib = { .bytes = [data bytes], .length = [data length] };
    NSData *result = nil;

    if (!parseNibArchive(&nib)) {
        NSLog(@"NSNib: malformed NIBArchive data");
        freeNibArchive(&nib);
        return nil;
    }

    Converter c = {
        .nib = &nib,
        .objects = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks),
        .classes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks),
    };

    // Reserve slots so that NIB object i lives at $objects[i + 1].
    CFArrayAppendValue(c.objects, CFSTR("$null"));
    for (CFIndex i = 0; i < nib.objectCount; i++)
        CFArrayAppendValue(c.objects, kCFNull);
    for (CFIndex i = 0; i < nib.objectCount; i++) {
        CFTypeRef converted = createConvertedObject(&c, i);
        if (converted == NULL) {
            NSLog(@"NSNib: malformed NIBArchive object %ld", (long) i);
            CFRelease(c.objects);
            CFRelease(c.classes);
            freeNibArchive(&nib);
            return nil;
        }
        CFArraySetValueAtIndex(c.objects, slotForObject((uint32_t) i), converted);
        CFRelease(converted);
    }

    // The root object's keys (e.g. IB.objectdata) become $top.
    CFMutableDictionaryRef top = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    const NibObject *root = &nib.objects[0];
    for (CFIndex i = 0; i < root->valueCount; i++) {
        const NibValue *value = &nib.values[root->firstValue + i];
        CFTypeRef member = createMember(value);
        if (member) {
            CFDictionarySetValue(top, nib.keys[value->keyIndex], member);
            CFRelease(member);
        }
    }

    CFMutableDictionaryRef archive = CFDictionaryCreateMutable(kCFAllocatorDefault, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int version = 100000;
    CFNumberRef versionNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &version);
    CFDictionarySetValue(archive, CFSTR("$archiver"), CFSTR("NSKeyedArchiver"));
    CFDictionarySetValue(archive, CFSTR("$version"), versionNumber);
    CFDictionarySetValue(archive, CFSTR("$top"), top);
    CFDictionarySetValue(archive, CFSTR("$objects"), c.objects);
    CFRelease(versionNumber);
    CFRelease(top);

    CFErrorRef error = NULL;
    CFDataRef plist = CFPropertyListCreateData(kCFAllocatorDefault, archive, kCFPropertyListBinaryFormat_v1_0, 0, &error);
    if (plist) {
        result = [(NSData *) plist autorelease];
    } else {
        NSLog(@"NSNib: failed to convert NIBArchive to a keyed archive: %@", error);
        if (error)
            CFRelease(error);
    }

    CFRelease(archive);
    CFRelease(c.objects);
    CFRelease(c.classes);
    freeNibArchive(&nib);
    return result;
}
