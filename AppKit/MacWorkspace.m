#import "MacWorkspace.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSRaise.h>
#include <LaunchServices/LaunchServices.h>
#include <LaunchServices/LaunchServicesPriv.h>
#include <dispatch/dispatch.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/xattr.h>
#include <unistd.h>

@interface NSRunningApplication (LaunchLookup)
+ (NSArray<NSRunningApplication *> *) _runningApplicationsWithBundleURL: (NSURL *) bundleURL;
@end

static NSCache *_workspaceIconCache;

static NSCache *WorkspaceIconCache(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _workspaceIconCache = [[NSCache alloc] init];
    });
    return _workspaceIconCache;
}

static NSImage *ImageFromIconFile(NSString *file) {
    NSImage *icon = nil;
    @try {
        icon = [[[NSImage alloc] initWithContentsOfFile: file] autorelease];
    } @catch (NSException *exception) {
        icon = nil;
    }
    if (icon != nil && (icon.size.width <= 0.0 || icon.size.height <= 0.0))
        icon = nil;
    return icon;
}

static NSImage *ImageFromIcnsData(NSData *data) {
    if (data == nil)
        return nil;

    const unsigned char *bytes = (const unsigned char *)[data bytes];
    NSUInteger length = [data length];
    uint32_t declaredLength = (length >= 8)
            ? (((uint32_t)bytes[4] << 24) | ((uint32_t)bytes[5] << 16) |
               ((uint32_t)bytes[6] << 8) | bytes[7])
            : 0;

    if (length < 8 || memcmp(bytes, "icns", 4) != 0 ||
        declaredLength < 8 || declaredLength > length)
        return nil;

    NSImage *best = nil;
    CGFloat bestArea = 0.0;
    NSUInteger offset = 8;
    while (offset + 8 <= declaredLength) {
        uint32_t chunkLength = ((uint32_t)bytes[offset + 4] << 24) |
                ((uint32_t)bytes[offset + 5] << 16) |
                ((uint32_t)bytes[offset + 6] << 8) | bytes[offset + 7];
        if (chunkLength < 8 || chunkLength > declaredLength - offset)
            break;

        BOOL pngChunk = (memcmp(bytes + offset, "ic13", 4) == 0 ||
                         memcmp(bytes + offset, "ic12", 4) == 0 ||
                         memcmp(bytes + offset, "ic11", 4) == 0 ||
                         memcmp(bytes + offset, "ic10", 4) == 0 ||
                         memcmp(bytes + offset, "ic09", 4) == 0 ||
                         memcmp(bytes + offset, "ic08", 4) == 0 ||
                         memcmp(bytes + offset, "ic07", 4) == 0);
        if (pngChunk && chunkLength > 8) {
            NSData *payload =
                    [data subdataWithRange: NSMakeRange(offset + 8, chunkLength - 8)];
            if (payload.length >= 8 &&
                memcmp([payload bytes], "\x89PNG\r\n\x1a\n", 8) == 0) {
                NSImage *candidate = nil;
                @try {
                    candidate = [[[NSImage alloc] initWithData: payload] autorelease];
                } @catch (NSException *exception) {
                    candidate = nil;
                }
                CGFloat area = (candidate != nil)
                        ? candidate.size.width * candidate.size.height : 0.0;
                if (candidate != nil && area > bestArea) {
                    best = candidate;
                    bestArea = area;
                }
            }
        }
        offset += chunkLength;
    }
    return best;
}

static NSImage *ImageFromIcnsFile(NSString *file) {
    return ImageFromIcnsData([NSData dataWithContentsOfFile: file]);
}

// Custom icons. An item's custom icon is an 'icns' resource (ID -16455) in its resource fork, and the
// Finder flag kHasCustomIcon is set in its FinderInfo. A folder cannot hold a resource fork of its own, so
// the resource fork is on an invisible file named "Icon\r" inside it, and only the flag is on the folder.
static NSString *const kFinderInfoName = @"com.apple.FinderInfo";
static NSString *const kResourceForkName = @"com.apple.ResourceFork";
static const uint16_t kHasCustomIconFlag = 0x0400;
static const uint16_t kIsInvisibleFlag = 0x4000;
static const int16_t kCustomIconResourceID = -16455;
static const NSUInteger kFinderInfoLength = 32;
static const NSUInteger kResourceForkHeaderLength = 256;
static const NSUInteger kResourceMapLength = 50;

static NSString *CustomIconFilePath(NSString *folder) {
    return [folder stringByAppendingPathComponent: @"Icon\r"];
}

static NSData *CopyXattr(NSString *path, NSString *name) {
    const char *fsPath = [path fileSystemRepresentation];
    ssize_t length = getxattr(fsPath, [name UTF8String], NULL, 0, 0, 0);
    if (length < 0)
        return nil;
    NSMutableData *data = [NSMutableData dataWithLength: (NSUInteger)length];
    if (length > 0 && getxattr(fsPath, [name UTF8String], [data mutableBytes], (size_t)length, 0, 0) != length)
        return nil;
    return data;
}

static BOOL SetXattr(NSString *path, NSString *name, NSData *data) {
    return setxattr([path fileSystemRepresentation], [name UTF8String], [data bytes], [data length], 0, 0) == 0;
}

static BOOL RemoveXattr(NSString *path, NSString *name) {
    return removexattr([path fileSystemRepresentation], [name UTF8String], 0) == 0 || errno == ENOATTR;
}

