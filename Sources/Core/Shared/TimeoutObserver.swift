//
//  TimeoutObserver.swift
//  Operations
//
//  Created by Daniel Thorpe on 27/06/2015.
//  Copyright (c) 2015 Daniel Thorpe. All rights reserved.
//

import Foundation

/**
An operation observer which will automatically cancels (with an error)
if it doesn't finish before a time interval is expired.
*/
public struct TimeoutObserver: OperationWillExecuteObserver {

    internal let timeout: TimeInterval

    /**
    Initialize the operation observer with a timeout, which will start when
    the operation to which it is attached starts.

    - parameter timeout: a `NSTimeInterval` value.
    */
    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    /**
    Conforms to `OperationObserver`, when the operation starts, it triggers
    a block using dispatch_after and the time interval. When the block runs,
    if the operation has not finished and is not cancelled, then it will
    cancel it with an error of `OperationError.OperationTimedOut`

    - parameter operation: the `Procedure` which will be cancelled if the timeout is reached.
    */
    public func willExecuteOperation(_ operation: Procedure) {
        let when = DispatchTime.now() + Double(Int64(timeout * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)

        Queue.default.queue.asyncAfter(deadline: when) {
            if !operation.isFinished && !operation.isCancelled {
                let error = OperationError.operationTimedOut(self.timeout)
                operation.cancelWithError(error)
            }
        }
    }
}
