#import <AppKit/NSApplication.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSPrintPanel.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSPathUtilities.h>
#import <objc/message.h>
#import "NSPrintDialogSupport.h"

// The panel of a print job: the copies and the collation, the pages and where the job goes. There is no
// print queue, so the job goes to a PDF file, which the panel asks for.
@interface _NSPrintPanelController : NSObject {
    NSPrintInfo *_printInfo;
    NSPrintPanelOptions _options;
    _NSPrintDialogWindow *_window;
    NSTextField *_copies, *_first, *_last, *_path;
    NSButton *_collate;
    NSPopUpButton *_pages;
}
- initWithPrintInfo: (NSPrintInfo *) printInfo options: (NSPrintPanelOptions) options;
- (NSInteger) run;
@end

@implementation _NSPrintPanelController

- initWithPrintInfo: (NSPrintInfo *) printInfo options: (NSPrintPanelOptions) options {
    NSDictionary *attributes = [printInfo dictionary];
    NSNumber *copies = [attributes objectForKey: NSPrintCopies];
    NSString *path = [attributes objectForKey: NSPrintSavePath];
    BOOL allPages = [attributes objectForKey: NSPrintAllPages] == nil || [[attributes objectForKey: NSPrintAllPages] boolValue];
    NSString *title = [attributes objectForKey: @"_title"];
    NSView *content;

    _printInfo = [printInfo retain];
    _options = options;
    if (path == nil)
        path = [NSHomeDirectory() stringByAppendingPathComponent: [(title != nil ? title : @"Untitled") stringByAppendingPathExtension: @"pdf"]];

    _window = NSPrintDialogMakeWindow(@"Print", NSMakeSize(420, 250), self);
    content = [_window contentView];
    [content addSubview: NSPrintDialogLabel(@"Printer:", NSMakeRect(20, 205, 80, 22))];
    [content addSubview: NSPrintDialogPopUp([NSArray arrayWithObject: @"PDF File"], NSMakeRect(105, 203, 295, 26))];
    [content addSubview: NSPrintDialogLabel(@"Save to:", NSMakeRect(20, 171, 80, 22))];
    _path = NSPrintDialogField(path, NSMakeRect(105, 169, 205, 24));
    [content addSubview: _path];
    [content addSubview: NSPrintDialogButton(@"Choose...", NSMakeRect(314, 166, 86, 28), self, @selector(choose:))];
    if (_options & NSPrintPanelShowsCopies) {
        [content addSubview: NSPrintDialogLabel(@"Copies:", NSMakeRect(20, 135, 80, 22))];
        _copies = NSPrintDialogField([NSString stringWithFormat: @"%d", copies != nil ? [copies intValue] : 1],
                                     NSMakeRect(105, 133, 60, 24));
        [content addSubview: _copies];
        _collate = [[[NSButton alloc] initWithFrame: NSMakeRect(180, 133, 120, 24)] autorelease];
        [_collate setButtonType: NSSwitchButton];
        [_collate setTitle: @"Collated"];
        [_collate setState: [[attributes objectForKey: NSPrintMustCollate] boolValue] ? NSOnState : NSOffState];
        [content addSubview: _collate];
    }
    if (_options & NSPrintPanelShowsPageRange) {
        [content addSubview: NSPrintDialogLabel(@"Pages:", NSMakeRect(20, 99, 80, 22))];
        _pages = NSPrintDialogPopUp([NSArray arrayWithObjects: @"All", @"Range", nil], NSMakeRect(105, 97, 90, 26));
        [_pages selectItemAtIndex: allPages ? 0 : 1];
        [content addSubview: _pages];
        [content addSubview: NSPrintDialogLabel(@"From:", NSMakeRect(205, 99, 40, 22))];
        _first = NSPrintDialogField([[attributes objectForKey: NSPrintFirstPage] description] ?: @"1", NSMakeRect(247, 97, 50, 24));
        [content addSubview: _first];
        [content addSubview: NSPrintDialogLabel(@"to:", NSMakeRect(305, 99, 25, 22))];
        _last = NSPrintDialogField([[attributes objectForKey: NSPrintLastPage] description] ?: @"1", NSMakeRect(332, 97, 50, 24));
        [content addSubview: _last];
    }
    NSPrintDialogAddButtons(_window, @"Print", self);
    return self;
}

- (void) dealloc {
    [_window release];
    [_printInfo release];
    [super dealloc];
}

- (void) choose: (id) sender {
    NSSavePanel *panel = [NSSavePanel savePanel];

    [panel setNameFieldStringValue: [[_path stringValue] lastPathComponent]];
    [panel setDirectoryURL: [NSURL fileURLWithPath: [[_path stringValue] stringByDeletingLastPathComponent]]];
    if ([panel runModal] == NSOKButton && [panel URL] != nil)
        [_path setStringValue: [[panel URL] path]];
}