static uint32_t ReadBE32(const unsigned char *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

static void WriteBE32(unsigned char *p, uint32_t v) {
    p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v;
}

static uint16_t FinderFlags(NSData *finderInfo) {
    if ([finderInfo length] < kFinderInfoLength)
        return 0;
    const unsigned char *b = [finderInfo bytes];
    return (uint16_t)((b[8] << 8) | b[9]);
}

// Returns FinderInfo with the Finder flags changed; the other bytes are kept. Nil when nothing is left set.
static NSData *FinderInfoWithFlags(NSData *finderInfo, uint16_t set, uint16_t clear) {
    NSMutableData *info = [NSMutableData dataWithLength: kFinderInfoLength];
    if ([finderInfo length] == kFinderInfoLength)
        [info setData: finderInfo];
    unsigned char *b = [info mutableBytes];
    uint16_t flags = (uint16_t)(((b[8] << 8) | b[9]) & ~clear) | set;
    b[8] = flags >> 8;
    b[9] = flags & 0xff;
    for (NSUInteger i = 0; i < kFinderInfoLength; i++)
        if (b[i] != 0)
            return info;
    return nil;
}

// A resource fork that holds just the custom icon: the 256 byte header area, the length-prefixed icns data,
// and a resource map with one 'icns' resource.
static NSData *ResourceForkForIcns(NSData *icns) {
    uint32_t dataLength = (uint32_t)([icns length] + 4);
    uint32_t mapOffset = (uint32_t)kResourceForkHeaderLength + dataLength;
    NSMutableData *fork = [NSMutableData dataWithLength: mapOffset + kResourceMapLength];
    unsigned char *b = [fork mutableBytes];

    WriteBE32(b, (uint32_t)kResourceForkHeaderLength);
    WriteBE32(b + 4, mapOffset);
    WriteBE32(b + 8, dataLength);
    WriteBE32(b + 12, (uint32_t)kResourceMapLength);
    WriteBE32(b + kResourceForkHeaderLength, (uint32_t)[icns length]);
    memcpy(b + kResourceForkHeaderLength + 4, [icns bytes], [icns length]);

    unsigned char *map = b + mapOffset;
    memcpy(map, b, 16);
    map[24] = 0; map[25] = 28;           // offset of the type list
    map[26] = 0; map[27] = 50;           // offset of the name list
    unsigned char *types = map + 28;
    types[0] = 0; types[1] = 0;          // one type
    memcpy(types + 2, "icns", 4);
    types[6] = 0; types[7] = 0;          // one resource of that type
    types[8] = 0; types[9] = 10;         // offset of its reference list
    types[10] = (unsigned char)((uint16_t)kCustomIconResourceID >> 8);
    types[11] = (unsigned char)((uint16_t)kCustomIconResourceID & 0xff);
    types[12] = 0xff; types[13] = 0xff;  // no name
    return fork;
}

// The 'icns' resource of a resource fork, preferring the custom icon ID. Nil if there is none.
static NSData *IcnsFromResourceFork(NSData *fork) {
    const unsigned char *b = [fork bytes];
    NSUInteger length = [fork length];
    if (length < kResourceForkHeaderLength + 30)
        return nil;

    uint32_t dataOffset = ReadBE32(b), mapOffset = ReadBE32(b + 4), dataLength = ReadBE32(b + 8), mapLength = ReadBE32(b + 12);
    if ((uint64_t)mapOffset + mapLength > length || (uint64_t)dataOffset + dataLength > length || mapLength < 30)
        return nil;

    const unsigned char *map = b + mapOffset;
    uint32_t typeListOffset = (map[24] << 8) | map[25];
    if (typeListOffset + 2 > mapLength)
        return nil;
    const unsigned char *types = map + typeListOffset;
    uint32_t typeCount = (uint32_t)(((types[0] << 8) | types[1]) + 1) & 0xffff;

    NSData *found = nil;
    for (uint32_t t = 0; t < typeCount; t++) {
        if (typeListOffset + 2 + (t + 1) * 8 > mapLength)
            return found;
        const unsigned char *type = types + 2 + t * 8;
        if (memcmp(type, "icns", 4) != 0)
            continue;
        uint32_t count = (uint32_t)(((type[4] << 8) | type[5]) + 1) & 0xffff;
        uint32_t refOffset = typeListOffset + ((type[6] << 8) | type[7]);
        for (uint32_t r = 0; r < count; r++) {
            if (refOffset + (r + 1) * 12 > mapLength)
                break;
            const unsigned char *ref = map + refOffset + r * 12;
            int16_t resourceID = (int16_t)((ref[0] << 8) | ref[1]);
            uint32_t offset = ((uint32_t)ref[5] << 16) | ((uint32_t)ref[6] << 8) | ref[7];
            if ((uint64_t)offset + 4 > dataLength)
                continue;
            uint32_t size = ReadBE32(b + dataOffset + offset);
            if ((uint64_t)offset + 4 + size > dataLength)
                continue;
            found = [NSData dataWithBytes: b + dataOffset + offset + 4 length: size];
            if (resourceID == kCustomIconResourceID)
                return found;
        }
    }
    return found;
}

static NSImage *CustomIconForPath(NSString *path, BOOL isDirectory) {
    if ((FinderFlags(CopyXattr(path, kFinderInfoName)) & kHasCustomIconFlag) == 0)
        return nil;
    NSData *fork = CopyXattr(isDirectory ? CustomIconFilePath(path) : path, kResourceForkName);
    NSData *icns = fork != nil ? IcnsFromResourceFork(fork) : nil;
    if (icns == nil)
        return nil;
    NSImage *icon = ImageFromIcnsData(icns);
    return icon;
}

// The PNG elements of an icns file for the image, smallest first. Each element is scaled to fit its
// pixel size.
static NSArray *IcnsElementsForImage(NSImage *image) {
    static const struct { const char *type; NSInteger pixels; } elements[] = {
        { "ic11", 32 }, { "ic12", 64 }, { "ic07", 128 }, { "ic08", 256 }, { "ic09", 512 },
    };
    NSMutableArray *result = [NSMutableArray array];

    for (size_t i = 0; i < sizeof(elements) / sizeof(elements[0]); i++) {
        NSInteger pixels = elements[i].pixels;
        NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
                initWithBitmapDataPlanes: NULL pixelsWide: pixels pixelsHigh: pixels bitsPerSample: 8
                         samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
                             bytesPerRow: 0 bitsPerPixel: 32] autorelease];
        NSGraphicsContext *context = rep != nil ? [NSGraphicsContext graphicsContextWithBitmapImageRep: rep] : nil;
        if (context == nil)
            return nil;

        NSSize size = [image size];
        CGFloat scale = MIN((CGFloat)pixels / size.width, (CGFloat)pixels / size.height);
        NSRect target = NSMakeRect(((CGFloat)pixels - size.width * scale) / 2.0, ((CGFloat)pixels - size.height * scale) / 2.0,
                size.width * scale, size.height * scale);

        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext: context];
        [image drawInRect: target fromRect: NSZeroRect operation: NSCompositingOperationSourceOver fraction: 1.0];
        [context flushGraphics];
        [NSGraphicsContext restoreGraphicsState];

        NSData *png = [rep representationUsingType: NSPNGFileType properties: @{}];
        if ([png length] == 0)
            return nil;
        NSMutableData *element = [NSMutableData dataWithCapacity: [png length] + 8];
        unsigned char header[8];
        memcpy(header, elements[i].type, 4);
        WriteBE32(header + 4, (uint32_t)([png length] + 8));
        [element appendBytes: header length: 8];
        [element appendData: png];
        [result addObject: element];
    }
    return result;
}

