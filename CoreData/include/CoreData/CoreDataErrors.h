#import <CoreData/CoreDataExports.h>
#import <Foundation/NSString.h>

COREDATA_EXPORT NSString *const NSAffectedStoresErrorKey;
COREDATA_EXPORT NSString *const NSAffectedObjectsErrorKey;
COREDATA_EXPORT NSString *const NSDetailedErrorsKey;

// Validation failures. Values as in the public CoreDataErrors.h; the domain is NSCocoaErrorDomain.
enum {
    NSManagedObjectValidationError = 1550,
    NSManagedObjectConstraintValidationError = 1551,
    NSValidationMultipleErrorsError = 1560,
    NSValidationMissingMandatoryPropertyError = 1570,
    NSValidationRelationshipLacksMinimumCountError = 1580,
    NSValidationRelationshipExceedsMaximumCountError = 1590,
    NSValidationRelationshipDeniedDeleteError = 1600,
    NSValidationNumberTooLargeError = 1610,
    NSValidationNumberTooSmallError = 1620,
    NSValidationDateTooLateError = 1630,
    NSValidationDateTooSoonError = 1640,
    NSValidationInvalidDateError = 1650,
    NSValidationStringTooLongError = 1660,
    NSValidationStringTooShortError = 1670,
    NSValidationStringPatternMatchingError = 1680,
    NSValidationInvalidURIError = 1690,
};

enum {
    NSPersistentStoreInvalidTypeError = 134000,
    NSPersistentStoreTypeMismatchError = 134010,
    NSPersistentStoreIncompatibleSchemaError = 134020,
    NSPersistentStoreSaveError = 134030,
    NSPersistentStoreIncompleteSaveError = 134040,
    NSPersistentStoreOperationError = 134070,
    NSPersistentStoreOpenError = 134080,
    NSPersistentStoreTimeoutError = 134090,
    NSPersistentStoreIncompatibleVersionHashError = 134100,
};
