#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
static int failures;
static NSString *env(const char *key) { return [NSString stringWithUTF8String:getenv(key)]; }
static NSArray *files(void) { return @[env("FILE_ONE"),env("FILE_TWO")]; }
@interface FileClipboardView : NSView
@end
@implementation FileClipboardView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)drawRect:(NSRect)rect { [[NSColor whiteColor]set];NSRectFill([self bounds]); }
- (void)keyDown:(NSEvent *)event {
 NSPasteboard *pb=[NSPasteboard generalPasteboard];NSString *key=[event characters];
 if([key isEqual:@"c"]) {
  NSArray *types=getenv("FILE_RAW") ? (getenv("REVERSE_RAW") ? @[@"text/uri-list",NSFilenamesPboardType] : @[NSFilenamesPboardType,@"text/uri-list"]) : @[NSFilenamesPboardType];
  [pb declareTypes:types owner:nil];
  if(![pb setPropertyList:files() forType:NSFilenamesPboardType])failures++;
  if(getenv("FILE_RAW")) [pb setData:[env("FILE_WIRE") dataUsingEncoding:NSUTF8StringEncoding] forType:@"text/uri-list"];
  printf("COPIED failures=%d\n",failures);
 } else if([key isEqual:@"p"]) {
  NSArray *list=[pb propertyListForType:NSFilenamesPboardType];
  BOOL converted=getenv("FILE_BAD") ? list==nil : [list isEqual:files()];
  BOOL raw=[[pb dataForType:@"text/uri-list"] isEqual:[env("FILE_INCOMING_WIRE") dataUsingEncoding:NSUTF8StringEncoding]];
  BOOL types=[[pb types]containsObject:NSFilenamesPboardType] && [[pb types]containsObject:@"text/uri-list"];
  if(!converted || !raw || !types)failures++;
  printf("PASTED converted=%d raw=%d types=%d failures=%d\n",converted,raw,types,failures);
 } else if([key isEqual:@"q"]) {printf("RESULT failures=%d\n",failures);fflush(stdout);exit(failures?1:0);}
 fflush(stdout);
}
@end
int main(void) {
 [NSAutoreleasePool new];[NSApplication sharedApplication];
 NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,400,200) styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
 [w setTitle:@"File clipboard fixture"];
 FileClipboardView *v=[[FileClipboardView alloc]initWithFrame:NSMakeRect(0,0,400,200)];[w setContentView:v];[w makeKeyAndOrderFront:nil];[w makeFirstResponder:v];
 puts("READY");fflush(stdout);[NSApp run];return 2;
}
