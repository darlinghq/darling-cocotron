#import <AppKit/AppKit.h>
#include <stdio.h>
@interface NSCollectionView (DataSourceProbe)
- (void)setDataSource:(id)source;
- (void)reloadData;
- (NSInteger)numberOfSections;
- (NSInteger)numberOfItemsInSection:(NSInteger)section;
- (NSCollectionViewItem *)itemAtIndexPath:(NSIndexPath *)path;
@end
@interface SyntheticSource : NSObject { @public NSInteger count; NSUInteger callbacks; }
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
 @try {
  NSCollectionView *view=[[[NSCollectionView alloc] initWithFrame:NSMakeRect(0,0,200,150)] autorelease];
  NSCollectionViewFlowLayout *layout=[[[NSCollectionViewFlowLayout alloc] init] autorelease]; layout.itemSize=NSMakeSize(80,30); view.collectionViewLayout=layout;
  [view registerClass:[NSCollectionViewItem class] forItemWithIdentifier:@"synthetic"];
  SyntheticSource *source=[[[SyntheticSource alloc] init] autorelease]; source->count=2;
  [view setDataSource:source]; source->callbacks=0; [view reloadData];
  NSCollectionViewItem *item=[view itemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]];
  BOOL populated=[view numberOfSections]==1 && [view numberOfItemsInSection:0]==2 && source->callbacks==2 && [[view subviews] count]==2 && [item.view superview]==view;
  source->count=0; [view reloadData]; BOOL cleared=[[view subviews] count]==0;
  fprintf(stderr,"%s synthetic data source creates and attaches item views\n",populated?"PASS":"FAIL");
  fprintf(stderr,"%s reload removes stale item views\n",cleared?"PASS":"FAIL"); ok=populated&&cleared;
 } @catch(NSException *exception) { fprintf(stderr,"FAIL collection data-source path: %s\n",[[exception name] UTF8String]); }
 [pool drain]; return ok?0:1;
}
