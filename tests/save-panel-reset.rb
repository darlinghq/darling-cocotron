# Actual reset and setter methods with controlled directory and text field.
# Usage: ruby tests/save-panel-reset.rb GNUSTEP_ROOT [COCOTRON_ROOT]
require 'tmpdir'
require 'open3'
sdk,root=ARGV
root ||= File.expand_path('..',__dir__)
source=File.read(File.join(root,'AppKit/NSSavePanel.subproj/NSSavePanel.m'))
names=['resetToDefaultValues','setTitle: (NSString *) title',
 'setNameFieldStringValue: (NSString *) value','_setFilename: (NSString *) filename',
 'setDirectory: (NSString *) directory','setRequiredFileType: (NSString *) type',
 'setAllowedFileTypes: (NSArray *) value',
 'setAllowsOtherFileTypes: (BOOL) value','setAccessoryView: (NSView *) view']
methods=names.map{|n|source[/^- \((?:id|void)\) #{Regexp.escape(n)} \{.*?^\}/m] or abort "missing #{n}"}.join("\n")
program=<<~'OBJC'
  #import <Foundation/Foundation.h>
  #include <assert.h>
  #include <stdbool.h>
  typedef NSObject NSView;
  static unsigned deaths;
  static NSString *defaultDirectory(void) { return @"/controlled/Documents"; }
  @interface NSObject (ContentType)
  - (NSString *)preferredFilenameExtension;
  @end
  @interface Tracked : NSObject @end
  @implementation Tracked
  - (void)dealloc { ++deaths; [super dealloc]; }
  @end
  @interface Field : NSObject { @public NSString *text; }
  @end
  @implementation Field
  - (void)setStringValue:(NSString *)value { [value retain]; [text release]; text=value; }
  - (void)dealloc { [text release]; [super dealloc]; }
  @end
  @interface Panel : NSObject {
  @public id _dialogTitle,_nameFieldStringValue,_filename,_directory,_requiredFileType;
    id _allowedFileTypes,_accessoryView;
    Field *_nameField;
    BOOL _allowsOtherFileTypes,_treatsFilePackagesAsDirectories,_showsHiddenFiles;
  }
  @end
  @implementation Panel
  ACTUAL_METHODS
  - (void)dealloc {
    [_dialogTitle release]; [_nameFieldStringValue release]; [_filename release];
    [_directory release]; [_requiredFileType release]; [_allowedFileTypes release];
    [_accessoryView release]; [_nameField release];
    [super dealloc];
  }
  @end
  int main(void) {
    @autoreleasepool {
      Panel *p=[Panel new]; p->_nameField=[Field new];
      // Install individually owned sentinels without relying on retainCount.
      p->_dialogTitle=[Tracked new]; p->_nameFieldStringValue=[Tracked new];
      p->_filename=[Tracked new]; p->_directory=[Tracked new];
      p->_requiredFileType=[Tracked new]; p->_allowedFileTypes=[Tracked new];
      p->_accessoryView=[Tracked new];
      p->_allowsOtherFileTypes=YES; p->_showsHiddenFiles=YES;
      p->_treatsFilePackagesAsDirectories=YES;
      assert([p resetToDefaultValues]==p);
      printf("released previous values: %u/7\n",deaths);
      assert(deaths==7);
      assert([p->_directory isEqual:@"/controlled/Documents"]);
      assert([p->_dialogTitle isEqual:@"Save"] && [p->_nameField->text isEqual:@""]);
      assert([p->_filename isEqual:@""] && [p->_requiredFileType isEqual:@""]);
      assert(!p->_allowedFileTypes && !p->_accessoryView);
      assert(!p->_allowsOtherFileTypes && !p->_showsHiddenFiles && !p->_treatsFilePackagesAsDirectories);
      for(unsigned i=0;i<10;++i) [p resetToDefaultValues];
      [p release]; assert(deaths==7);
      // A custom backend can have no text field.
      p=[Panel new]; [p resetToDefaultValues]; [p resetToDefaultValues]; [p release];
      puts("PASS: prior ownership released, filters/policies cleared, name field, directory and repeated reset");
    }
  }
OBJC
program=program.sub('ACTUAL_METHODS'){methods}
gcc,status=Open3.capture2('gcc','-print-file-name=include')
abort 'missing headers' unless status.success?
Dir.mktmpdir('save-reset') do |dir|
  input=File.join(dir,'probe.m'); output=File.join(dir,'probe'); File.write(input,program)
  abort 'compile failed' unless system('clang','-O1','-fobjc-runtime=gcc','-fobjc-exceptions','-fexceptions',
    '-fconstant-string-class=NSConstantString',"-I#{sdk}/usr/include/GNUstep","-I#{gcc.strip}",
    input,"-L#{sdk}/usr/lib","-Wl,-rpath,#{sdk}/usr/lib",'-lgnustep-base','-lobjc','-o',output)
  abort 'reset regression failed' unless system(output,rlimit_core:0)
end
