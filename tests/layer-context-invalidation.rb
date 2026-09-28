# Actual timer creation/invalidation with a real GNUstep timer and run loop.
# Usage: ruby tests/layer-context-invalidation.rb GNUSTEP_ROOT [CALayerContext.m]
require 'tmpdir'
require 'open3'
sdk=ARGV.fetch(0)
source=File.read(ARGV[1] || File.expand_path('../QuartzCore/CALayerContext.m',__dir__))
methods=%w[invalidate startTimerIfNeeded].map do |name|
  source[/^- \(void\) #{name} \{.*?^\}/m] or abort "missing #{name}"
end.join("\n")
program=<<~'OBJC'
  #import <Foundation/Foundation.h>
  #include <assert.h>
  static unsigned fires, deaths;
  @interface Context : NSObject { @public NSTimer *_timer; }
  - (void)invalidate;
  - (void)startTimerIfNeeded;
  @end
  @implementation Context
  ACTUAL_METHODS
  - (void)timer:(NSTimer *)timer { ++fires; }
  - (void)dealloc {
    ++deaths; [_timer invalidate]; [_timer release]; [super dealloc];
  }
  @end
  int main(void) {
    @autoreleasepool {
      Context *context=[Context new];
      [context invalidate]; assert(!context->_timer);
      [context startTimerIfNeeded]; NSTimer *timer=[context->_timer retain];
      assert(timer && [timer isValid]);
      [context startTimerIfNeeded]; assert(context->_timer==timer);
      [context invalidate];
      assert(!context->_timer && ![timer isValid]);
      [context invalidate];
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
      assert(fires==0);
      // Invalidation is cancellation, not a permanently disabled context.
      [context startTimerIfNeeded];
      assert(context->_timer && context->_timer!=timer && [context->_timer isValid]);
      [context invalidate]; [timer release]; [context release];
    }
    assert(deaths==1 && fires==0);
    puts("PASS: real timer cancellation, repeated invalidation, no callbacks, restart and eventual deallocation");
  }
OBJC
program=program.sub('ACTUAL_METHODS'){methods}
gcc,status=Open3.capture2('gcc','-print-file-name=include')
abort 'missing headers' unless status.success?
Dir.mktmpdir('layer-invalidation') do |dir|
  input=File.join(dir,'probe.m'); output=File.join(dir,'probe'); File.write(input,program)
  abort 'compile failed' unless system('clang','-O1','-fobjc-runtime=gcc',
    '-fconstant-string-class=NSConstantString',"-I#{sdk}/usr/include/GNUstep","-I#{gcc.strip}",
    input,"-L#{sdk}/usr/lib","-Wl,-rpath,#{sdk}/usr/lib",'-lgnustep-base','-lobjc','-o',output)
  abort 'test failed' unless system(output,rlimit_core:0)
end
