#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <math.h>
#include <dlfcn.h>
#include <mach-o/loader.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Shared by the collection layout tests. The classes are looked up by name so a test runs, and fails with a message,
// against an AppKit that lacks them.
static void expect(BOOL condition, NSString *message) {
    if (!condition) {
        printf("FAIL: %s\n", [message UTF8String]);
        exit(1);
    }
}

// The install name (LC_ID_DYLIB) of the image that holds the class. class_getImageName answers the file the image was
// loaded from, which says nothing about the name other images, the dyld cache policy and AppKit's re-export refer to it by.
static NSString *installNameOfImageDefining(Class cls) {
    Dl_info info;
    if (cls == Nil || !dladdr((const void *) cls, &info) || info.dli_fbase == NULL)
        return nil;
#ifdef __LP64__
    const struct mach_header_64 *header = (const struct mach_header_64 *) info.dli_fbase;
#else
    const struct mach_header *header = (const struct mach_header *) info.dli_fbase;
#endif
    const uint8_t *command = (const uint8_t *) (header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *) command;
        if (lc->cmd == LC_ID_DYLIB) {
            const struct dylib_command *id = (const struct dylib_command *) lc;
            return [NSString stringWithUTF8String: (const char *) lc + id->dylib.name.offset];
        }
        command += lc->cmdsize;
    }
    return nil;
}

// The NSCollectionLayout* classes come from the CollectionViewCore image AppKit re-exports (the stand-in on plain
// Darling), not from AppKit itself: a copy in AppKit would be a duplicate of the cache's class on a cache stage. The
// image also has to carry the install name the cache's CollectionViewCore has.
static void expectFromCollectionViewCore(Class cls) {
    const char *image = cls != Nil ? class_getImageName(cls) : NULL;
    expect(image != NULL && strstr(image, "/CollectionViewCore.framework/") != NULL,
           [NSString stringWithFormat: @"%s is defined by CollectionViewCore (image: %s)",
                                       cls != Nil ? class_getName(cls) : "(missing class)", image ? image : "none"]);
    NSString *installName = installNameOfImageDefining(cls);
    expect([installName isEqualToString: @"/System/Library/PrivateFrameworks/CollectionViewCore.framework/Versions/A/CollectionViewCore"],
           [NSString stringWithFormat: @"%s lives in an image with the CollectionViewCore install name (install name: %@)",
                                       class_getName(cls), installName]);
}

// Two layout sizes with the same width and height dimensions. A layout size given to an item is not necessarily
// the object the item answers (macOS answers a copy), so identity is not compared.
static BOOL sameDimension(NSCollectionLayoutDimension *a, NSCollectionLayoutDimension *b) {
    return [a isFractionalWidth] == [b isFractionalWidth] && [a isFractionalHeight] == [b isFractionalHeight] &&
           [a isAbsolute] == [b isAbsolute] && [a isEstimated] == [b isEstimated] && [a dimension] == [b dimension];
}

static BOOL sameSize(NSCollectionLayoutSize *a, NSCollectionLayoutSize *b) {
    return a != nil && b != nil && sameDimension([a widthDimension], [b widthDimension]) &&
           sameDimension([a heightDimension], [b heightDimension]);
}

// The items of an array match those of another one in order, by layout size (macOS answers copies of the subitems).
static BOOL sameItemSizes(NSArray *actual, NSArray *expected) {
    if ([actual count] != [expected count])
        return NO;
    for (NSUInteger i = 0; i < [actual count]; i++)
        if (!sameSize([[actual objectAtIndex: i] layoutSize], [[expected objectAtIndex: i] layoutSize]))
            return NO;
    return YES;
}
