//
//  RetryOperation.swift
//  Operations
//
//  Created by Daniel Thorpe on 29/12/2015.
//
//

import Foundation

/// A type which has an associated error type
public protocol AssociatedErrorType {

    /// The type of associated error
    associatedtype Error: Swift.Error
}

/**
 RetryFailureInfo is a value type which provides
 information related to a previously failed
 NSOperation which it is generic over. It is used
 in conjunction with RetryOperation.
*/
public struct RetryFailureInfo<T: Operation> {

    /// - returns: the failed operation
    public let operation: T

    /// - returns: the errors the operation finished with.
    public let errors: [Error]

    /// - returns: the previous errors of previous attempts
    public let historicalErrors: [Error]

    /// - returns: the number of attempts made so far
    public let count: Int

    /**
     This is a block which can be used to add operations
     to a queue. For example, perhaps it is necessary
     to retry the task, but only until another operation
     has completed. This can be done by creating the
     operation, setting the dependency and adding it using
     this block, before responding to the RetryOperation.

     - returns: a block which accects var arg NSOperation instances.
    */
    public let addOperations: (Operation...) -> Void

    /// - returns: the `RetryOperation`'s log property.
    public let log: LoggerType

    /**
    - returns: the block which is used to configure
        operation instances before they are added to
        the queue
    */
    public let configure: (T) -> Void
}

class RetryGenerator<T: Operation>: IteratorProtocol {
    typealias Payload = RetryOperation<T>.Payload
    typealias Handler = RetryOperation<T>.Handler

    internal let retry: Handler
    internal var info: RetryFailureInfo<T>? = .none
    fileprivate var generator: AnyIterator<Payload>

    init(generator: AnyIterator<Payload>, retry: Handler) {
        self.generator = generator
        self.retry = retry
    }

    func next() -> Payload? {
        guard let payload = generator.next() else { return nil }
        guard let info = info else { return payload }
        return retry(info, payload)
    }
}

/**
 RetryOperation is a subclass of RepeatedOperation. Like RepeatedOperation
 it is generic over type T, an NSOperation subclass. It can be used to
 automatically retry another instance of operation T if the first operation
 finishes with errors.

 To support effective error recovery, in addition to a (Delay?, T) generator
 RetryOperation is initialized with a block. The block will receive failure
 info, in addition to the next result (if not nil) of the operation generator.
 The block must return (Delay?, T)?.

 Therefore consumers can inspect the failure info, and adjust the Delay, or
 operation before returning it. To finish, the block can return .none
*/
public class RetryOperation<T: Operation>: RepeatedOperation<T> {
    public typealias FailureInfo = RetryFailureInfo<T>
    public typealias Handler = (RetryFailureInfo<T>, Payload) -> Payload?

    let retry: RetryGenerator<T>

    /**
     A designated initializer

     Creates an operation which will retry executing operations in the face
     of errors.

     - parameter maxCount: an optional Int, which defaults to .none. If not nil, this is
     the maximum number of operations which will be executed.
     - parameter generator: the generator of (Delay?, T) values.
     - parameter retry: a Handler block type, can be used to inspect aggregated error to
     adjust the next delay and Procedure.

    */
    public init(maxCount max: Int? = .none, generator: AnyIterator<Payload>, retry block: Handler) {
        retry = RetryGenerator(generator: generator, retry: block)
        super.init(maxCount: max, generator: AnyIterator(retry))
        name = "Retry Procedure <\(T.self)>"
    }

    /**
     A designated initializer, which accepts two generators, one for the delay and another for
     the operation, in addition to a retry handler block

     - parameter maxCount: an optional Int, which defaults to .none. If not nil, this is
     the maximum number of operations which will be executed.
     - parameter delay: a generator with Delay element.
     - parameter generator: a generator with T element.
     - parameter retry: a Handler block type, can be used to inspect aggregated error to
     adjust the next delay and Procedure.

     */
    public init<D, G>(maxCount max: Int? = .none, delay: D, generator: G, retry block: Handler) where D: IteratorProtocol, D.Element == Delay, G: IteratorProtocol, G.Element == T {
        let tuple = TupleGenerator(primary: generator, secondary: delay)
        let mapped = MapGenerator(tuple) { RepeatedPayload(delay: $0.0, operation: $0.1, configure: .none) }
        retry = RetryGenerator(generator: AnyIterator(mapped), retry: block)
        super.init(maxCount: max, generator: AnyIterator(retry))
        name = "Retry Procedure <\(T.self)>"
    }

