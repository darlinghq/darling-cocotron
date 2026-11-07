#import <CoreText/CTFontCollection.h>
#import <CoreText/CTFontDescriptor.h>
#import <Foundation/Foundation.h>

const CFStringRef kCTFontCollectionRemoveDuplicatesOption =
        CFSTR("kCTFontCollectionRemoveDuplicatesOption");

// A collection keeps the query descriptors it was made from; matching runs
// each query against the installed fonts when it is asked for.
@interface KTFontCollection : NSObject <NSCopying> {
    NSArray *_queries;
    NSDictionary *_options;
}
- initWithQueries: (NSArray *) queries options: (NSDictionary *) options;
- (NSArray *) queries;
- (NSDictionary *) options;
@end

@implementation KTFontCollection

- initWithQueries: (NSArray *) queries options: (NSDictionary *) options {
    self = [super init];
    if (self == nil)
        return nil;
    _queries = [queries copy];
    _options = [options copy];
    return self;
}

- (void) dealloc {
    [_queries release];
    [_options release];
    [super dealloc];
}

- (CFTypeID) _cfTypeID {
    return CTFontCollectionGetTypeID();
}

- copyWithZone: (NSZone *) zone {
    return [self retain];
}

- (NSArray *) queries {
    return _queries;
}

- (NSDictionary *) options {
    return _options;
}

@end

static BOOL optionIsSet(NSDictionary *options, CFStringRef key) {
    id value = [options objectForKey: (NSString *) key];
    return [value respondsToSelector: @selector(boolValue)] && [value boolValue];
}

CFTypeID CTFontCollectionGetTypeID(void) {
    return (CFTypeID) [KTFontCollection self];
}

CTFontCollectionRef CTFontCollectionCreateFromAvailableFonts(CFDictionaryRef options)
{
    // Without query descriptors, matching lists every installed face.
    return (CTFontCollectionRef) [[KTFontCollection alloc]
            initWithQueries: nil
                    options: (NSDictionary *) options];
}

CTFontCollectionRef CTFontCollectionCreateWithFontDescriptors(CFArrayRef _Nullable queryDescriptors,
                                                              CFDictionaryRef _Nullable options)
{
    // A collection made from no descriptors is empty, not "all fonts".
    NSArray *queries = queryDescriptors ? (NSArray *) queryDescriptors : [NSArray array];
    return (CTFontCollectionRef) [[KTFontCollection alloc]
            initWithQueries: queries
                    options: (NSDictionary *) options];
}

CTFontCollectionRef CTFontCollectionCreateCopyWithFontDescriptors(CTFontCollectionRef original,
                                                                  CFArrayRef _Nullable queryDescriptors,
                                                                  CFDictionaryRef _Nullable options)
{
    if (original == NULL)
        return NULL;
    KTFontCollection *collection = (KTFontCollection *) original;
    NSMutableArray *queries = [NSMutableArray array];
    if ([collection queries] != nil)
        [queries addObjectsFromArray: [collection queries]];
    if (queryDescriptors != NULL)
        [queries addObjectsFromArray: (NSArray *) queryDescriptors];
    if (options == NULL)
        options = (CFDictionaryRef) [collection options];
    return CTFontCollectionCreateWithFontDescriptors((CFArrayRef) queries, options);
}

CFArrayRef _Nullable CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionRef collection)
{
    if (collection == NULL)
        return NULL;

    KTFontCollection *object = (KTFontCollection *) collection;
    NSArray *queries = [object queries];
    if (queries == nil) {
        CTFontDescriptorRef all = CTFontDescriptorCreateWithAttributes(
                (CFDictionaryRef) [NSDictionary dictionary]);
        queries = [NSArray arrayWithObject: (id) all];
        CFRelease(all);
    }

    // Several queries can match the same face. With
    // kCTFontCollectionRemoveDuplicatesOption, faces with the same
    // PostScript name are also reported once.
    BOOL removeDuplicates =
            optionIsSet([object options], kCTFontCollectionRemoveDuplicatesOption);
    NSMutableArray *matches = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id query in queries) {
        CFArrayRef found = CTFontDescriptorCreateMatchingFontDescriptors(
                (CTFontDescriptorRef) query, NULL);
        if (found == NULL)
            continue;
        for (id match in (NSArray *) found) {
            id key = match;
            if (removeDuplicates) {
                CFTypeRef name = CTFontDescriptorCopyAttribute(
                        (CTFontDescriptorRef) match, kCTFontNameAttribute);
                if (name != NULL)
                    key = [(id) name autorelease];
            }
            if ([seen containsObject: key])
                continue;
            [seen addObject: key];
            [matches addObject: match];
        }
        CFRelease(found);
    }

    if ([matches count] == 0)
        return NULL;
    return (CFArrayRef) [matches copy];
}

CFArrayRef CTFontCollectionCreateMatchingFontDescriptorsForFamily(CTFontCollectionRef collection,
                                                                 CFStringRef familyName,
                                                                 CFDictionaryRef options)
{
    if (collection == NULL || familyName == NULL)
        return NULL;
    CFArrayRef all = CTFontCollectionCreateMatchingFontDescriptors(collection);
    if (all == NULL)
        return NULL;

    NSMutableArray *matches = [NSMutableArray array];
    for (id match in (NSArray *) all) {
        CFTypeRef family = CTFontDescriptorCopyAttribute(
                (CTFontDescriptorRef) match, kCTFontFamilyNameAttribute);
        if (family != NULL && CFEqual(family, familyName))
            [matches addObject: match];
        if (family != NULL)
            CFRelease(family);
    }
    CFRelease(all);

    if ([matches count] == 0)
        return NULL;
    return (CFArrayRef) [matches copy];
}
