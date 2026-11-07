# Run actual configuration implementation with GNUstep Foundation. Only the
# drawing method is excluded; color objects are represented by lifetime tokens.
require 'tmpdir'
require 'open3'
sdk = ARGV.fetch(0)
root = ARGV[1] || File.expand_path('..', __dir__)
header = File.read(File.join(root, 'AppKit/include/AppKit/NSImage.h'))
source = File.read(File.join(root, 'AppKit/NSImage.m'))
interface = header[/@interface NSImageSymbolConfiguration :.*?@end/m] or abort 'interface missing'
implementation = source[/@implementation NSImageSymbolConfiguration\n(.*?)^\+ \(void\) _drawSymbolPlaceholder:/m, 1] or abort 'implementation missing'
program = <<~'OBJC'
  #import <Foundation/Foundation.h>
  #include <assert.h>
  #include <math.h>
  typedef CGFloat NSFontWeight;
  typedef NSInteger NSImageSymbolScale;
  enum { NSImageSymbolScaleSmall=1, NSImageSymbolScaleMedium=2, NSImageSymbolScaleLarge=3 };
  @class NSColor;
  ACTUAL_INTERFACE
  @implementation NSImageSymbolConfiguration
  ACTUAL_IMPLEMENTATION
  @end
  static unsigned destroyed;
  @interface ColorToken : NSObject @end
  @implementation ColorToken
  - (void)dealloc { ++destroyed; [super dealloc]; }
  @end
  static NSArray *palette(id c) { return [c valueForKey:@"_paletteColors"]; }
  int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    assert([NSImageSymbolConfiguration respondsToSelector:@selector(configurationWithPaletteColors:)]);
    ColorToken *first = [ColorToken new], *second = [ColorToken new];
    NSMutableArray *input = [NSMutableArray arrayWithObject:first];
    id a = [NSImageSymbolConfiguration configurationWithPaletteColors:(id)input];
    [input removeAllObjects];
    assert([palette(a) count]==1 && [palette(a) objectAtIndex:0]==first);
    id equal = [NSImageSymbolConfiguration configurationWithPaletteColors:(id)@[first]];
    id b = [NSImageSymbolConfiguration configurationWithPaletteColors:(id)@[second]];
    assert([a isEqual:equal] && [a hash]==[equal hash] && ![a isEqual:b]);
    id copy = [a copy]; assert(copy==a); [copy release];
    id size = [NSImageSymbolConfiguration configurationWithPointSize:22 weight:0.5 scale:3];
    CGFloat side = [size _placeholderSide];
    id sized = [size configurationByApplyingConfiguration:a];
    assert([palette(sized) isEqual:palette(a)] && [sized _placeholderSide]==side);
    assert(palette(size)==nil && [a _placeholderSide]!=side);
    id reverse = [a configurationByApplyingConfiguration:size];
    assert([reverse isEqual:sized] && [reverse hash]==[sized hash]);
    id replaced = [sized configurationByApplyingConfiguration:b];
    assert([palette(replaced) isEqual:palette(b)] && [replaced _placeholderSide]==side);
    assert([palette(sized) isEqual:palette(a)] && [palette(a) objectAtIndex:0]==first);
    id scaled = [sized configurationByApplyingConfiguration:
        [NSImageSymbolConfiguration configurationWithScale:1]];
    assert([palette(scaled) isEqual:palette(a)] && [scaled _placeholderSide]<side);
    assert([[scaled valueForKey:@"_pointSize"] doubleValue]==22);
    assert([[scaled valueForKey:@"_weight"] doubleValue]==0.5);
    assert([[sized configurationByApplyingConfiguration:nil] isEqual:sized]);
    id empty = [NSImageSymbolConfiguration configurationWithPaletteColors:@[]];
    assert(![empty isEqual:[NSImageSymbolConfiguration configurationWithScale:0]]);
    assert([palette([sized configurationByApplyingConfiguration:empty]) count]==0);
    [first release]; [second release]; assert(destroyed==0);
    // Keep one merged configuration beyond the factory autorelease pool.
    [replaced retain]; [pool drain]; assert(destroyed==1);
    pool = [NSAutoreleasePool new];
    assert([palette(replaced) count]==1);
    [replaced release]; assert(destroyed==2);
    [pool drain];
    puts("PASS: palette snapshot, equality, immutable merge, size/scale preservation and lifetime");
  }
OBJC
program = program.sub('ACTUAL_INTERFACE') { interface }.sub('ACTUAL_IMPLEMENTATION') { implementation }
gcc, status = Open3.capture2('gcc', '-print-file-name=include')
abort 'GCC headers unavailable' unless status.success?
Dir.mktmpdir('symbol-palette') do |dir|
  input = File.join(dir, 'probe.m'); output = File.join(dir, 'probe')
  File.write(input, program)
  abort 'compile failed' unless system('clang', '-fobjc-runtime=gcc', '-fconstant-string-class=NSConstantString',
    "-I#{sdk}/usr/include/GNUstep", "-I#{gcc.strip}", input,
    "-L#{sdk}/usr/lib", "-Wl,-rpath,#{sdk}/usr/lib", '-lgnustep-base', '-lobjc', '-lm', '-o', output)
  Process.setrlimit(Process::RLIMIT_CORE, 0)
  abort 'probe failed' unless system(output)
end
