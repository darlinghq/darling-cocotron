# Execute actual toolbar-item ownership methods with controlled view objects.
# Usage: ruby tests/toolbar-copy.rb GNUSTEP_ROOT [BASELINE_REF]
require 'open3'
require 'tmpdir'
sdk = ARGV.fetch(0)
root = File.expand_path('..', __dir__)
path = 'AppKit/NSToolbar.subproj/NSToolbarItem.m'
source = if ARGV[1]
  out, status = Open3.capture2('git', '-C', root, 'show', "#{ARGV[1]}:#{path}")
  abort out unless status.success?
  out
else
  File.read("#{root}/#{path}")
end
methods = [/^- \(instancetype\) initWithItemIdentifier:.*?^\}/m,
           /^- \(void\) dealloc.*?^\}/m,
           /^- copyWithZone:.*?^\}/m,
           /^- \(void\) setToolTip:.*?^\}/m].map do |pattern|
  source[pattern] or abort "missing method #{pattern}"
end.join("\n")
program = <<~'OBJC'
  #import <Foundation/Foundation.h>
  #include <assert.h>
  typedef NSString *NSToolbarItemIdentifier;
  enum { NSToolbarItemVisibilityPriorityStandard=0 };
  static int liveViews;
  @interface ProbeView : NSObject <NSCopying> {
    @public id owner, child; NSRect rect;
  }
  - (id)initWithFrame:(NSRect)frame;
  - (NSRect)frame;
  - (void)setToolbarItem:(id)item;
  - (void)setSubview:(id)view;
  @end
  @implementation ProbeView
  - (id)init { return [self initWithFrame:NSZeroRect]; }
  - (id)initWithFrame:(NSRect)frame {
    if ((self=[super init])) { liveViews++; rect=frame; }
    return self;
  }
  - (NSRect)frame { return rect; }
  - (void)setToolbarItem:(id)item { owner=item; }
  - (void)setSubview:(id)view { [view retain]; [child release]; child=view; }
  - (id)copyWithZone:(NSZone*)zone {
    return [[[self class] allocWithZone:zone] initWithFrame:rect];
  }
  - (void)dealloc { liveViews--; [child release]; [super dealloc]; }
  @end
  #define NSToolbarItemView ProbeView
  @interface NSToolbarItem : NSObject <NSCopying> {
    @public id _itemIdentifier, _toolbar, _toolTip, _image, _label, _paletteLabel;
    id _target, _menuFormRepresentation, _view;
    ProbeView *_enclosingView;
    SEL _action;
    NSSize _minSize, _maxSize;
    NSInteger _visibilityPriority;
    BOOL _autovalidates, _isEnabled;
  }
  - (id)initWithItemIdentifier:(NSString*)identifier;
  - (void)setToolTip:(NSString*)tip;
  @end
  @implementation NSToolbarItem
  - (void)_configureAsStandardItemIfNeeded {}
  METHODS
  @end
  int main(void) {
    @autoreleasepool {
      for (int custom=0; custom<2; custom++) {
        for (int originalFirst=0; originalFirst<2; originalFirst++) {
          NSToolbarItem *item=[[NSToolbarItem alloc] initWithItemIdentifier:@"test"];
          item->_enclosingView->rect=NSMakeRect(2,3,40,50);
          item->_toolbar=(id)@"original toolbar";
          if (custom) {
            item->_view=[ProbeView new];
            [item->_enclosingView setSubview:item->_view];
          }
          NSMutableString *tip=[NSMutableString stringWithString:@"original tooltip"];
          [item setToolTip:tip];
          [tip appendString:@" changed externally"];
          assert([item->_toolTip isEqual:@"original tooltip"]);
          id originalTip=[item->_toolTip retain];
          NSUInteger tipCount=[originalTip retainCount];
          NSToolbarItem *copy=[item copy];
          assert(copy!=item && copy->_toolbar==nil);
          assert(copy->_enclosingView!=item->_enclosingView);
          assert(copy->_enclosingView->owner==copy && item->_enclosingView->owner==item);
          assert(NSEqualRects([copy->_enclosingView frame],[item->_enclosingView frame]));
          assert(copy->_enclosingView->child==copy->_view);
          assert(!custom || (copy->_view!=item->_view && copy->_view!=nil));
          if (copy->_toolTip==originalTip) assert([originalTip retainCount]==tipCount+1);
          [copy setToolTip:@"copy tooltip"];
          assert([item->_toolTip isEqual:@"original tooltip"]);
          ProbeView *originalView=[item->_enclosingView retain];
          ProbeView *copyView=[copy->_enclosingView retain];
          if (originalFirst) {
            [item release];
            assert(originalView->owner==nil && copyView->owner==copy);
            [copy release];
          } else {
            [copy release];
            assert(copyView->owner==nil && originalView->owner==item);
            [item release];
          }
          assert(originalView->owner==nil && copyView->owner==nil);
          assert([originalTip retainCount]==1);
          [originalTip release]; [originalView release]; [copyView release];
          assert(liveViews==0);
        }
      }
    }
    puts("PASS: independent copy views, owner rebinding, custom child, tooltip ownership, both destruction orders");
  }
OBJC
program.sub!('METHODS') { methods }
gcc, status = Open3.capture2('gcc', '-print-file-name=include'); abort unless status.success?
Dir.mktmpdir('toolbar-copy') do |dir|
  input="#{dir}/probe.m"; output="#{dir}/probe"; File.write(input,program)
  log,status=Open3.capture2e('clang','-fobjc-runtime=gcc','-fconstant-string-class=NSConstantString',
    "-I#{sdk}/usr/include/GNUstep","-I#{gcc.strip}",input,"-L#{sdk}/usr/lib",
    "-Wl,-rpath,#{sdk}/usr/lib",'-lgnustep-base','-lobjc','-o',output)
  abort log unless status.success?
  abort 'test failed' unless system(output,rlimit_core:0)
end
