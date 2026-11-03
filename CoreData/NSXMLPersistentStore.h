#import <CoreData/NSAtomicStore.h>

@class NSXMLDocument, NSMutableDictionary;

@interface NSXMLPersistentStore : NSAtomicStore {
    NSXMLDocument *_document;
    NSMutableDictionary *_referenceToCacheNode;
    NSMutableDictionary *_referenceToElement;
    NSMutableSet *_usedReferences;
}

- (BOOL)_readStoreURLOnInitialization;
@end
