#import <AppKit/NSNibConnector.h>

@interface NSNibAXRelationshipConnector : NSNibConnector {
}

@end

@interface NSNibAXAttributeConnector : NSObject <NSCoding> {
    id _destination;
    NSString *_attributeType;
    id _attributeValue;
}
@end