static NSData *IcnsDataFromElements(NSArray *elements, NSUInteger count) {
    NSMutableData *icns = [NSMutableData data];
    unsigned char header[8] = { 'i', 'c', 'n', 's' };
    NSUInteger total = 8;

    for (NSUInteger i = 0; i < count; i++)
        total += [[elements objectAtIndex: i] length];
    WriteBE32(header + 4, (uint32_t)total);
    [icns appendBytes: header length: 8];
    for (NSUInteger i = 0; i < count; i++)
        [icns appendData: [elements objectAtIndex: i]];
    return icns;
}

// Stores the icns data as the resource fork of path. The filesystem limits the size of an extended
// attribute, so when the fork does not fit, the largest elements are left out until it does.
static BOOL SetIcnsResourceFork(NSString *path, NSArray *elements) {
    for (NSUInteger count = [elements count]; count > 0; count--) {
        if (SetXattr(path, kResourceForkName, ResourceForkForIcns(IcnsDataFromElements(elements, count))))
            return YES;
        if (errno != ENOSPC && errno != E2BIG && errno != ERANGE)
            return NO;
    }
    return NO;
}

@implementation NSWorkspace (macos)

+ allocWithZone: (NSZone *) zone {
    return NSAllocateObject([MacWorkspace class], 0, NULL);
}

@end

@implementation MacWorkspace

// The icon of a file that has no icon of its own: the one for its type, which comes from the filename
// extension. A path that is empty or does not exist still gets one, as on macOS.
- (NSImage *) _iconByTypeForPath: (NSString *) path isDirectory: (BOOL) isDirectory {
    NSString *extension = [path pathExtension];

    if (isDirectory)
        return [self iconForFileType: [extension isEqualToString: @"app"] ? @"app" : @"public.folder"];

    return [self iconForFileType: [extension length] > 0 ? extension : @"public.data"];
}

- (NSImage *) iconForFile: (NSString *) path {
    if (path == nil || [path length] == 0)
        return [self _iconByTypeForPath: @"" isDirectory: NO];

    NSImage *cached = [WorkspaceIconCache() objectForKey: path];
    if (cached != nil)
        return cached;

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDirectory])
        return [self _iconByTypeForPath: path isDirectory: NO];

    NSImage *custom = CustomIconForPath(path, isDirectory);
    if (custom != nil) {
        [WorkspaceIconCache() setObject: custom forKey: path];
        return custom;
    }
    if (!isDirectory)
        return [self _iconByTypeForPath: path isDirectory: NO];

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
            [path stringByAppendingPathComponent: @"Contents/Info.plist"]];
    if (info == nil)
        return [self _iconByTypeForPath: path isDirectory: YES];

    NSMutableArray *names = [NSMutableArray array];
    id value = [info objectForKey: @"CFBundleIconName"];
    if ([value isKindOfClass: [NSString class]])
        [names addObject: value];
    value = [info objectForKey: @"CFBundleIconFile"];
    if ([value isKindOfClass: [NSString class]] && ![names containsObject: value])
        [names addObject: value];
    value = [info objectForKey: @"CFBundleIconFiles"];
    if ([value isKindOfClass: [NSArray class]])
        for (id item in value)
            if ([item isKindOfClass: [NSString class]])
                [names addObject: item];

    NSString *resources =
            [path stringByAppendingPathComponent: @"Contents/Resources"];
    for (NSString *name in names) {
        NSString *candidate = ([name pathExtension].length > 0)
                ? name : [name stringByAppendingPathExtension: @"icns"];
        NSString *file = [resources stringByAppendingPathComponent: candidate];
        NSImage *icon = ImageFromIconFile(file);
        if (icon == nil)
            icon = ImageFromIcnsFile(file);
        if (icon != nil) {
            [WorkspaceIconCache() setObject: icon forKey: path];
            return icon;
        }
    }

    return [self _iconByTypeForPath: path isDirectory: YES];
}

// One file gets its own icon; a group (or nothing) gets the generic document icon.
- (NSImage *) iconForFiles: (NSArray *) array {
    if ([array count] == 1)
        return [self iconForFile: [array objectAtIndex: 0]];

    return [self _iconByTypeForPath: @"" isDirectory: NO];
}

// A file type is a UTI, a filename extension, or an HFS type code in quotes.
static UTType *TypeForFileType(NSString *type) {
    if ([type length] == 6 && [type hasPrefix: @"'"] && [type hasSuffix: @"'"])
        return [UTType typeWithTag: [type substringWithRange: NSMakeRange(1, 4)]
                          tagClass: @"com.apple.ostype"
                  conformingToType: nil];

    UTType *uti = [UTType typeWithIdentifier: type];
    return uti ? uti : [UTType typeWithFilenameExtension: type];
}

static NSImage *ImageForGenericIcon(NSString *name) {
    NSString *path = [[NSBundle bundleForClass: [NSWorkspace class]]
            pathForResource: name ofType: @"png"];
    return path ? [[[NSImage alloc] initWithContentsOfFile: path] autorelease] : nil;
}

// The icon the applications declare for a type, which LaunchServices locates; nil when none does.
static NSImage *DeclaredIconForType(UTType *uti) {
    if ([uti identifier] == nil)
        return nil;

    NSURL *url = (NSURL *) _LSCopyIconURLForContentType((CFStringRef) [uti identifier]);
    if (url == nil)
        return nil;

    NSString *file = [url path];
    NSImage *icon = ImageFromIconFile(file);
    if (icon == nil)
        icon = ImageFromIcnsFile(file);
    [url release];
    // Like the generic icons, the icon starts out at 32x32 points; the larger representations stay.
    [icon setSize: NSMakeSize(32, 32)];
    return icon;
}

