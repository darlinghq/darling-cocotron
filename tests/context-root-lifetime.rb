# Actual context setter/deallocator and layer context propagation, with host
# Foundation and controlled renderer/CGL adapters. No GL rendering is tested.
# Usage: ruby tests/context-root-lifetime.rb GNUSTEP_ROOT [COCOTRON_ROOT]
require 'tmpdir'
require 'open3'
sdk,root=ARGV
root ||= File.expand_path('..',__dir__)
context=File.read(File.join(root,'QuartzCore/CALayerContext.m'))
layer=File.read(File.join(root,'QuartzCore/CALayer.m'))
def method(source, signature)
  source[/^#{Regexp.escape(signature)} \{.*?^\}/m] or abort "missing #{signature}"
end
context_methods=['- (void) setLayer: (CALayer *) layer','- (void) dealloc'].map { |s| method(context,s) }.join("\n")
layer_methods=['- (CALayerContext *) _context','- (void) _setContext: (CALayerContext *) context'].map { |s| method(layer,s) }.join("\n")
program=<<~'OBJC'
  #import <Foundation/Foundation.h>
  #include <assert.h>
  static unsigned destroyedLayers, cleanupCalls, resourcesReleased;
  static void CGLReleaseContext(void *x) { ++resourcesReleased; }
  static void CGLReleasePixelFormat(void *x) {}
  static void CGLDestroyWindow(void *x) {}
  @class CALayerContext;
  @interface CALayer : NSObject {
  @public
    CALayerContext *_context;
    NSArray *_sublayers;
    CALayer *_mask;
    NSNumber *_textureId;
  }
  - (CALayerContext *)_context;
  - (void)_setContext:(CALayerContext *)context;
  @end
  @interface Renderer : NSObject { CALayer *root; }
  - (void)setLayer:(CALayer *)layer;
  @end
  @implementation Renderer
  - (void)setLayer:(CALayer *)layer { [layer retain]; [root release]; root=layer; }
  - (void)dealloc { [root release]; [super dealloc]; }
  @end
  @interface CALayerContext : NSObject {
    NSTimer *_timer; Renderer *_renderer; CALayer *_layer;
    void *_glContext, *_pixelFormat, *_cglWindow; id _subwindow;
  }
  - (void)setLayer:(CALayer *)layer;
  - (void)deleteTextureId:(NSNumber *)texture;
  @end
  @implementation CALayer
  LAYER_METHODS
  - (void)dealloc {
    ++destroyedLayers;
    [_sublayers release]; [_mask release]; [_textureId release];
    [super dealloc];
  }
  @end
  @implementation CALayerContext
  CONTEXT_METHODS
  - (id)init { if ((self=[super init])) _renderer=[Renderer new]; return self; }
  - (void)deleteTextureId:(NSNumber *)texture {
    if (texture) { assert(resourcesReleased==0); ++cleanupCalls; }
  }
  @end
  static void assertTree(CALayer *layer,CALayerContext *context) {
    assert([layer _context]==context);
    for(CALayer *child in layer->_sublayers) assertTree(child,context);
    if(layer->_mask) assertTree(layer->_mask,context);
  }
  static CALayer *tree(void) {
    CALayer *root=[CALayer new], *child=[CALayer new];
    root->_sublayers=[[NSArray alloc] initWithObjects:child,nil]; [child release];
    root->_mask=[CALayer new]; return root;
  }
  static void textures(CALayer *layer) {
    layer->_textureId=[[NSNumber alloc] initWithInt:42];
    for(CALayer *child in layer->_sublayers) textures(child);
    if(layer->_mask) textures(layer->_mask);
  }
  int main(void) {
    @autoreleasepool {
      CALayerContext *c=[CALayerContext new]; CALayer *a=tree(), *b=tree();
      [c setLayer:a]; assertTree(a,c); textures(a);
      [c setLayer:a]; assertTree(a,c); assert(cleanupCalls==0);
      [c setLayer:b]; assertTree(a,nil); assertTree(b,c); assert(cleanupCalls==3);
      [c setLayer:nil]; assertTree(b,nil); [c setLayer:nil];
      [c release]; [a release]; [b release];
      // External references survive context destruction, including descendants.
      resourcesReleased=0; cleanupCalls=0;
      c=[CALayerContext new]; a=tree(); [c setLayer:a]; textures(a);
      [c release]; assertTree(a,nil); assert(cleanupCalls==3);
      assert(resourcesReleased==1); [a release];
      // An older context must not clear a newer context's binding on teardown.
      resourcesReleased=0;
      c=[CALayerContext new]; CALayerContext *other=[CALayerContext new]; a=tree();
      [c setLayer:a]; [other setLayer:a]; [c release]; assertTree(a,other);
      [other setLayer:nil]; assertTree(a,nil); [other release]; [a release];
      // Likewise when the old context replaces its root after the rebind.
      resourcesReleased=0;
      c=[CALayerContext new]; other=[CALayerContext new]; a=tree(); b=tree();
      [c setLayer:a]; [other setLayer:a]; [c setLayer:b];
      assertTree(a,other); assertTree(b,c);
      [c release]; assertTree(a,other); assertTree(b,nil);
      [other release]; assertTree(a,nil); [a release]; [b release];
      // Context + renderer are the only remaining owners of the old root.
      resourcesReleased=0; unsigned before=destroyedLayers;
      c=[CALayerContext new]; a=tree(); [c setLayer:a]; [a release];
      [c setLayer:nil]; assert(destroyedLayers==before+3); [c release];
      puts("PASS: replacement, clear, self-assignment, teardown, children/mask, rebind and sole ownership");
    }
  }
OBJC
program=program.sub('LAYER_METHODS'){layer_methods}.sub('CONTEXT_METHODS'){context_methods}
gcc,status=Open3.capture2('gcc','-print-file-name=include')
abort 'missing GCC headers' unless status.success?
Dir.mktmpdir('context-root-lifetime') do |dir|
  input=File.join(dir,'probe.m'); output=File.join(dir,'probe'); File.write(input,program)
  abort 'compile failed' unless system('clang','-O1','-fobjc-runtime=gcc',
    '-fconstant-string-class=NSConstantString',"-I#{sdk}/usr/include/GNUstep","-I#{gcc.strip}",
    input,"-L#{sdk}/usr/lib","-Wl,-rpath,#{sdk}/usr/lib",'-lgnustep-base','-lobjc','-o',output)
  abort 'lifetime regression failed' unless system(output,rlimit_core:0)
end
