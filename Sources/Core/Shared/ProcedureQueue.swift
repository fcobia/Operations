//
//  ProcedureQueue.swift
//  Operations
//
//  Created by Daniel Thorpe on 26/06/2015.
//  Copyright (c) 2015 Daniel Thorpe. All rights reserved.
//

import Foundation

/**
A protocol which the `ProcedureQueue`'s delegate must conform to. The delegate is informed
when the queue is about to add an operation, and when operations finish. Because it is a
delegate protocol, conforming types must be classes, as the queue weakly owns it.
*/
public protocol OperationQueueDelegate: class {

    /**
    The operation queue will add a new operation. This is for information only, the
    delegate cannot affect whether the operation is added, or other control flow.

    - paramter queue: the `ProcedureQueue`.
    - paramter operation: the `NSOperation` instance about to be added.
    */
    func operationQueue(_ queue: ProcedureQueue, willAddOperation operation: Operation)

    /**
    An operation has finished on the queue.

    - parameter queue: the `ProcedureQueue`.
    - parameter operation: the `NSOperation` instance which finished.
    - parameter errors: an array of `ErrorType`s.
    */
    func operationQueue(_ queue: ProcedureQueue, willFinishOperation operation: Operation, withErrors errors: [Error])

    /**
     An operation has finished on the queue.

     - parameter queue: the `ProcedureQueue`.
     - parameter operation: the `NSOperation` instance which finished.
     - parameter errors: an array of `ErrorType`s.
     */
    func operationQueue(_ queue: ProcedureQueue, didFinishOperation operation: Operation, withErrors errors: [Error])

    /**
     The operation queue will add a new operation via produceOperation().
     This is for information only, the delegate cannot affect whether the operation
     is added, or other control flow.

     - paramter queue: the `ProcedureQueue`.
     - paramter operation: the `NSOperation` instance about to be added.
     */
    func operationQueue(_ queue: ProcedureQueue, willProduceOperation operation: Operation)
}

/**
An `NSOperationQueue` subclass which supports the features of Operations. All functionality
is achieved via the overridden functionality of `addOperation`.
*/
public class ProcedureQueue: OperationQueue {

    #if swift(>=3.0)
        // (SR-192 is fixed in Swift 3)
    #else
    deinit {
        // Swift < 3 FIX:
        // (SR-192): Weak properties are not thread safe when reading
        // https://bugs.swift.org/browse/SR-192
        //
        // Cannot surround native deinitialization of _delegate with a lock,
        // so avoid the issue by setting it to nil here.
        delegate = nil
    }
    #endif

    /**
    The queue's delegate, helpful for reporting activity.

    - parameter delegate: a weak `OperationQueueDelegate?`
    */
    #if swift(>=3.0)
    public weak var delegate: OperationQueueDelegate? = .none
    #else
    // Swift < 3 FIX:
    // (SR-192): Weak properties are not thread safe when reading
    // https://bugs.swift.org/browse/SR-192
    //
    // Surround access of delegate with a lock to avoid the issue.
    public weak var delegate: OperationQueueDelegate? {
        get {
            return delegateLock.withCriticalScope { _delegate }
        }
        set (newDelegate) {
            delegateLock.withCriticalScope {
                _delegate = newDelegate
            }
        }
    }
    private weak var _delegate: OperationQueueDelegate? = .none
    private let delegateLock = Foundation.Lock()
    #endif

