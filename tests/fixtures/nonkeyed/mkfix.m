// Copyright (C) 2026 Lubos Dolezel
//
// Writes small NSArchiver (typedstream) archives of nib object classes into
// the directory given as argv[1], to be used as decoding fixtures (MC-NSCODER-3).
// The objects are built through public setters where there are any, and
// NSWindowTemplate/NSCustomView by decoding a scripted coder (see feed.m).
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdarg.h>

static void put(NSString *dir, NSString *name, id root) {
  @try {
    NSData *d = [NSArchiver archivedDataWithRootObject:root];
    [d writeToFile:[dir stringByAppendingPathComponent:name] atomically:NO];
    printf("%s %lu bytes\n", [name UTF8String], (unsigned long)[d length]);
  } @catch (NSException *e) { printf("%s EXC %s\n", [name UTF8String], [[e reason] UTF8String]); }
}

@interface Scr : NSCoder { @public NSMutableDictionary *spec; int n[256]; NSString *under; NSInteger ver; }
@end
@implementation Scr
- (BOOL)allowsKeyedCoding { return NO; }
- (NSInteger)versionForClassName:(NSString *)nm {
  if ([nm isEqualToString:under]) return ver;
  Class c = NSClassFromString(nm); return c ? (NSInteger)[c version] : 0;
}
- (id)objFor:(int)i {
  id v = [spec objectForKey:[NSString stringWithFormat:@"o%d", i]];
  return [v isKindOfClass:[NSString class]] && [v isEqualToString:@"view"] ? [[[NSView alloc] initWithFrame:NSMakeRect(0,0,100,50)] autorelease] : v;
}
- (void)put:(char)k type:(const char *)t at:(void *)p {
  int idx = n[(unsigned char)k]++;
  NSNumber *v = [spec objectForKey:[NSString stringWithFormat:@"%c%d", k, idx]];
  switch (t[0]) {
    case 'c': *(char *)p = [v charValue]; break;
    case 'i': *(int *)p = [v intValue]; break;
    case 'f': *(float *)p = [v floatValue]; break;
    case '@': *(id *)p = [[self objFor:idx] retain]; break;
    default: { NSUInteger sz; NSGetSizeAndAlignment(t, &sz, NULL); memset(p, 0, sz); }
  }
}
#define KEY(t) ((t)[0]=='@'?'o':(t)[0]=='c'?'c':(t)[0]=='i'?'i':(t)[0]=='f'?'f':'x')
- (void)decodeValueOfObjCType:(const char *)t at:(void *)p { [self put:KEY(t) type:t at:p]; }
- (void)decodeValuesOfObjCTypes:(const char *)t, ... {
  va_list ap; va_start(ap, t);
  while (*t) { NSUInteger s; const char *nx = NSGetSizeAndAlignment(t, &s, NULL); void *p = va_arg(ap, void *); [self put:KEY(t) type:t at:p]; t = nx; }
  va_end(ap);
}
- (id)decodeObject { return [self objFor:n['o']++]; }
@end

static id build(NSString *cls, NSDictionary *spec) {
  Scr *s = [[Scr alloc] init]; s->spec = [spec mutableCopy]; s->under = cls; s->ver = [NSClassFromString(cls) version];
  return [[[NSClassFromString(cls) alloc] initWithCoder:s] autorelease];
}
#define N(x) [NSNumber numberWithInt:x]

int main(int argc, char **argv) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  NSString *dir = [NSString stringWithUTF8String:argv[1]];
  // NSCustomObject: class name and extension string
  id co = build(@"NSCustomObject", [NSDictionary dictionaryWithObjectsAndKeys:@"FixtureOwner", @"o0", @"ext", @"o1", nil]);
  put(dir, @"customobject.typedstream", co);
  // NSWindowTemplate: style 15, backing 2, rect, hidesOnDeactivate|oneShot|notReleased|deferred, title, class,
  // content view; screen rect present, minimum size flagged, autosave name, maximum size flagged
  id wt = build(@"NSWindowTemplate", [NSDictionary dictionaryWithObjectsAndKeys:
    N(15), @"i0", N(2), @"i1", [NSNumber numberWithFloat:10], @"f0", [NSNumber numberWithFloat:20], @"f1",
    [NSNumber numberWithFloat:300], @"f2", [NSNumber numberWithFloat:200], @"f3", N((int)0xF0000000), @"i2",
    @"Fixture Window", @"o0", @"NSWindow", @"o1", @"view", @"o3",
    N(1), @"c0", [NSNumber numberWithFloat:0], @"f4", [NSNumber numberWithFloat:0], @"f5",
    [NSNumber numberWithFloat:1440], @"f6", [NSNumber numberWithFloat:900], @"f7",
    N(1), @"c1", [NSNumber numberWithFloat:120], @"f8", [NSNumber numberWithFloat:80], @"f9",
    @"FixtureAutosave", @"o5", N(2), @"c2", [NSNumber numberWithFloat:640], @"f10", [NSNumber numberWithFloat:480], @"f11", nil]);
  put(dir, @"windowtemplate.typedstream", wt);
  // connectors
  id oc = [[[NSClassFromString(@"NSNibOutletConnector") alloc] init] autorelease];
  id co2 = build(@"NSCustomObject", [NSDictionary dictionaryWithObjectsAndKeys:@"FixtureTarget", @"o0", nil]);
  [oc setSource:co]; [oc setDestination:co2]; [oc setLabel:@"someOutlet"];
  put(dir, @"outletconnector.typedstream", oc);
  id cc = [[[NSClassFromString(@"NSNibControlConnector") alloc] init] autorelease];
  [cc setSource:co2]; [cc setDestination:co]; [cc setLabel:@"doIt:"];
  put(dir, @"controlconnector.typedstream", cc);
  // NSControl with an NSActionCell
  NSControl *ctl = [[[NSControl alloc] initWithFrame:NSMakeRect(1, 2, 30, 40)] autorelease];
  NSActionCell *ac = [[[NSActionCell alloc] initTextCell:@"cell"] autorelease];
  [ac setTag:5]; [ac setAction:@selector(doIt:)]; [ctl setCell:ac]; [ctl setTag:7]; [ctl setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  put(dir, @"control.typedstream", ctl);
  NSView *vw = [[[NSView alloc] initWithFrame:NSMakeRect(1, 2, 30, 40)] autorelease];
  [vw setAutoresizingMask:NSViewWidthSizable | NSViewMaxXMargin]; [vw setAutoresizesSubviews:NO];
  [vw registerForDraggedTypes:[NSArray arrayWithObject:@"public.text"]];
  [vw addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(2, 3, 4, 5)] autorelease]];
  put(dir, @"view.typedstream", vw);
  // NSCustomView
  id cv = build(@"NSCustomView", [NSDictionary dictionaryWithObjectsAndKeys:@"NSTextView", @"o9", @"cvext", @"o10", nil]);
  put(dir, @"customview.typedstream", cv);
  // NSIBObjectData with an owner and one connector
  id od = [[[NSClassFromString(@"NSIBObjectData") alloc] init] autorelease];
  @try { [od setRootObject:co]; [od setConnections:[NSArray arrayWithObject:oc]]; } @catch (NSException *e) { printf("od EXC %s\n", [[e reason] UTF8String]); }
  put(dir, @"ibobjectdata.typedstream", od);
  [pool drain];
  return 0;
}
