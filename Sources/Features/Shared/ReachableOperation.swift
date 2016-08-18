//
//  ReachableOperation.swift
//  Operations
//
//  Created by Daniel Thorpe on 24/07/2015.
//  Copyright (c) 2015 Daniel Thorpe. All rights reserved.
//

import Foundation

/**
 Compose your `NSOperation` inside a `ReachableOperation` to
 ensure that it is executed when the desired connectivity is
 available.

 If the device is not reachable, the operation will observe
 the default route reachability, and add your operation as
 soon as the conditions are met.
*/
public class ReachableOperation<T: Operation>: ComposedOperation<T> {

    fileprivate var token: String? = .none
    fileprivate var status: Reachability.NetworkStatus? = .none

    /// The required connectivity kind.
    public let connectivity: Reachability.Connectivity

    internal var reachability: SystemReachabilityType = ReachabilityManager.sharedInstance

    /**
     Composes an operation to ensure that is will definitely be executed as soon as
     the required kind of connectivity is achieved.

     - parameter [unlabeled] operation: any `NSOperation` type.
     - parameter connectivity: a `Reachability.Connectivity` value, defaults to `.AnyConnectionKind`.
    */
    public init(_ operation: T, connectivity: Reachability.Connectivity = .anyConnectionKind) {
        self.connectivity = connectivity
        super.init(operation: operation)
        name = "Reachable Procedure <\(operation.operationName)>"
    }

    public override func execute() {
        reachability.whenConnected(connectivity, block: { super.execute() })
    }
}
