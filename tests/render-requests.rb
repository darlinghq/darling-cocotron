# Actual context timer methods with real GNUstep scheduling and a controlled renderer.
# Usage: ruby cocotron-render-redirty.rb GNUSTEP_ROOT CALayerContext.m
require 'tmpdir'
require 'open3'
sdk=ARGV.fetch(0)
path=ARGV[1] || File.expand_path('../QuartzCore/CALayerContext.m',__dir__)
source=File.read(path)
names=['timer: (NSTimer *) timer','startTimerIfNeeded','renderOnce: (NSTimer *) timer','scheduleRenderIfNeeded']
methods=names.filter_map{|n| source[/^- \(void\) #{Regexp.escape(n)} \{.*?^\}/m]}.join("\n")
private_scheduler=methods.include?('scheduleRenderIfNeeded')
program=<<~'OBJC'
  #import <Foundation/Foundation.h>
  #include <assert.h>
  typedef id CALayer;
  static unsigned frames, requestedFrames, animationFrames;
  static BOOL layerTreeHasAnimations(id layer) { return frames < animationFrames; }
  static double CACurrentMediaTime(void) { return 0; }
  @interface Renderer : NSObject @end
  @implementation Renderer
  - (void)beginFrameAtTime:(double)t timeStamp:(void *)s {}
  - (void)endFrame {}
  @end
  @interface Context : NSObject {
    NSTimer *_timer, *_renderTimer; Renderer *_renderer; id _layer; BOOL _renderRequested;
  }
  - (void)timer:(NSTimer *)timer;
  - (void)startTimerIfNeeded;
  @end
  @implementation Context
  ACTUAL_METHODS
  - (id)init { if((self=[super init])) _renderer=[Renderer new]; return self; }
  - (void)render {
    ++frames;
    // Simulate one delegate invalidation after its current frame began.
    if(frames < requestedFrames) {
      for(unsigned i=0;i<10;++i) [self SCHEDULE];
    }
  }
  - (void)flush {}
  - (void)stop {
    [_timer invalidate]; [_timer release]; _timer=nil;
    [_renderTimer invalidate]; [_renderTimer release]; _renderTimer=nil;
  }
  - (void)dealloc { [self stop]; [_renderer release]; [super dealloc]; }
  @end
  int main(void) {
    @autoreleasepool {
      for(requestedFrames=1; requestedFrames<=3; ++requestedFrames) {
      frames=0;
      Context *context=[Context new];
      [context SCHEDULE];
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
      [context stop]; [context release];
      fprintf(stderr,"observed frames=%u\n",frames);
      assert(frames==requestedFrames && "in-frame requests must coalesce without being lost");
      }
      frames=0; requestedFrames=1; animationFrames=3;
      Context *animated=[Context new]; [animated startTimerIfNeeded];
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
      [animated stop]; [animated release];
      assert(frames==3);
      puts("PASS: one to three frames, coalesced requests, idle stopping and animation continuation");
    }
  }
OBJC
program=program.sub('ACTUAL_METHODS'){methods}.gsub('SCHEDULE',private_scheduler ? 'scheduleRenderIfNeeded' : 'startTimerIfNeeded')
gcc,status=Open3.capture2('gcc','-print-file-name=include')
abort 'missing headers' unless status.success?
Dir.mktmpdir('render-redirty') do |dir|
  input=File.join(dir,'probe.m'); output=File.join(dir,'probe'); File.write(input,program)
  abort 'compile failed' unless system('clang','-O1','-fobjc-runtime=gcc',
    '-fconstant-string-class=NSConstantString',"-I#{sdk}/usr/include/GNUstep","-I#{gcc.strip}",
    input,"-L#{sdk}/usr/lib","-Wl,-rpath,#{sdk}/usr/lib",'-lgnustep-base','-lobjc','-o',output)
  abort 'redirty regression failed' unless system(output,rlimit_core:0)
end
