# Actual adjustment methods with controlled frame storage; no UI or divider rendering.
# Usage: ruby tests/split-empty-layout.rb GNUSTEP_ROOT [COCOTRON_ROOT]
require 'tmpdir'
require 'open3'
sdk,root=ARGV; root ||= File.expand_path('..',__dir__)
source=File.read(File.join(root,'AppKit/NSSplitView.m'))
methods=%w[_adjustSubviewWidths _adjustSubviewHeights adjustSubviews].map{|name| source[/^- \(void\) #{name} \{.*?^\}/m] or abort name}
program=<<~'OBJC'
  #import <Foundation/Foundation.h>
  #include <assert.h>
  #include <math.h>
  @interface NSView : NSObject { @public NSRect frame; BOOL hidden; } @end
  @implementation NSView
  - (NSRect)frame { return frame; }
  - (void)setFrame:(NSRect)value { frame=value; }
  @end
  @interface Split : NSObject { @public NSArray *_subviews; NSRect bounds; BOOL vertical; unsigned will,did; } @end
  @implementation Split
  METHODS
  - (NSRect)bounds { return bounds; }
  - (CGFloat)dividerThickness { return 5; }
  - (BOOL)isSubviewCollapsed:(NSView *)view { return view->hidden; }
  - (BOOL)isVertical { return vertical; }
  - (void)_postNoteWillResize { ++will; }
  - (void)_postNoteDidResize { ++did; }
  - (void)setNeedsDisplay:(BOOL)value {}
  @end
  int main(void) {
    @autoreleasepool {
      for(unsigned vertical=0;vertical<2;++vertical) {
        for(unsigned mode=0;mode<8;++mode) {
          NSView *a=[NSView new],*b=[NSView new],*c=[NSView new];
          Split *s=[Split new]; s->_subviews=@[a,b,c]; s->bounds=NSMakeRect(11,17,101,101); s->vertical=vertical;
          if(mode==1) a->frame=NSMakeRect(0,0,20,20);
          if(mode==2) b->hidden=YES;
          if(mode==3) a->hidden=b->hidden=c->hidden=YES;
          if(mode==4) s->bounds=NSMakeRect(11,17,3,3);
          if(mode==5) s->_subviews=@[a];
          if(mode==6) { a->frame=NSMakeRect(0,0,20,20); b->frame=NSMakeRect(0,0,40,40); c->frame=NSMakeRect(0,0,60,60); }
          if(mode==7) s->_subviews=@[];
          [s adjustSubviews];
          assert(s->will==(mode!=7) && s->did==s->will);
          double start=vertical?s->bounds.origin.x:s->bounds.origin.y;
          double end=start+(mode==4?3:101);
          unsigned i=0;
          for(NSView *v in s->_subviews) {
            if(v->hidden) { assert(NSEqualRects(v->frame,NSZeroRect)); continue; }
            double origin=vertical?v->frame.origin.x:v->frame.origin.y;
            double size=vertical?v->frame.size.width:v->frame.size.height;
            assert(isfinite(origin) && isfinite(size) && size>=0);
            assert(origin>=start && origin+size<=end);
            if(mode==0 || mode==1) assert(size==(i==2?31:30));
            if(mode==2) assert(size==48);
            if(mode==4) assert(size==0);
            if(mode==5) assert(size==101 && origin==start);
            if(mode==6) { double sizes[]={15,30,46}; assert(size==sizes[i]); }
            ++i;
          }
          [s release]; [a release]; [b release]; [c release];
        }
      }
      puts("PASS: both axes, empty/mixed/proportional panes, hidden panes, narrow bounds, singleton and notifications");
    }
  }
OBJC
program.sub!('METHODS'){methods.join("\n")}
gcc,status=Open3.capture2('gcc','-print-file-name=include'); abort unless status.success?
Dir.mktmpdir('split-empty-layout') do |dir|
  input=File.join(dir,'probe.m'); output=File.join(dir,'probe'); File.write(input,program)
  abort 'compile failed' unless system('clang','-fobjc-runtime=gcc','-fconstant-string-class=NSConstantString',"-I#{sdk}/usr/include/GNUstep","-I#{gcc.strip}",input,"-L#{sdk}/usr/lib","-Wl,-rpath,#{sdk}/usr/lib",'-lgnustep-base','-lobjc','-lm','-o',output)
  abort 'probe failed' unless system(output,rlimit_core:0)
end
