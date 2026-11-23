// CFLAGS: -framework Foundation -framework AppKit
// A collection view asks its data source for items during its layout pass, not in reloadData, and shows their
// views as its subviews; after a reload with no items no item view is shown. As on macOS 26.7.3 and 10.14.4.
#import <AppKit/AppKit.h>
#include <stdio.h>
// Builds its view in code: a plain NSCollectionViewItem loads a nib named after its class (10.14 raises without one)
@interface SyntheticItem : NSCollectionViewItem
@end
@implementation SyntheticItem
- (void)loadView { self.view=[[[NSView alloc] initWithFrame:NSMakeRect(0,0,80,30)] autorelease]; }
@end
@interface SyntheticSource : NSObject <NSCollectionViewDataSource> { @public NSInteger count; NSUInteger callbacks; }
@end
@implementation SyntheticSource
- (NSInteger)collectionView:(NSCollectionView *)view numberOfItemsInSection:(NSInteger)section { return count; }
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)view itemForRepresentedObjectAtIndexPath:(NSIndexPath *)path {
 callbacks++;
 NSCollectionViewItem *item=[view makeItemWithIdentifier:@"synthetic" forIndexPath:path];
 item.view=[[[NSView alloc] initWithFrame:NSMakeRect(0,0,80,30)] autorelease];
 return item;
}
@end
int main(void) {
 NSAutoreleasePool *pool=[NSAutoreleasePool new]; BOOL ok=NO;
 [NSApplication sharedApplication];
 @try {
  NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,200,150) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
  NSScrollView *scroll=[[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,200,150)] autorelease];
  NSCollectionView *view=[[[NSCollectionView alloc] initWithFrame:NSMakeRect(0,0,200,150)] autorelease];
  NSCollectionViewFlowLayout *layout=[[[NSCollectionViewFlowLayout alloc] init] autorelease]; layout.itemSize=NSMakeSize(80,30); view.collectionViewLayout=layout;
  [view registerClass:[SyntheticItem class] forItemWithIdentifier:@"synthetic"];
  SyntheticSource *source=[[[SyntheticSource alloc] init] autorelease]; source->count=2;
  [view setDataSource:source]; scroll.documentView=view; [window.contentView addSubview:scroll];
  source->callbacks=0; [view reloadData];
  BOOL lazy=source->callbacks==0;
  [view layoutSubtreeIfNeeded];
  NSCollectionViewItem *item=[view itemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]];
  BOOL populated=[view numberOfSections]==1 && [view numberOfItemsInSection:0]==2 && source->callbacks==2 && [[view visibleItems] count]==2 && [item.view superview]==view && ![item.view isHidden];
  source->count=0; [view reloadData]; [view layoutSubtreeIfNeeded];
  BOOL cleared=[[view visibleItems] count]==0 && ([item.view superview]==nil || [item.view isHidden]);
  fprintf(stderr,"%s reloadData asks for no item until the layout pass\n",lazy?"PASS":"FAIL");
  fprintf(stderr,"%s synthetic data source creates and attaches item views\n",populated?"PASS":"FAIL");
  fprintf(stderr,"%s reload hides stale item views\n",cleared?"PASS":"FAIL"); ok=lazy&&populated&&cleared;
  [window release];
 } @catch(NSException *exception) { fprintf(stderr,"FAIL collection data-source path: %s\n",[[exception name] UTF8String]); }
 [pool drain]; return ok?0:1;
}
