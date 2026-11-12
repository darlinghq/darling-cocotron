#import <AppKit/NSNib.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSString.h>
#import <AppKit/NSStoryboard-Private.h>

@interface NSNib (private)
- (NSDictionary *) externalNameTable;
@end

// Stands in for an object that the code loading the nib supplies in the
// external name table under the placeholder's identifier, or for a storyboard scene's storyboard.
@interface NSNibExternalObjectPlaceholder : NSObject {
    NSString *_externalObjectPlaceholderIdentifier;
}
@end

@implementation NSNibExternalObjectPlaceholder

- (instancetype) initWithCoder: (NSCoder *) coder {
    NSString *identifier = [coder decodeObjectForKey: @"NSExternalObjectPlaceholderIdentifier"];
    if (![identifier isKindOfClass: [NSString class]])
        [NSException raise: NSInvalidUnarchiveOperationException
                    format: @"%@ has no identifier", [self class]];

    _externalObjectPlaceholderIdentifier = [identifier copy];
    return self;
}

- (void) dealloc {
    [_externalObjectPlaceholderIdentifier release];
    [super dealloc];
}

- (id) awakeAfterUsingCoder: (NSCoder *) coder {
    id nib = [(NSKeyedUnarchiver *) coder delegate];
    NSDictionary *nameTable = [nib respondsToSelector: @selector(externalNameTable)]
                                      ? [nib externalNameTable]
                                      : nil;
    id external = [nameTable objectForKey: _externalObjectPlaceholderIdentifier];

    if (external == nil)
        external = [nameTable objectForKey: NSStoryboardSceneExternalObjectKey];

    if (external == nil)
        [NSException raise: NSInternalInconsistencyException
                    format: @"No object in the external name table for nib placeholder '%@'",
                            _externalObjectPlaceholderIdentifier];

    [external retain];
    [self release];
    return external;
}

@end