- (NSImage *) iconForFileType: (NSString *) type {
    if (type == nil)
        return nil;

    NSString *cacheKey = [@"type:" stringByAppendingString: type];
    NSImage *icon = [WorkspaceIconCache() objectForKey: cacheKey];
    if (icon != nil)
        return icon;

    UTType *uti = TypeForFileType(type);
    if ([uti conformsToType: UTTypeDirectory])
        icon = [NSImage imageNamed: NSImageNameFolder];
    else {
        icon = DeclaredIconForType(uti);
        if (icon == nil) {
            NSArray *generic = @[
                @[ UTTypeApplication, @"application-x-executable" ],
                @[ UTTypeImage, @"image-x-generic" ],
                @[ UTTypeAudio, @"audio-x-generic" ],
                @[ UTTypeMovie, @"video-x-generic" ],
                @[ UTTypeText, @"text-x-generic" ],
                @[ UTTypeArchive, @"package-x-generic" ],
            ];
            NSString *name = @"application-x-generic";
            for (NSArray *entry in generic)
                if ([uti conformsToType: entry[0]]) {
                    name = entry[1];
                    break;
                }
            icon = ImageForGenericIcon(name);
        }
    }

    if (icon == nil)
        [NSException raise: NSInternalInconsistencyException
                    format: @"AppKit's file type icons are not installed"];
    [WorkspaceIconCache() setObject: icon forKey: cacheKey];
    return icon;
}

- (NSString *) localizedDescriptionForType: (NSString *) type {
    // TODO: call UTTypeCopyDescription()
    NSUnimplementedMethod();
    return NULL;
}

- (BOOL) filenameExtension: (NSString *) extension
            isValidForType: (NSString *) type
{
    // TODO: call UTTypeCreateAllIdentifiersForTag
    NSUnimplementedMethod();
    return NO;
}

- (NSString *) preferredFilenameExtensionForType: (NSString *) type {
    // TODO: call UTTypeCopyPreferredTagWithClass(kUTTagClassFilenameExtension)
    NSUnimplementedMethod();
    return NULL;
}

- (BOOL) type: (NSString *) type conformsToType: (NSString *) conformsToType {
    if (type == nil || conformsToType == nil)
        return NO;
    return UTTypeConformsTo((CFStringRef) type, (CFStringRef) conformsToType);
}

- (NSString *) typeOfFile: (NSString *) path error: (NSError **) error {
    // TODO: call LSCopyItemAttribute(kLSItemContentType)
    NSUnimplementedMethod();
    return NULL;
}

- (BOOL) openFile: (NSString *) path {
    return [self openFile: path withApplication: nil];
}

- (BOOL) openFile: (NSString *) path withApplication: (NSString *) application {
    return [self openFile: path
            withApplication: application
              andDeactivate: YES];
}

- (BOOL) openTempFile: (NSString *) path {
    return [self openFile: path withApplication: nil andDeactivate: YES];
}

- (BOOL) openFile: (NSString *) path
        fromImage: (NSImage *) image
               at: (NSPoint) point
           inView: (NSView *) view
{
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) openFile: (NSString *) path
        withApplication: (NSString *) application
          andDeactivate: (BOOL) deactivate
{
    return [self _openFile: path
            withApplication: application
              andDeactivate: deactivate];
}

// Shared by -openFile:withApplication:andDeactivate: and the
// -launchApplication: family, which launch an application without a file.
- (BOOL) _openFile: (nullable NSString *) path
        withApplication: (NSString *) application
          andDeactivate: (BOOL) deactivate
{
    // TODO: Implement handling `deactivate` flag
    // TODO: Implement handling race-condition between inter-application (when target app is terminating)

    // On macOS, a nil path with a valid application simply launches the
    // application (and returns YES), so the file URL is only added when a
    // path was given.
    NSURL *url = nil;
    NSURL *appURL = nil;

    if (path != nil) {
        url = [NSURL fileURLWithPath:path];
    }

    if (application != nil) {
        appURL = [NSURL fileURLWithPath:application];
    }

    LSLaunchURLSpec spec;
    memset(&spec, 0, sizeof(spec));

    NSArray *urlArray = (url != nil) ? [NSArray arrayWithObject:url] : nil;
    spec.itemURLs = (CFArrayRef)urlArray;
    spec.appURL = (CFURLRef)appURL;
    spec.launchFlags = kLSLaunchDefaults;

    OSStatus status = LSOpenFromURLSpec(&spec, NULL);

    return (status == noErr);
}

- (BOOL) openURL: (NSURL *) url {
    if (url == nil) {
        return NO;
    }

    LSLaunchURLSpec spec;
    memset(&spec, 0, sizeof(spec));

    NSArray *urlArray = [NSArray arrayWithObject:url];
    spec.itemURLs = (CFArrayRef)urlArray;
    spec.launchFlags = kLSLaunchDefaults;

    OSStatus status = LSOpenFromURLSpec(&spec, NULL);

    return (status == noErr);
}

// Opens urls with LaunchServices; appURL nil means each URL's default
// application.
static OSStatus openURLsWithFlags(NSArray *urls, NSURL *appURL,
                                  LSLaunchFlags flags) {
    LSLaunchURLSpec spec;
    memset(&spec, 0, sizeof(spec));
    spec.appURL = (CFURLRef) appURL;
    spec.itemURLs = (CFArrayRef) urls;
    spec.launchFlags = flags;
    return LSOpenFromURLSpec(&spec, NULL);
}

static LSLaunchFlags launchFlagsForConfiguration(
        NSWorkspaceOpenConfiguration *configuration) {
    LSLaunchFlags flags = kLSLaunchDefaults;
    if (configuration == nil)
        return flags;
    if (![configuration activates])
        flags |= kLSLaunchDontSwitch;
    if ([configuration hides])
        flags |= kLSLaunchAndHide;
    if ([configuration hidesOthers])
        flags |= kLSLaunchAndHideOthers;
    if ([configuration createsNewApplicationInstance])
        flags |= kLSLaunchNewInstance;
    if (![configuration addsToRecentItems])
        flags |= kLSLaunchDontAddToRecents;
    if ([configuration isForPrinting])
        flags |= kLSLaunchAndPrint;
    return flags;
}

