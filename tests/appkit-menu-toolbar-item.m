// NSMenuToolbarItem: a subclassable NSToolbarItem with a menu and an indicator flag.
#import <AppKit/AppKit.h>
#include <objc/runtime.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

// Archives no keys; the unarchiver maps it to the menu item, as a nib load does.
@interface ArchivedMenuItem : NSObject <NSCoding>
@end
@implementation ArchivedMenuItem
- (void)encodeWithCoder:(NSCoder *)coder {
}
- (id)initWithCoder:(NSCoder *)coder { return nil; }
@end

@interface Sub : NSMenuToolbarItem {
    long _extra;
}
@end
@implementation Sub
@end

int main(void)
{
    @autoreleasepool
    {
        NSMenuToolbarItem *item = [[NSMenuToolbarItem alloc] initWithItemIdentifier:@"menu"];
        expect([item isKindOfClass:[NSToolbarItem class]], @"is a toolbar item");
        expect([[item itemIdentifier] isEqualToString:@"menu"], @"keeps its identifier");
        expect(item.showsIndicator, @"indicator defaults to YES");

        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"m"];
        item.menu = menu;
        item.showsIndicator = NO;
        expect(item.menu == menu && !item.showsIndicator, @"keeps what it is given");

        NSUInteger before = [menu retainCount];
        NSMenuToolbarItem *dup = [item copy];
        NSUInteger afterCopy = [menu retainCount];
        expect(afterCopy == before + 1, @"the copy retains the menu");
        [dup release];
        NSUInteger afterRelease = [menu retainCount];
        expect(afterRelease == before, @"releasing the copy gives the retain back");
        expect(item.menu == menu, @"original keeps the menu");

        Sub *sub = [[Sub alloc] initWithItemIdentifier:@"sub"];
        expect(class_getSuperclass(object_getClass([Sub class])) == object_getClass([NSMenuToolbarItem class]),
               @"metaclass chain");
        expect(class_getInstanceSize([Sub class]) > class_getInstanceSize([NSMenuToolbarItem class]),
               @"subclass ivar is laid out after the superclass");
        expect(sub.showsIndicator, @"subclass inherits the default");

        NSMutableData *data = [NSMutableData data];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
        [archiver encodeObject:[[[ArchivedMenuItem alloc] init] autorelease] forKey:@"root"];
        [archiver finishEncoding];
        [archiver release];
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
        [unarchiver setClass:[NSMenuToolbarItem class] forClassName:@"ArchivedMenuItem"];
        NSMenuToolbarItem *decoded = [unarchiver decodeObjectForKey:@"root"];
        [unarchiver release];
        expect([decoded isKindOfClass:[NSMenuToolbarItem class]], @"the archive decodes to a menu toolbar item");
        expect(decoded.showsIndicator, @"a decoded item shows the indicator by default");

        [sub release];
        [menu release];
        [item release];
        NSLog(@"PASS: NSMenuToolbarItem");
    }
    return 0;
}
