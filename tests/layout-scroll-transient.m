#import <AppKit/AppKit.h>
#import <Foundation/NSLayoutAnchor.h>
#include <stdio.h>
int main(void) {
 NSAutoreleasePool *pool=[NSAutoreleasePool new]; BOOL ok=NO;
 @try {
  NSView *root=[[[NSView alloc] initWithFrame:NSMakeRect(0,0,280,300)] autorelease];
  NSScrollView *scroll=[[[NSScrollView alloc] initWithFrame:NSZeroRect] autorelease];
  scroll.hasVerticalScroller=YES; scroll.translatesAutoresizingMaskIntoConstraints=NO;
  [root addSubview:scroll];
  BOOL transient=NSWidth([[scroll contentView] frame])<0;
  [NSLayoutConstraint activateConstraints:@[
   [[scroll leadingAnchor] constraintEqualToAnchor:[root leadingAnchor]],
   [[scroll trailingAnchor] constraintEqualToAnchor:[root trailingAnchor]],
   [[scroll topAnchor] constraintEqualToAnchor:[root topAnchor]],
   [[scroll bottomAnchor] constraintEqualToAnchor:[root bottomAnchor]]]];
  [root layoutSubtreeIfNeeded];
  ok=transient && NSWidth([scroll frame])==280 && NSWidth([[scroll contentView] frame])>0;
  fprintf(stderr,"%s constrained scroll view tiles transient negative clip width\n",ok?"PASS":"FAIL");
 } @catch(NSException *exception) { fprintf(stderr,"FAIL scroll layout: %s\n",[[exception name] UTF8String]); }
 [pool drain]; return ok?0:1;
}