// The handler runs asynchronously, on a concurrent queue, as documented.
// Which application took the URL is not known here, so it gets nil.
- (void) openURL: (NSURL *) url
        configuration: (NSWorkspaceOpenConfiguration *) configuration
    completionHandler: (void (^)(NSRunningApplication *app, NSError *error)) completionHandler
{
    LSLaunchFlags flags = launchFlagsForConfiguration(configuration);
    [url retain];
    void (^handler)(NSRunningApplication *, NSError *) = [completionHandler copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OSStatus status = url == nil
                ? paramErr
                : openURLsWithFlags([NSArray arrayWithObject: url], nil, flags);
        if (handler != nil) {
            NSError *error = nil;
            if (status != noErr)
                error = [NSError errorWithDomain: NSOSStatusErrorDomain
                                            code: status
                                        userInfo: nil];
            handler(nil, error);
        }
        [handler release];
        [url release];
    });
}

- (BOOL) openURLs: (NSArray<NSURL *> *) urls
           withAppBundleIdentifier: (NSString *) bundleIdentifier
                           options: (NSWorkspaceLaunchOptions) options
    additionalEventParamDescriptor: (NSAppleEventDescriptor *) descriptor
                 launchIdentifiers: (NSArray<NSNumber *> * _Nullable * _Nullable) identifiers
{
    if (identifiers != NULL)
        *identifiers = nil;
    if ([urls count] == 0)
        return NO;

    NSURL *appURL = nil;
    if (bundleIdentifier != nil) {
        appURL = [self URLForApplicationWithBundleIdentifier: bundleIdentifier];
        if (appURL == nil)
            return NO;
    }

    // The launch options share their values with LaunchServices' launch flags.
    LSLaunchFlags flags = kLSLaunchDefaults |
            (options & (NSWorkspaceLaunchAndPrint |
                        NSWorkspaceLaunchWithoutAddingToRecents |
                        NSWorkspaceLaunchWithoutActivation |
                        NSWorkspaceLaunchAsync |
                        NSWorkspaceLaunchNewInstance |
                        NSWorkspaceLaunchAndHide |
                        NSWorkspaceLaunchAndHideOthers));
    return openURLsWithFlags(urls, appURL, flags) == noErr;
}

// Private LaunchServices: shows a file in the host desktop's file manager (not in older LaunchServices).
extern OSStatus _LSOpenFileOnHost(CFURLRef fileURL, Boolean reveal) __attribute__((weak_import));

// The file viewer is the application named by NSFileViewer in the global defaults (a bundle identifier), or the
// Finder. It is asked to show items by the events that open them (observed on macOS 26.7.3, tier 2): an open-documents
// event listing the items as bookmark data (file URLs where no bookmark can be made), or a reopen event for no items,
// both with the boolean parameter 'aapd' set to true, which tells a reveal from an open.

// Sends the event to the running application with the bundle identifier; fails with procNotFound when it is not running
// (or has not yet started to receive events).
static OSStatus sendRevealEvent(NSString *bundleIdentifier, NSArray<NSURL *> *urls) {
    NSAppleEventDescriptor *target = [NSAppleEventDescriptor
            descriptorWithDescriptorType: typeApplicationBundleID
                                    data: [bundleIdentifier dataUsingEncoding: NSUTF8StringEncoding]];
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor
            appleEventWithEventClass: kCoreEventClass
                             eventID: [urls count] > 0 ? kAEOpenDocuments : kAEReopenApplication
                    targetDescriptor: target
                            returnID: kAutoGenerateReturnID
                       transactionID: kAnyTransactionID];
    if ([urls count] > 0) {
        NSAppleEventDescriptor *list = [NSAppleEventDescriptor listDescriptor];
        for (NSURL *url in urls) {
            NSData *bookmark = [url bookmarkDataWithOptions: 0
                             includingResourceValuesForKeys: nil
                                              relativeToURL: nil
                                                      error: NULL];
            NSAppleEventDescriptor *item = bookmark != nil
                    ? [NSAppleEventDescriptor descriptorWithDescriptorType: 'bmrk' data: bookmark]
                    : [NSAppleEventDescriptor descriptorWithDescriptorType: typeFileURL
                                                                      data: [[url absoluteString]
                                                                                dataUsingEncoding: NSUTF8StringEncoding]];
            [list insertDescriptor: item atIndex: 0];
        }
        [event setParamDescriptor: list forKeyword: keyDirectObject];
    }
    [event setParamDescriptor: [NSAppleEventDescriptor descriptorWithBoolean: YES] forKeyword: 'aapd'];
    return AESendMessage([event aeDesc], NULL, kAENoReply, 5 * 60);
}

- (void) _revealURLs: (NSArray<NSURL *> *) urls {
    NSString *viewerID = [[NSUserDefaults standardUserDefaults] stringForKey: @"NSFileViewer"];
    if ([viewerID length] == 0)
        viewerID = @"com.apple.finder";

    NSURL *viewerURL = [self URLForApplicationWithBundleIdentifier: viewerID];
    if (viewerURL != nil) {
        OSStatus status = sendRevealEvent(viewerID, urls);
        if (status == procNotFound && [self launchApplication: [viewerURL path]]) {
            // The first event must not be lost while the application starts: it is delivered as soon as the
            // application takes events, so keep trying for a limited time.
            for (int attempt = 0; attempt < 100 && status == procNotFound; attempt++) {
                usleep(100000);
                status = sendRevealEvent(viewerID, urls);
            }
        }
        if (status == noErr)
            return;
    }

    // No usable viewer (a prefix may have no Finder): the host's file manager shows the items, selected in their
    // folders. Items that it cannot show have their folders opened instead.
    NSMutableSet *folders = [NSMutableSet set];
    for (NSURL *url in urls) {
        if (![url isFileURL])
            continue;
        if (_LSOpenFileOnHost != NULL && _LSOpenFileOnHost((CFURLRef) url, true) == noErr)
            continue;
        NSString *path = [[url path] stringByDeletingLastPathComponent];
        if ([path length] > 0 && [folders member: path] == nil) {
            [folders addObject: path];
            [self openFile: path];
        }
    }
}

