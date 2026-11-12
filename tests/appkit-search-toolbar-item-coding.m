#import <AppKit/AppKit.h>
#import <AppKit/NSSearchToolbarItem.h>

// Stand-ins that archive the keys NSToolbarItem decodes; the unarchiver maps
// them to NSSearchToolbarItem and to a view class, as a nib toolbar does.
@interface ArchivedItem : NSObject <NSCoding> {
    id _view;
}
- (instancetype)initWithView:(id)view;
@end

@implementation ArchivedItem
- (instancetype)initWithView:(id)view {
    if ((self = [super init])) _view = [view retain];
    return self;
}
- (void)dealloc {
    [_view release];
    [super dealloc];
}
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:@"filter" forKey:@"NSToolbarItemIdentifier"];
    [coder encodeObject:_view forKey:@"NSToolbarItemView"];
    [coder encodeObject:@"Filter" forKey:@"NSToolbarItemLabel"];
    [coder encodeSize:NSMakeSize(140, 22) forKey:@"NSToolbarItemMinSize"];
    [coder encodeSize:NSMakeSize(140, 22) forKey:@"NSToolbarItemMaxSize"];
    [coder encodeBool:YES forKey:@"NSToolbarItemEnabled"];
}
- (id)initWithCoder:(NSCoder *)coder { return nil; }
@end

@interface ArchivedView : NSObject <NSCoding>
@end

@implementation ArchivedView
- (void)encodeWithCoder:(NSCoder *)coder {
}
- (id)initWithCoder:(NSCoder *)coder { return nil; }
@end

@interface DecodedSearchField : NSSearchField
@end

@implementation DecodedSearchField
- (id)initWithCoder:(NSCoder *)coder {
    return [self initWithFrame:NSMakeRect(0, 0, 140, 22)];
}
@end

@interface DecodedPlainView : NSView
@end

@implementation DecodedPlainView
- (id)initWithCoder:(NSCoder *)coder {
    return [self initWithFrame:NSMakeRect(0, 0, 10, 10)];
}
@end

static id decodeItem(NSString *viewClassName) {
    ArchivedView *view = [[[ArchivedView alloc] init] autorelease];
    ArchivedItem *item = [[[ArchivedItem alloc] initWithView:view] autorelease];
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:item forKey:@"root"];
    [archiver finishEncoding];
    [archiver release];

    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [unarchiver setClass:[NSSearchToolbarItem class] forClassName:@"ArchivedItem"];
    [unarchiver setClass:NSClassFromString(viewClassName) forClassName:@"ArchivedView"];
    id result = [unarchiver decodeObjectForKey:@"root"];
    [unarchiver release];
    return result;
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSSearchToolbarItem *item = decodeItem(@"DecodedSearchField");
    if (![item isKindOfClass:[NSSearchToolbarItem class]]) return 1;
    if (![[item itemIdentifier] isEqualToString:@"filter"] || ![[item label] isEqualToString:@"Filter"])
        return 2;
    // The decoded view is the search field, not a new one.
    if (![[item searchField] isKindOfClass:[DecodedSearchField class]] || [item view] != [item searchField])
        return 3;
    if ([item preferredWidthForSearchField] != 140) return 4;
    if (![item resignsFirstResponderWithCancel]) return 5;

    [item setPreferredWidthForSearchField:200];
    if ([[item searchField] frame].size.width != 200) return 6;
    [item setResignsFirstResponderWithCancel:NO];
    if ([item resignsFirstResponderWithCancel]) return 7;

    NSSearchToolbarItem *fresh = [[NSSearchToolbarItem alloc] initWithItemIdentifier:@"search"];
    if (![[fresh searchField] isKindOfClass:[NSSearchField class]] || [fresh view] != [fresh searchField] ||
        ![fresh resignsFirstResponderWithCancel] || [fresh preferredWidthForSearchField] != 180)
        return 8;
    [fresh release];

    @try {
        decodeItem(@"DecodedPlainView");
        return 9;
    } @catch (NSException *e) {
        if (![[e name] isEqualToString:NSInvalidArgumentException]) return 10;
    }

    printf("PASS appkit-search-toolbar-item-coding\n");
    [pool release];
    return 0;
}