    /**
     An initializer with wait strategy and generic operation generator.
     This is useful where another system can be responsible for vending instances of
     the custom operation. Typically there may be some state involved in such a Generator. e.g.

     The wait strategy is useful if say, you want to repeat the operations with random
     delays, or exponential backoff. These standard schemes and be easily expressed.

     ```swift
     class MyOperationGenerator: GeneratorType {
         func next() -> MyOperation? {
              // etc
         }
     }

     let operation = RetryOperation(
         maxCount: 3,
         strategy: .Random((0.1, 1.0)),
         generator: MyOperationGenerator()
     ) { info, delay, op in
         // inspect failure info
         return (delay, op)
     }
     ```

     - parameter maxCount: an optional Int, which defaults to 5.
     - parameter strategy: a WaitStrategy which defaults to a 0.1 second fixed interval.
     - parameter [unnamed] generator: a generic generator which has an Element equal to T.
     - parameter retry: a Handler block type, can be used to inspect aggregated error to
     adjust the next delay and Procedure. This defaults to pass through the delay and
     operation regardless of error info.

     */
    public init<G>(maxCount max: Int? = 5, strategy: WaitStrategy = .fixed(0.1), _ generator: G, retry block: Handler = { $1 }) where G: IteratorProtocol, G.Element == T {
        let delay = MapGenerator(strategy.generator()) { Delay.by($0) }
        let tuple = TupleGenerator(primary: generator, secondary: delay)
        let mapped = MapGenerator(tuple) { RepeatedPayload(delay: $0.0, operation: $0.1, configure: .none) }
        retry = RetryGenerator(generator: AnyIterator(mapped), retry: block)
        super.init(maxCount: max, generator: AnyIterator(retry))
        name = "Retry Procedure <\(T.self)>"
    }

    /**
     Sets up the retry info object (used by the RetryGenerator), then
     calls the super implementation, returning true.
     */
    public override func willAttemptRecoveryFromErrors(_ errors: [Error], inOperation operation: Operation) -> Bool {
        var returnValue = false
        defer {
            let message = returnValue ? "will attempt" : "will not attempt"
            log.verbose("\(message) \(count) recovery from errors: \(errors) in operation: \(operation)")
        }

        guard let op = operation as? T, operation === current else { return returnValue }
        retry.info = createFailureInfo(op, errors: errors)
        returnValue = addNextOperation()
        return returnValue
    }

    /**
     RetryOperation suppress any retries when the target operation succeeded.
     */
    public override func willFinishOperation(_ operation: Operation) {
        // no-op
    }

    internal func createFailureInfo(_ operation: T, errors: [Error]) -> RetryFailureInfo<T> {
        return RetryFailureInfo(
            operation: operation,
            errors: errors,
            historicalErrors: internalErrors.previousAttempts,
            count: count,
            addOperations: addOperations,
            log: log,
            configure: configure
        )
    }

    internal override func child(_ child: Operation, didAttemptRecoveryFromErrors errors: [Error]) {
        if let previous = previous, child === current {
            didNotRecoverFromOperationErrors(previous)
        }
        super.child(child, didAttemptRecoveryFromErrors: errors)
    }

    public override func operationQueue(_ queue: ProcedureQueue, willFinishOperation operation: Operation, withErrors errors: [Error]) {
        if errors.isEmpty, let previous = previous, operation === current {
            didRecoverFromOperationErrors(previous)
        }
        super.operationQueue(queue, willFinishOperation: operation, withErrors: errors)
    }
}