// Documented to return YES when the file was selected; the viewer is asked and not waited for, and a viewer that
// cannot be found is not an error (observed on macOS 26.7.3, tier 2: YES in every case, the root path is not sent).
- (BOOL) selectFile: (NSString *) path
        inFileViewerRootedAtPath: (NSString *) rootedAtPath
{
    if ([path length] > 0) {
        [self _revealURLs: [NSArray arrayWithObject: [NSURL fileURLWithPath: path]]];
        return YES;
    }
    // no file: the viewer is only brought to the front
    if ([rootedAtPath length] > 0) {
        [self _revealURLs: [NSArray array]];
        return YES;
    }
    return NO;
}

- (void) slideImage: (NSImage *) image from: (NSPoint) from to: (NSPoint) to {
}

- (BOOL) performFileOperation: (NSString *) operation
                       source: (NSString *) source
                  destination: (NSString *) destination
                        files: (NSArray *) files
                          tag: (NSInteger *) tag
{
    NSUnimplementedMethod();
}

- (BOOL) getFileSystemInfoForPath: (NSString *) path
                      isRemovable: (BOOL *) isRemovable
                       isWritable: (BOOL *) isWritable
                    isUnmountable: (BOOL *) isUnmountable
                      description: (NSString **) description
                             type: (NSString **) type
{
    if (!path)
        return NO;

    // TODO: call statfs() to get filesystem information
    // Use DiskArbitration for the rest.
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) getInfoForFile: (NSString *) path
            application: (NSString **) application
                   type: (NSString **) type
{
    // TODO: call LSGetApplicationForURL()
    NSUnimplementedMethod();
    return NO;
}

- (void) checkForRemovableMedia {
}

- (NSArray *) mountNewRemovableMedia {
    return [self mountedRemovableMedia];
}

- (NSArray *) mountedRemovableMedia {
    // TODO: call [[NSFileManager defaultManager]
    // mountedVolumeURLsIncludingResourceValuesForKeys:@[NSURLVolumeIsRemovableKey]
    // options:NSVolumeEnumerationSkipHiddenVolumes]
    NSUnimplementedMethod();
    return @[];
}

- (NSArray *) mountedLocalVolumePaths {
    // TODO: call [[NSFileManager defaultManager]
    // mountedVolumeURLsIncludingResourceValuesForKeys:@[]
    // options:NSVolumeEnumerationSkipHiddenVolumes]
    NSUnimplementedMethod();
    return @[];
}

- (BOOL) unmountAndEjectDeviceAtPath: (NSString *) path {
    // TODO: call FSEjectVolumeSync()
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) fileSystemChanged {
    return NO;
}

- (BOOL) userDefaultsChanged {
    return NO;
}

- (void) noteFileSystemChanged {
    [self noteFileSystemChanged: @"/"];
}

- (void) noteFileSystemChanged: (NSString *) path {
    // TODO: call FNNotifyByPath()
    NSUnimplementedMethod();
}

- (void) noteUserDefaultsChanged {
}

// A package is a folder that is presented as one file. Without a type
// registry to ask, this recognizes the folders whose extension marks a
// well-known package or bundle type.
- (BOOL) isFilePackageAtPath: (NSString *) path {
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath: path
                                               isDirectory: &isDirectory] ||
        !isDirectory)
        return NO;
    NSArray *extensions = @[
        @"app", @"bundle", @"framework", @"plugin", @"kext", @"xpc", @"appex",
        @"prefPane", @"saver", @"qlgenerator", @"mdimporter", @"component",
        @"rtfd", @"pkg", @"mpkg", @"xcodeproj", @"xcworkspace", @"playground",
        @"photoslibrary", @"dSYM", @"lproj"
    ];
    NSString *extension = [path pathExtension];
    for (NSString *known in extensions)
        if ([known caseInsensitiveCompare: extension] == NSOrderedSame)
            return YES;
    return NO;
}

- (NSString *) absolutePathForAppBundleWithIdentifier: (NSString *) identifier {
    // TODO: call LSFindApplicationForInfo() /
    // LSCopyApplicationURLsForBundleIdentifier()
    NSUnimplementedMethod();
    return NULL;
}

- (NSString *) pathForApplication: (NSString *) application {
    // This method doesn't exist on macOS?!
    return NULL;
}

- (NSArray *) launchedApplications {
    // TODO: call _LSCopyRunningApplicationArray()
    NSUnimplementedMethod();
    return @[];
}

- (NSArray *) runningApplications {
    NSUnimplementedMethod();
    return @[];
}

- (BOOL) launchApplication: (NSString *) application {
    return [self _openFile: nil
            withApplication: application
              andDeactivate: YES];
}

- (BOOL) launchApplication: (NSString *) application
                  showIcon: (BOOL) showIcon
                autolaunch: (BOOL) autolaunch
{
    return [self _openFile: nil
            withApplication: application
              andDeactivate: YES];
}

- (void) findApplications {
}

- (NSDictionary *) activeApplication {
    // TODO: call _LSCopyFrontApplication() and _LSCopyApplicationInformation()
    NSUnimplementedMethod();
    return NULL;
}

- (void) hideOtherApplications {
    [NSApp hideOtherApplications: self];
}

- (NSInteger) extendPowerOffBy: (NSInteger) milliseconds {
    return 0;
}

