# Actual NSTextView method, controlled coordinate/layout adapters; no GUI.
require 'tmpdir'
require 'open3'
sdk = ARGV.fetch(0)
source = File.read(File.expand_path('../AppKit/NSTextView.subproj/NSTextView.m', __dir__))
method = source[/^- \(NSUInteger\) characterIndexForPoint:.*?^\}/m] or abort 'method missing'
program = <<~'OBJC'
  #import <Foundation/Foundation.h>
  #include <assert.h>
  @interface NSWindow : NSObject @end
  @implementation NSWindow
  - (NSPoint)convertScreenToBase:(NSPoint)p { return NSMakePoint(p.x-100,p.y-200); }
  @end
  @interface NSTextContainer : NSObject @end
  @implementation NSTextContainer @end
  @interface NSLayoutManager : NSObject {
  @public NSUInteger glyph, count, character; NSRect rect; NSPoint received;
  }
  @end
  @implementation NSLayoutManager
  - (NSUInteger)glyphIndexForPoint:(NSPoint)p inTextContainer:(id)c fractionOfDistanceThroughGlyph:(CGFloat *)f {
    assert(c); received=p; *f=0.25; return glyph;
  }
  - (NSUInteger)numberOfGlyphs { return count; }
  - (NSRect)boundingRectForGlyphRange:(NSRange)r inTextContainer:(id)c {
    assert(r.location==glyph && r.length==1 && c); return rect;
  }
  - (NSUInteger)characterIndexForGlyphAtIndex:(NSUInteger)g { assert(g==glyph); return character; }
  @end
  @interface View : NSObject {
  @public NSWindow *window; NSLayoutManager *manager; NSTextContainer *container; NSString *string;
  }
  @end
  @implementation View
  - (id)window { return window; }
  - (id)string { return string; }
  - (id)layoutManager { return manager; }
  - (id)textContainer { return container; }
  - (NSPoint)textContainerOrigin { return NSMakePoint(3,7); }
  - (NSPoint)convertPoint:(NSPoint)p fromView:(id)v {
    assert(v==nil); return NSMakePoint(p.x-10,80-p.y);
  }
  ACTUAL_METHOD
  @end
  // Inverse of the adapters: screen -> window -> flipped view -> container.
  static NSPoint screen(CGFloat x, CGFloat y) { return NSMakePoint(x+113,273-y); }
  int main(void) { @autoreleasepool {
    View *v=[View new]; v->window=[NSWindow new]; v->manager=[NSLayoutManager new];
    v->container=[NSTextContainer new]; v->string=@"abcdef";
    NSLayoutManager *m=v->manager; m->glyph=1; m->count=3; m->character=4;
    m->rect=NSMakeRect(20,30,10,12);
    assert([v characterIndexForPoint:screen(25,35)]==4);
    assert(m->received.x==25 && m->received.y==35);
    // Nearest-glyph lookup returns the same glyph for all these misses.
    NSPoint outside[]={screen(19,35),screen(31,35),screen(25,29),screen(25,43),screen(25,100)};
    for(unsigned i=0;i<5;i++) assert([v characterIndexForPoint:outside[i]]==NSNotFound);
    m->glyph=m->count; assert([v characterIndexForPoint:screen(25,35)]==NSNotFound);
    m->glyph=NSNotFound; assert([v characterIndexForPoint:screen(25,35)]==NSNotFound);
    m->glyph=1; m->character=6; assert([v characterIndexForPoint:screen(25,35)]==NSNotFound);
    m->character=0; assert([v characterIndexForPoint:screen(25,35)]==0);
    v->string=@""; assert([v characterIndexForPoint:screen(25,35)]==NSNotFound);
    v->string=@"abcdef"; [v->window release]; v->window=nil;
    assert([v characterIndexForPoint:screen(25,35)]==NSNotFound);
    [v->manager release]; [v->container release]; [v release];
    puts("PASS: coordinate conversion, containment, nearest-glyph rejection, mapping, empty and detached views");
  } }
OBJC
program = program.sub('ACTUAL_METHOD') { method }
gcc, status = Open3.capture2('gcc', '-print-file-name=include')
abort 'headers missing' unless status.success?
Dir.mktmpdir('text-hit-testing') do |dir|
  input=File.join(dir,'probe.m'); output=File.join(dir,'probe'); File.write(input,program)
  abort 'compile failed' unless system('clang','-fobjc-runtime=gcc','-fconstant-string-class=NSConstantString',
    "-I#{sdk}/usr/include/GNUstep","-I#{gcc.strip}",input,"-L#{sdk}/usr/lib",
    "-Wl,-rpath,#{sdk}/usr/lib",'-lgnustep-base','-lobjc','-o',output)
  abort 'probe failed' unless system(output)
end
