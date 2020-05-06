#import <AppKit/NSRuleEditor.h>

NSString *const NSRuleEditorRowsDidChangeNotification =
    @"NSRuleEditorRowsDidChangeNotification";

@implementation NSRuleEditor

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
}
@end