- (BOOL) setIcon: (NSImage *) image
         forFile: (NSString *) fullPath
         options: (NSWorkspaceIconCreationOptions) options
{
    // The icon is written as PNG elements only, so neither the 10.4 nor the QuickDraw elements
    // are ever included and the options need no handling.
    if (fullPath == nil || [fullPath length] == 0)
        return NO;

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath: fullPath isDirectory: &isDirectory])
        return NO;

    [WorkspaceIconCache() removeObjectForKey: fullPath];
    NSData *finderInfo = CopyXattr(fullPath, kFinderInfoName);
    NSString *forkPath = isDirectory ? CustomIconFilePath(fullPath) : fullPath;

    if (image == nil) {
        if ((FinderFlags(finderInfo) & kHasCustomIconFlag) == 0)
            return YES;
        // The fork of a file may hold other resources, so only a fork that is exactly the icon is removed.
        NSData *fork = CopyXattr(forkPath, kResourceForkName);
        NSData *icns = fork != nil ? IcnsFromResourceFork(fork) : nil;
        if (isDirectory) {
            if (unlink([forkPath fileSystemRepresentation]) != 0 && errno != ENOENT)
                return NO;
        } else if (icns != nil && [fork isEqualToData: ResourceForkForIcns(icns)] && !RemoveXattr(fullPath, kResourceForkName))
            return NO;

        NSData *remaining = FinderInfoWithFlags(finderInfo, 0, kHasCustomIconFlag);
        return remaining != nil ? SetXattr(fullPath, kFinderInfoName, remaining) : RemoveXattr(fullPath, kFinderInfoName);
    }

    NSSize size = [image size];
    NSArray *elements = (size.width > 0.0 && size.height > 0.0) ? IcnsElementsForImage(image) : nil;
    if ([elements count] == 0)
        return NO;

    if (isDirectory) {
        // The file is invisible both through its Finder flags and the hidden file flag.
        int fd = open([forkPath fileSystemRepresentation], O_WRONLY | O_CREAT, 0644);
        if (fd < 0)
            return NO;
        close(fd);
        chflags([forkPath fileSystemRepresentation], UF_HIDDEN);
        if (!SetXattr(forkPath, kFinderInfoName, FinderInfoWithFlags(nil, kIsInvisibleFlag, 0)))
            return NO;
    }
    if (!SetIcnsResourceFork(forkPath, elements))
        return NO;
    return SetXattr(fullPath, kFinderInfoName, FinderInfoWithFlags(finderInfo, kHasCustomIconFlag, 0));
}

- (void) activateFileViewerSelectingURLs: (NSArray<NSURL *> *) fileURLs {
    // one event for all the URLs, in order, even across folders (observed on macOS 26.7.3, tier 2)
    [self _revealURLs: fileURLs != nil ? fileURLs : [NSArray array]];
}

#pragma mark - Opening applications and items with an application

// An application URL that names nothing gets the error of a missing file, as the calls report it on
// macOS (observed on macOS 26.7.3: NSCocoaErrorDomain, NSFileReadNoSuchFileError).
static NSError *errorForMissingApplication(NSURL *applicationURL) {
    return [NSError errorWithDomain: NSCocoaErrorDomain
                               code: NSFileReadNoSuchFileError
                           userInfo: applicationURL != nil ? @{NSURLErrorKey : applicationURL} : nil];
}

static BOOL applicationExists(NSURL *applicationURL) {
    return [applicationURL isFileURL] &&
           [[NSFileManager defaultManager] fileExistsAtPath: [applicationURL path]];
}

// The application that was launched, once it is known to the registry of running applications: the
// launch itself does not report a process, so the registry is polled for a short while.
static NSRunningApplication *waitForApplicationAtURL(NSURL *applicationURL) {
    for (int attempt = 0; attempt < 50; attempt++) {
        NSRunningApplication *application =
                [[NSRunningApplication _runningApplicationsWithBundleURL: applicationURL] firstObject];

        if (application != nil)
            return application;
        usleep(100 * 1000);
    }
    return nil;
}

// Opens the items (none: just launches) with the application. Returns the application's running
// application when it is one, and sets the error when the request failed.
static NSRunningApplication *openItemsWithApplication(NSArray<NSURL *> *items, NSURL *applicationURL,
                                                      LSLaunchFlags flags, NSError **error) {
    if (!applicationExists(applicationURL)) {
        if (error != NULL)
            *error = errorForMissingApplication(applicationURL);
        return nil;
    }

    OSStatus status = openURLsWithFlags([items count] > 0 ? items : nil, applicationURL, flags);

    if (status != noErr) {
        if (error != NULL)
            *error = [NSError errorWithDomain: NSOSStatusErrorDomain code: status userInfo: nil];
        return nil;
    }
    if (error != NULL)
        *error = nil;
    return waitForApplicationAtURL(applicationURL);
}

static void runOnConcurrentQueue(dispatch_block_t block) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), block);
}

- (void) openApplicationAtURL: (NSURL *) applicationURL
                configuration: (NSWorkspaceOpenConfiguration *) configuration
            completionHandler: (void (^)(NSRunningApplication *app, NSError *error)) completionHandler
{
    [self openURLs: nil
            withApplicationAtURL: applicationURL
                   configuration: configuration
               completionHandler: completionHandler];
}

- (void) openURLs: (NSArray<NSURL *> *) urls
        withApplicationAtURL: (NSURL *) applicationURL
               configuration: (NSWorkspaceOpenConfiguration *) configuration
           completionHandler: (void (^)(NSRunningApplication *app, NSError *error)) completionHandler
{
    LSLaunchFlags flags = launchFlagsForConfiguration(configuration);
    NSArray *items = [urls copy];
    NSURL *application = [applicationURL retain];
    void (^handler)(NSRunningApplication *, NSError *) = [completionHandler copy];

    runOnConcurrentQueue(^{
        NSError *error = nil;
        NSRunningApplication *running = openItemsWithApplication(items, application, flags, &error);

        if (handler != nil)
            handler(running, error);
        [handler release];
        [application release];
        [items release];
    });
}

- (NSRunningApplication *) launchApplicationAtURL: (NSURL *) url
                                          options: (NSWorkspaceLaunchOptions) options
                                    configuration: (NSDictionary<NSString *, id> *) configuration
                                            error: (NSError **) error
{
    // The launch options share their values with LaunchServices' launch flags, as for
    // -openURLs:withAppBundleIdentifier:options:additionalEventParamDescriptor:launchIdentifiers:.
    LSLaunchFlags flags = kLSLaunchDefaults |
            (options & (NSWorkspaceLaunchAndPrint |
                        NSWorkspaceLaunchWithoutAddingToRecents |
                        NSWorkspaceLaunchWithoutActivation |
                        NSWorkspaceLaunchAsync |
                        NSWorkspaceLaunchNewInstance |
                        NSWorkspaceLaunchAndHide |
                        NSWorkspaceLaunchAndHideOthers));
    return openItemsWithApplication(nil, url, flags, error);
}

