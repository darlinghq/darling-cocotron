#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

@class NSView;

@interface NSDockTile : NSObject {
    id _owner;
    NSSize _size;
    NSString *_badgeLabel;
    NSView *_contentView;
    BOOL _showsApplicationBadge;
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
