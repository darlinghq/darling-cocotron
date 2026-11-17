project(CoreData)

include(darling_framework)

remove_sdk_framework(CoreData)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} \
	-include math.h \
	-include stdlib.h \
	-include CoreFoundation/CoreFoundation.h \
	-include Foundation/Foundation.h \
	-Wno-nonportable-include-path \
	-Wno-deprecated-objc-isa-usage \
	-mmacosx-version-min=10.10"
)

include_directories(
	${CMAKE_SOURCE_DIR}/src/external/icu/icuSources/i18n
	${CMAKE_SOURCE_DIR}/src/external/icu/icuSources/common

	${CMAKE_CURRENT_SOURCE_DIR}
)

set(CoreData_sources
    CoreDataErrors.m
    # dllmain.m
    NSAtomicStoreCacheNode.m
    NSAtomicStore.m
    NSAttributeDescription.m
    NSEntityDescription.m
    NSEntityMapping.m
    NSFetchedPropertyDescription.m
    NSFetchRequest.m
    NSFetchRequestExpression.m
    NSInMemoryPersistentStore.m
    NSManagedObjectContext.m
    NSManagedObjectID.m
    NSManagedObject.m
    NSManagedObjectModel.m
    NSManagedObjectMutableSet.m
    NSManagedObjectSetEnumerator.m
    NSManagedObjectSet.m
    NSMappingModel.m
    NSPersistentContainer.m
    NSPersistentStoreDescription.m
    NSPersistentStoreCoordinator.m
    NSPersistentStore.m
    NSPropertyDescription.m
    NSPropertyMapping.m
    NSRelationshipDescription.m
    NSXMLPersistentStore.m
    NSMergeConflict.m
    NSMergePolicy.m
)

set_source_files_properties(${CoreData_sources} LANGUAGE C)

set(DYLIB_COMPAT_VERSION "1.0.0")
set(DYLIB_CURRENT_VERSION "752.0.0")

set(FRAMEWORK_VERSION "A")

generate_sdk_framework(CoreData
    VERSION ${FRAMEWORK_VERSION}
    HEADER "include/CoreData"
)

add_framework(CoreData
	FAT
	CURRENT_VERSION
	SOURCES
		${CoreData_sources}
	VERSION ${FRAMEWORK_VERSION}
	DEPENDENCIES
		objc
		system
		CoreFoundation
		Foundation
)