#pragma mark - Applications for items and the default application

- (NSArray<NSURL *> *) URLsForApplicationsToOpenURL: (NSURL *) url {
    CFArrayRef apps = url != nil ? LSCopyApplicationURLsForURL((CFURLRef) url, kLSRolesAll) : NULL;

    return apps != NULL ? [(NSArray *) apps autorelease] : @[];
}

- (NSArray<NSURL *> *) URLsForApplicationsWithBundleIdentifier: (NSString *) bundleIdentifier {
    CFArrayRef apps = bundleIdentifier != nil
            ? LSCopyApplicationURLsForBundleIdentifier((CFStringRef) bundleIdentifier, NULL)
            : NULL;

    return apps != NULL ? [(NSArray *) apps autorelease] : @[];
}

- (NSImage *) iconForContentType: (UTType *) contentType {
    return contentType != nil ? [self iconForFileType: [contentType identifier]] : nil;
}

// The default handler is stored under the application's bundle identifier. An application that is
// not there, or has no identifier, cannot be made the default.
static NSError *errorForDefaultApplication(NSURL *applicationURL, NSString **bundleIdentifier) {
    if (!applicationExists(applicationURL))
        return errorForMissingApplication(applicationURL);
    *bundleIdentifier = [[NSBundle bundleWithURL: applicationURL] bundleIdentifier];
    if (*bundleIdentifier == nil)
        return [NSError errorWithDomain: NSOSStatusErrorDomain code: kLSApplicationNotFoundErr userInfo: nil];
    return nil;
}

- (void) _setDefaultApplicationAtURL: (NSURL *) applicationURL
                           forScheme: (NSString *) scheme
                         contentType: (NSString *) contentType
                   completionHandler: (void (^)(NSError *error)) completionHandler
{
    NSURL *application = [applicationURL retain];
    NSString *schemeCopy = [scheme copy];
    NSString *typeCopy = [contentType copy];
    void (^handler)(NSError *) = [completionHandler copy];

    runOnConcurrentQueue(^{
        NSString *bundleIdentifier = nil;
        NSError *error = errorForDefaultApplication(application, &bundleIdentifier);

        if (error == nil) {
            OSStatus status = schemeCopy != nil
                    ? LSSetDefaultHandlerForURLScheme((CFStringRef) schemeCopy, (CFStringRef) bundleIdentifier)
                    : LSSetDefaultRoleHandlerForContentType((CFStringRef) typeCopy, kLSRolesAll,
                                                            (CFStringRef) bundleIdentifier);
            if (status != noErr)
                error = [NSError errorWithDomain: NSOSStatusErrorDomain code: status userInfo: nil];
        }
        if (handler != nil)
            handler(error);
        [handler release];
        [typeCopy release];
        [schemeCopy release];
        [application release];
    });
}

- (void) setDefaultApplicationAtURL: (NSURL *) applicationURL
               toOpenURLsWithScheme: (NSString *) urlScheme
                  completionHandler: (void (^)(NSError *error)) completionHandler
{
    [self _setDefaultApplicationAtURL: applicationURL
                            forScheme: urlScheme
                          contentType: nil
                    completionHandler: completionHandler];
}

- (void) setDefaultApplicationAtURL: (NSURL *) applicationURL
                  toOpenContentType: (UTType *) contentType
                  completionHandler: (void (^)(NSError *error)) completionHandler
{
    [self _setDefaultApplicationAtURL: applicationURL
                            forScheme: nil
                          contentType: [contentType identifier]
                    completionHandler: completionHandler];
}

// The content type of the file is the one its name extension stands for.
- (void) setDefaultApplicationAtURL: (NSURL *) applicationURL
                    toOpenFileAtURL: (NSURL *) url
                  completionHandler: (void (^)(NSError *error)) completionHandler
{
    UTType *type = [[url pathExtension] length] > 0
            ? [UTType typeWithFilenameExtension: [url pathExtension]]
            : nil;

    if (type == nil) {
        NSError *error = [NSError errorWithDomain: NSCocoaErrorDomain
                                             code: NSFileReadUnknownError
                                         userInfo: url != nil ? @{NSURLErrorKey : url} : nil];
        void (^handler)(NSError *) = [completionHandler copy];

        runOnConcurrentQueue(^{
            if (handler != nil)
                handler(error);
            [handler release];
        });
        return;
    }
    [self setDefaultApplicationAtURL: applicationURL toOpenContentType: type completionHandler: completionHandler];
}

- (NSURL *) URLForApplicationToOpenURL: (NSURL *) url {
    if (url == nil)
        return nil;
    CFErrorRef error = NULL;
    CFURLRef appURL = LSCopyDefaultApplicationURLForURL((CFURLRef) url, kLSRolesAll, &error);
    if (error != NULL)
        CFRelease(error);
    if (appURL != NULL)
        return [(NSURL *) appURL autorelease];
    return nil;
}

- (NSURL *) URLForApplicationWithBundleIdentifier: (NSString *) bundleIdentifier
{
    CFURLRef url;
    OSStatus status = LSFindApplicationForInfo(kLSUnknownCreator,
                                               (CFStringRef) bundleIdentifier,
                                               NULL, NULL, &url);

    if (status != noErr)
        return nil;

    return [(NSURL *) url autorelease];
}

- (NSString *) fullPathForApplication: (NSString *) appName {
    // If absolute, return as-is
    if ([appName isAbsolutePath])
        return appName;

    // If it doesn't have an suffix, add .app
    if ([[appName pathExtension] isEqualToString: @""])
        appName = [appName stringByAppendingPathExtension: @"app"];

    CFURLRef url;
    OSStatus status = LSFindApplicationForInfo(
            kLSUnknownCreator, NULL, (CFStringRef) appName, NULL, &url);

    if (status != noErr)
        return nil;

    NSString *path = [(NSURL *) url path];
    CFRelease(url);

    return path;
}

@end
