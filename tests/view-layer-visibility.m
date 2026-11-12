#import <AppKit/AppKit.h>
#import <QuartzCore/CALayer.h>
#include <assert.h>
#include <stdio.h>
@interface VisibilitySink : NSObject { @public BOOL hidden; unsigned updates; }
- (void)setHidden:(BOOL)value;
@end
@implementation VisibilitySink
- (void)setHidden:(BOOL)value { hidden=value; updates++; }
@end
@interface VisibilityView : NSView
- (void)attachLayer:(id)layer context:(id)context;
- (void)detachSinks;
@end
@implementation VisibilityView
- (void)attachLayer:(id)layer context:(id)context { _layer=layer; _layerContext=context; }
- (void)detachSinks { _layer=nil; _layerContext=nil; }
@end
int main(void) {
 @autoreleasepool {
  VisibilityView *parent=[[VisibilityView alloc] initWithFrame:NSMakeRect(0,0,100,100)];
  VisibilityView *child=[[VisibilityView alloc] initWithFrame:NSMakeRect(0,0,50,50)];
  [parent addSubview:child];
  VisibilitySink *layer=[VisibilitySink new], *context=[VisibilitySink new];
  [child attachLayer:layer context:context];
  [parent setHidden:YES]; assert(layer->hidden && context->hidden && context->updates);
  [parent setHidden:NO]; assert(!layer->hidden && !context->hidden);
  [child setHidden:YES]; assert(layer->hidden && context->hidden);
  [parent setHidden:YES]; [parent setHidden:NO]; assert(layer->hidden && context->hidden);
  [child setHidden:NO]; assert(!layer->hidden && !context->hidden);
  VisibilityView *hiddenParent=[[VisibilityView alloc] initWithFrame:NSMakeRect(0,0,100,100)];
  [hiddenParent setHidden:YES];
  [hiddenParent addSubview:parent]; assert(layer->hidden && context->hidden);
  [parent removeFromSuperview]; assert(!layer->hidden && !context->hidden);
  [hiddenParent release];
  VisibilityView *created=[[VisibilityView alloc] initWithFrame:NSMakeRect(0,0,10,10)];
  [created setHidden:YES]; [created setWantsLayer:YES];
  assert([created layer] && [[created layer] isHidden]);
  CALayer *replacement=[NSClassFromString(@"CALayer") layer]; [created setLayer:replacement];
  assert([[created layer] isHidden]);
  [created setHidden:NO]; assert(![[created layer] isHidden]);
  [created release];
  [child detachSinks]; [layer release]; [context release]; [child release]; [parent release];
  puts("PASS view and ancestor visibility reach layer and native context");
 }
 return 0;
}
