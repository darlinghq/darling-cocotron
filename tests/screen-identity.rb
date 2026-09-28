# Actual NSScreen dictionary/getter/setter methods with GNUstep collections.
require 'tmpdir'
require 'open3'
sdk=ARGV.fetch(0)
source=File.read(ARGV[1] || File.expand_path('../AppKit/NSScreen.m',__dir__))
methods = [/^- \(NSDictionary<NSDeviceDescriptionKey, id> \*\) deviceDescription.*?^\}/m,
  /^- \(CGDirectDisplayID\) cgDirectDisplayID.*?^\}/m,
  /^- \(void\) setCgDirectDisplayID:.*?^\}/m].map { |r| source[r] or abort 'method missing' }.join("\n")
program=<<~'OBJC'
  #import <Foundation/Foundation.h>
  #include <assert.h>
  #include <stdint.h>
  typedef uint32_t CGDirectDisplayID;
  typedef NSString *NSDeviceDescriptionKey;
  @interface Screen : NSObject { CGDirectDisplayID _directDisplayID; }
  @end
  @implementation Screen
  ACTUAL_METHODS
  @end
  int main(void) { @autoreleasepool {
    Screen *a=[Screen new], *b=[Screen new];
    uint32_t ids[]={0,1,2,UINT32_MAX};
    for (unsigned i=0;i<4;i++) {
      [a setCgDirectDisplayID:ids[i]];
      NSDictionary *d=[a deviceDescription];
      NSNumber *n=[d objectForKey:@"NSScreenNumber"];
      assert([n isKindOfClass:[NSNumber class]]);
      assert([n unsignedLongLongValue]==ids[i]);
      assert([n unsignedIntValue]==[a cgDirectDisplayID]);
    }
    [a setCgDirectDisplayID:1]; [b setCgDirectDisplayID:2];
    NSDictionary *snapshot=[[a deviceDescription] retain];
    [a setCgDirectDisplayID:3];
    assert([[snapshot objectForKey:@"NSScreenNumber"] unsignedIntValue]==1);
    assert([[[a deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue]==3);
    assert([[[b deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue]==2);
    [a release]; [b release];
    assert([[snapshot objectForKey:@"NSScreenNumber"] unsignedIntValue]==1);
    [snapshot release];
    puts("PASS: numeric screen identity, zero/high-bit IDs, independent screens and dictionary lifetime");
  } }
OBJC
program=program.sub('ACTUAL_METHODS'){methods}
gcc,status=Open3.capture2('gcc','-print-file-name=include'); abort unless status.success?
Dir.mktmpdir('screen-identity') do |dir|
  input=File.join(dir,'probe.m'); output=File.join(dir,'probe'); File.write(input,program)
  abort 'compile failed' unless system('clang','-fobjc-runtime=gcc','-fconstant-string-class=NSConstantString',
    "-I#{sdk}/usr/include/GNUstep","-I#{gcc.strip}",input,"-L#{sdk}/usr/lib",
    "-Wl,-rpath,#{sdk}/usr/lib",'-lgnustep-base','-lobjc','-o',output)
  Process.setrlimit(Process::RLIMIT_CORE,0)
  abort 'probe failed' unless system(output)
end
