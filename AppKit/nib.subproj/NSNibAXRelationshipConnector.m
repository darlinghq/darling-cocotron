#import "NSNibAXRelationshipConnector.h"

// Accessibility relationships (e.g. AXTitleUIElement) are not exposed, so establishing one does nothing.
@implementation NSNibAXRelationshipConnector
@end

@implementation NSNibAXAttributeConnector

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: _destination forKey: @"AXDestinationArchiveKey"];
    [coder encodeObject: _attributeType forKey: @"AXAttributeTypeArchiveKey"];
    [coder encodeObject: _attributeValue forKey: @"AXAttributeValueArchiveKey"];
}

- (id) initWithCoder: (NSCoder *) coder {
    if ((self = [super init])) {
        _destination = [[coder decodeObjectForKey: @"AXDestinationArchiveKey"] retain];
        _attributeType = [[coder decodeObjectForKey: @"AXAttributeTypeArchiveKey"] retain];
        _attributeValue = [[coder decodeObjectForKey: @"AXAttributeValueArchiveKey"] retain];
    }
    return self;
}

- (void) dealloc {
    [_destination release];
    [_attributeType release];
    [_attributeValue release];
    [super dealloc];
}

@end
