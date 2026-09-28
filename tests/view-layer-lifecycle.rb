# Actual NSView lifecycle methods with controlled layers, contexts and windows.
# Usage: ruby tests/view-layer-lifecycle.rb GNUSTEP_ROOT [NSView.m]
require 'tmpdir'
require 'open3'
sdk=ARGV.fetch(0)
source=File.read(ARGV[1] || File.expand_path('../AppKit/NSView.m',__dir__))
names=%w[_setWindow: _setSuperview: _removeLayerFromSuperlayer _createLayerContextIfNeeded _addLayerToSuperlayer _removeLayerBackedViewsFromTree]
methods=source.scan(/^- \(void\).*?^\}/m).select{|m| names.any?{|n| m.lines.first.include?(" #{n}")}}.join("\n")
abort 'missing methods' unless names.all?{|n| methods.include?(n)}
program=<<~'OBJC'
  #import <Foundation/Foundation.h>
  #include <assert.h>
  static unsigned created, destroyed, invalidated, bound;
  static BOOL failContext;
  @interface CALayer : NSObject { @public CALayer *parent; } @end
  @implementation CALayer
  - (id)superlayer { return parent; }
  - (void)removeFromSuperlayer { parent=nil; }
  - (void)addSublayer:(CALayer *)layer { assert(layer); layer->parent=self; }
  @end
  @interface NSViewBackingLayer : CALayer @end
  @implementation NSViewBackingLayer @end
  @interface CALayerContext : NSObject @end
  @implementation CALayerContext
  - (id)initWithFrame:(NSRect)frame {
    self=[super init]; ++created;
    if(failContext) { [self release]; return nil; } return self;
  }
  - (void)setLayer:(id)layer {}
  - (void)setSubwindow:(id)window { assert(window); ++bound; }
  - (void)invalidate { ++invalidated; }
  - (void)dealloc { ++destroyed; [super dealloc]; }
  @end
  @interface NSWindow : NSObject @end
  @implementation NSWindow
  - (BOOL)autorecalculatesKeyViewLoop { return NO; }
  - (void)recalculateKeyViewLoop {}
  - (void)invalidateCursorRectsForView:(id)view {}
  - (id)_createSubWindowWithFrame:(NSRect)frame { return self; }
  @end
  @interface View : NSObject {
  @public View *_superview; NSWindow *_window; CALayer *_layer;
    CALayerContext *_layerContext; NSArray *_subviews;
    BOOL _validTrackingAreas, _wantsLayer;
  }
  - (void)_setWindow:(NSWindow *)window;
  - (void)_setSuperview:(id)view;
  - (void)_removeLayerFromSuperlayer;
  - (void)_createLayerContextIfNeeded;
  - (void)_addLayerToSuperlayer;
  - (void)_removeLayerBackedViewsFromTree;
  @end
  @implementation View
  - (id)layer { return _layer; }
  - (NSRect)frame { return NSMakeRect(0,0,20,20); }
  - (void)setNextKeyView:(id)view {}
  - (void)setNextResponder:(id)view {}
  - (void)viewWillMoveToWindow:(id)window {}
  - (void)viewDidMoveToWindow {}
  ACTUAL_METHODS
  - (void)dealloc { [_layerContext release]; [_layer release]; [super dealloc]; }
  @end
  int main(void) {
    @autoreleasepool {
      NSWindow *w=[NSWindow new], *w2=[NSWindow new];
      View *v=[View new], *a=[View new], *b=[View new];
      v->_layer=[CALayer new]; a->_layer=[CALayer new]; b->_layer=[CALayer new];
      [v _addLayerToSuperlayer]; assert(!created && !v->_layerContext);
      [v _setWindow:w]; assert(created==1 && bound==1 && v->_layerContext);
      id context=v->_layerContext;
      [v _addLayerToSuperlayer]; [v _setWindow:w];
      assert(created==1 && v->_layerContext==context);
      [v _setWindow:w2]; assert(created==1 && bound==2);
      [v _setSuperview:a];
      assert(!v->_layerContext && destroyed==1 && invalidated==1);
      assert([v->_layer superlayer]==a->_layer);
      [v _setSuperview:a]; assert(created==1 && destroyed==1);
      [v _setSuperview:b]; assert([v->_layer superlayer]==b->_layer);
      // Mirror removeFromSuperview's superview-then-window order.
      [v _setSuperview:nil]; [v _setWindow:nil];
      assert(![v->_layer superlayer] && !v->_layerContext);
      [v _setWindow:w]; assert(created==2 && v->_layerContext);
      [v _setWindow:nil]; assert(destroyed==2 && !v->_layerContext);
      // Failed context creation remains retryable without dereferencing nil.
      failContext=YES; [v _setWindow:w];
      assert(created==3 && destroyed==3 && !v->_layerContext);
      failContext=NO; [v _addLayerToSuperlayer]; assert(created==4 && v->_layerContext);
      [v _setSuperview:a]; assert(destroyed==4);
      // Removing a parent's layer promotes an explicitly layer-backed child.
      [a->_layer release]; a->_layer=nil;
      v->_wantsLayer=YES; [v _removeLayerBackedViewsFromTree];
      assert(![v->_layer superlayer] && v->_layerContext && created==5);
      [v _removeLayerBackedViewsFromTree]; assert(created==5);
      [v release]; [a release]; [b release]; [w release]; [w2 release];
      assert(created==destroyed);
      puts("PASS: detached/attached, repeated, cross-window, cross-parent, failure retry and child promotion");
    }
  }
OBJC
program=program.sub('ACTUAL_METHODS'){methods}
gcc,status=Open3.capture2('gcc','-print-file-name=include')
abort 'missing headers' unless status.success?
Dir.mktmpdir('view-layer-lifecycle') do |dir|
  input=File.join(dir,'probe.m'); output=File.join(dir,'probe'); File.write(input,program)
  abort 'compile failed' unless system('clang','-O1','-fobjc-runtime=gcc',
    '-fconstant-string-class=NSConstantString',"-I#{sdk}/usr/include/GNUstep","-I#{gcc.strip}",
    input,"-L#{sdk}/usr/lib","-Wl,-rpath,#{sdk}/usr/lib",'-lgnustep-base','-lobjc','-o',output)
  abort 'test failed' unless system(output,rlimit_core:0)
end
