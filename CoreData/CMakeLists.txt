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
	${CMAKE_SOURCE_DIR}/src/external/sqlite
)

set(CoreData_sources
    CoreDataErrors.m
    # dllmain.m
    NSAtomicStoreCacheNode.m
    NSAtomicStore.m
    NSAttributeDescription.m
    NSBatchDeleteRequest.m
    NSBatchUpdateRequest.m
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
    NSPersistentStoreRequest.m
    NSPropertyDescription.m
    NSPropertyMapping.m
    NSRelationshipDescription.m
    NSSQLitePersistentStore.m
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
		sqlite3
)

option(DARLING_COREDATA_SWIFT_SUPPLEMENT "Build the arm64 Swift CoreData supplement" OFF)
set(DARLING_SWIFT_TOOLCHAIN "" CACHE PATH "Swift toolchain (bin/swiftc, bin/clang) used to build the supplement")
set(DARLING_SWIFT_IOS_STDLIB "" CACHE PATH "Swift core modules the supplement imports")
set(DARLING_SWIFT_HOST_LIBS "" CACHE PATH "Host libraries the Swift toolchain needs on LD_LIBRARY_PATH")
set(DARLING_COREDATA_SWIFT_SDK "" CACHE PATH "Public iOS SDK for Swift CoreData additions")
set(DARLING_COREDATA_SWIFT_SHIMS "" CACHE PATH "Swift shims matching the iOS core module")
set(DARLING_COREDATA_SWIFT_APINOTES "" CACHE PATH "API notes matching the iOS core module")
if(DARLING_COREDATA_SWIFT_SUPPLEMENT)
    if(NOT TARGET CoreData OR NOT TARGET_ARM64 OR TARGET_x86_64 OR TARGET_i386)
        message(FATAL_ERROR "Swift CoreData supplement requires an arm64-only CoreData target")
    endif()
    foreach(required IN ITEMS DARLING_SWIFT_TOOLCHAIN DARLING_SWIFT_IOS_STDLIB
            DARLING_COREDATA_SWIFT_SDK DARLING_COREDATA_SWIFT_SHIMS DARLING_COREDATA_SWIFT_APINOTES)
        if(NOT IS_DIRECTORY "${${required}}")
            message(FATAL_ERROR "${required} must name an existing directory")
        endif()
    endforeach()
    set(supplement_dir "${CMAKE_CURRENT_BINARY_DIR}/swift")
    set(supplement "${supplement_dir}/libDarlingCoreDataSupplement.dylib")
    add_custom_command(OUTPUT "${supplement}"
        COMMAND ${CMAKE_COMMAND} -E env
            "OUT=${supplement_dir}"
            "SWIFT_TOOLCHAIN=${DARLING_SWIFT_TOOLCHAIN}"
            "SWIFT_CORE_MODULES=${DARLING_SWIFT_IOS_STDLIB}"
            "SWIFT_SHIMS=${DARLING_COREDATA_SWIFT_SHIMS}"
            "SWIFT_APINOTES=${DARLING_COREDATA_SWIFT_APINOTES}"
            "IOS_SDK=${DARLING_COREDATA_SWIFT_SDK}"
            "LD_LIBRARY_PATH=${DARLING_SWIFT_HOST_LIBS}"
            bash "${CMAKE_CURRENT_SOURCE_DIR}/swift/build.sh"
        DEPENDS swift/build.sh swift/NSManagedObjectContext.swift
            swift/Bridge/CoreDataBridge.h swift/Bridge/CoreDataBridge.m
            swift/Bridge/module.modulemap "${DARLING_SWIFT_TOOLCHAIN}/bin/swiftc"
        VERBATIM COMMENT "Building source-only Swift CoreData supplement")
    add_custom_target(CoreDataSwiftSupplement_arm64 DEPENDS "${supplement}")
    add_dependencies(CoreData CoreDataSwiftSupplement_arm64)
    set_property(TARGET CoreData APPEND_STRING PROPERTY LINK_FLAGS
        " -Wl,-reexport_library,${supplement}")
    set_property(TARGET CoreData APPEND PROPERTY LINK_DEPENDS "${supplement}")
    install(PROGRAMS "${supplement}" DESTINATION libexec/darling/usr/lib/swift)
endif()