// The values of the panel go into the print info, as its attributes
- (void) accept: (id) sender {
    NSMutableDictionary *attributes = [_printInfo dictionary];
    NSInteger copies = _copies != nil ? [_copies integerValue] : 1;

    if (_copies != nil) {
        [attributes setObject: [NSNumber numberWithInteger: copies < 1 ? 1 : copies] forKey: NSPrintCopies];
        [attributes setObject: [NSNumber numberWithBool: [_collate state] == NSOnState] forKey: NSPrintMustCollate];
    }
    if (_pages != nil) {
        if ([_pages indexOfSelectedItem] == 0) {
            [attributes setObject: [NSNumber numberWithBool: YES] forKey: NSPrintAllPages];
        } else {
            NSInteger first = [_first integerValue], last = [_last integerValue];

            if (first < 1)
                first = 1;
            if (last < first)
                last = first;
            [attributes setObject: [NSNumber numberWithBool: NO] forKey: NSPrintAllPages];
            [attributes setObject: [NSNumber numberWithInteger: first] forKey: NSPrintFirstPage];
            [attributes setObject: [NSNumber numberWithInteger: last] forKey: NSPrintLastPage];
        }
    }
    [attributes setObject: NSPrintSaveJob forKey: NSPrintJobDisposition];
    [attributes setObject: [[_path stringValue] stringByExpandingTildeInPath] forKey: NSPrintSavePath];
    [NSApp stopModalWithCode: NSOKButton];
}

- (void) cancel: (id) sender {
    [NSApp stopModalWithCode: NSCancelButton];
}

- (NSInteger) run {
    return NSPrintDialogRun(_window);
}

@end

@implementation NSPrintPanel

+ (NSPrintPanel *) printPanel {
    return [[[self alloc] init] autorelease];
}

- init {
    self = [super init];
    _options = NSPrintPanelShowsCopies | NSPrintPanelShowsPageRange;
    return self;
}

- (void) dealloc {
    [_attributes release];
    [_accessoryControllers release];
    [super dealloc];
}

- (NSArray *) accessoryControllers {
    return _accessoryControllers ? [[_accessoryControllers copy] autorelease]
                                 : [NSArray array];
}

- (void) addAccessoryController: (NSViewController *) controller {
    if (controller == nil)
        return;
    if (_accessoryControllers == nil)
        _accessoryControllers = [[NSMutableArray alloc] init];
    if ([_accessoryControllers indexOfObjectIdenticalTo: controller] == NSNotFound)
        [_accessoryControllers addObject: controller];
}

- (void) removeAccessoryController: (NSViewController *) controller {
    [_accessoryControllers removeObjectIdenticalTo: controller];
}

- (void) setOptions: (NSPrintPanelOptions) options {
    _options = options;
}

- (NSPrintPanelOptions) options {
    return _options;
}

- (int) runModalWithPrintInfo: (NSPrintInfo *) printInfo {
    _NSPrintPanelController *controller = [[_NSPrintPanelController alloc] initWithPrintInfo: printInfo options: _options];
    NSInteger result = [controller run];

    [controller release];
    return result == NSOKButton ? NSOKButton : NSCancelButton;
}

- (int) runModal {
    NSPrintInfo *printInfo = [[NSPrintOperation currentOperation] printInfo];

    return [self runModalWithPrintInfo: printInfo != nil ? printInfo : [NSPrintInfo sharedPrintInfo]];
}

- (void) beginSheetWithPrintInfo: (NSPrintInfo *) printInfo
                  modalForWindow: (NSWindow *) docWindow
                        delegate: (id) delegate
                  didEndSelector: (SEL) didEndSelector
                     contextInfo: (void *) contextInfo
{
    NSInteger returnCode = [self runModalWithPrintInfo: printInfo];

    if (delegate != nil && didEndSelector != NULL)
        ((void (*)(id, SEL, NSPrintPanel *, NSInteger, void *)) objc_msgSend)(
                delegate, didEndSelector, self, returnCode, contextInfo);
}

- (void) updateFromPrintInfo {
    NSDictionary *source = [[[NSPrintOperation currentOperation] printInfo] dictionary];

    [_attributes release];
    _attributes = [source mutableCopy];
}

- (void) finalWritePrintInfo {
    NSMutableDictionary *destination = [[[NSPrintOperation currentOperation] printInfo] dictionary];

    [destination addEntriesFromDictionary: _attributes];
}

@end

NSString *const NSPrintPanelAccessorySummaryItemNameKey =
        @"NSPrintPanelAccessorySummaryItemName";
NSString *const NSPrintPanelAccessorySummaryItemDescriptionKey =
        @"NSPrintPanelAccessorySummaryItemDescription";
