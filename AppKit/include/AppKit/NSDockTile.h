#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSView;

@interface NSDockTile : NSObject {
    id _owner;
    NSSize _size;
    NSString *_badgeLabel;
    NSView *_contentView;
    BOOL _showsApplicationBadge;
    NS_LEGACY_IVAR_PAD(_NSDockTileReserved, 32)
}

- (NSSize) size;
- owner;

- (NSString *) badgeLabel;
- (NSView *) contentView;
- (BOOL) showsApplicationBadge;

- (void) setBadgeLabel: (NSString *) value;
- (void) setContentView: (NSView *) view;
- (void) setShowsApplicationBadge: (BOOL) value;

- (void) display;

@end

@protocol NSDockTilePlugIn <NSObject>

@end