    /**
    Adds the operation to the queue. Subclasses which override this method must call this
    implementation as it is critical to how Operations function.

    - parameter op: an `NSOperation` instance.
    */
    // swiftlint:disable function_body_length
    public override func addOperation(_ operation: Operation) {
        if let operation = operation as? Procedure {

            /// Add an observer so that any produced operations are added to the queue
            operation.addObserver(ProducedOperationObserver { [weak self] op, produced in
                if let q = self {
                    q.delegate?.operationQueue(q, willProduceOperation: produced)
                    q.addOperation(produced)
                }
            })

            /// Add an observer to invoke the will finish delegate method
            operation.addObserver(WillFinishObserver { [weak self] operation, errors in
                if let q = self {
                    q.delegate?.operationQueue(q, willFinishOperation: operation, withErrors: errors)
                }
            })

            /// Add an observer to invoke the did finish delegate method
            operation.addObserver(DidFinishObserver { [weak self] operation, errors in
                if let q = self {
                    q.delegate?.operationQueue(q, didFinishOperation: operation, withErrors: errors)
                }
            })

            /// Process any conditions
            if operation.conditions.count > 0 {

                /// Check for mutual exclusion conditions
                let manager = ExclusivityManager.sharedInstance
                let mutuallyExclusiveConditions = operation.conditions.filter { $0.mutuallyExclusive }
                var previousMutuallyExclusiveOperations = Set<Operation>()
                for condition in mutuallyExclusiveConditions {
                    let category = "\(condition.category)"
                    if let previous = manager.addOperation(operation, category: category) {
                        previousMutuallyExclusiveOperations.insert(previous)
                    }
                }

                // Create the condition evaluator
                let evaluator = operation.evaluateConditions()

                // Get the condition dependencies
                let indirectDependencies = operation.indirectDependencies

                // If there are dependencies
                if indirectDependencies.count > 0 {

                    // Iterate through the indirect dependencies
                    indirectDependencies.forEach {

                        // Indirect dependencies are executed after
                        // any previous mutually exclusive operation(s)
                        $0.addDependencies(previousMutuallyExclusiveOperations)

                        // Indirect dependencies are executed after
                        // all direct dependencies
                        $0.addDependencies(operation.directDependencies)

                        // Only evaluate conditions after all indirect
                        // dependencies have finished
                        evaluator.addDependency($0)
                    }

                    // Add indirect dependencies
                    addOperations(indirectDependencies)
                }

                // Add the evaluator
                addOperation(evaluator)
            }

            // Indicate to the operation that it is to be enqueued
            operation.willEnqueue()
        }
        else {
            operation.addCompletionBlock { [weak self, weak operation] in
                if let queue = self, let op = operation {
                    queue.delegate?.operationQueue(queue, didFinishOperation: op, withErrors: [])
                }
            }
        }
        // swiftlint:enable function_body_length

        delegate?.operationQueue(self, willAddOperation: operation)

        super.addOperation(operation)
    }

    /**
    Adds the operations to the queue.

    - parameter ops: an array of `NSOperation` instances.
    - parameter wait: a Bool flag which is ignored.
    */
    public override func addOperations(_ ops: [Operation], waitUntilFinished wait: Bool) {
        ops.forEach(addOperation)
    }
}


public extension OperationQueue {

    /**
     Add operations to the queue as an array
     - parameters ops: a array of `NSOperation` instances.
     */
    func addOperations<S where S: Sequence, S.Iterator.Element: Operation>(_ ops: S) {
        addOperations(Array(ops), waitUntilFinished: false)
    }

    /**
     Add operations to the queue as a variadic parameter
     - parameters ops: a variadic array of `NSOperation` instances.
    */
    func addOperations(_ ops: Operation...) {
        addOperations(ops)
    }
}


public extension ProcedureQueue {

    private static let sharedMainQueue = MainQueue()

    /**
     Override NSOperationQueue's mainQueue() to return the main queue as an ProcedureQueue

     - returns: The main queue
     */
    public override class var main: ProcedureQueue { return sharedMainQueue }
//
//    public override class func mainQueue() -> ProcedureQueue {
//        return sharedMainQueue
//    }
}

/// ProcedureQueue wrapper around the main queue
private class MainQueue: ProcedureQueue {
    override init() {
        super.init()
        underlyingQueue = DispatchQueue.main
        maxConcurrentOperationCount = 1
    }
}
