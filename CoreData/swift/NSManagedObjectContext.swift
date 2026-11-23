//===----------------------------------------------------------------------===//
// This source file is part of the Swift.org open source project
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
// See https://swift.org/LICENSE.txt and https://swift.org/CONTRIBUTORS.txt
// Adapted fetch-only from swiftlang/swift ba33f9e0b772015326bdecc0d597b2ac9fc61717
// stdlib/public/SDK/CoreData/NSManagedObjectContext.swift.
//===----------------------------------------------------------------------===//
@_exported import CoreData
import Foundation
import DarlingCoreDataSupplementBridge

extension NSManagedObjectContext {
    public func fetch<T>(_ request: NSFetchRequest<T>) throws -> [T]
        where T: NSFetchRequestResult {
        var error: NSError?
        let values = DarlingCoreDataExecuteFetch(self, request, &error)
        guard let values else {
            if let error { throw error }
            preconditionFailure("CoreData fetch returned neither results nor an error")
        }
        return values as! [T]
    }
}
