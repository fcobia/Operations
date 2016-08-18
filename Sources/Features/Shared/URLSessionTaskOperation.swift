//
//  URLSessionTaskOperation.swift
//  Operations
//
//  Created by Daniel Thorpe on 01/10/2015.
//  Copyright © 2015 Dan Thorpe. All rights reserved.
//

import Foundation


/**
An Procedure which is a simple wrapper around `NSURLSessionTask`.

Note that the task will still need to be configured with a delegate
as usual. Typically this operation would be used after the task is
setup, so that conditions or observers can be attached.

*/
public class URLSessionTaskOperation: Procedure {

    enum KeyPath: String {
        case State = "state"
    }

    public let task: URLSessionTask

    fileprivate var removedObserved = false
    fileprivate let lock = Foundation.NSLock()

    public init(task: URLSessionTask) {
        assert(task.state == .suspended, "NSURLSessionTask must be suspended, not \(task.state)")
        self.task = task
        super.init()
        addObserver(DidCancelObserver { _ in
            task.cancel()
        })
    }

    public override func execute() {
        assert(task.state == .suspended, "NSURLSessionTask resumed outside of \(self)")
        task.addObserver(self, forKeyPath: KeyPath.State.rawValue, options: [], context: &URLSessionTaskOperationKVOContext)
        task.resume()
    }

    public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [String : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &URLSessionTaskOperationKVOContext else { return }

        lock.withCriticalScope {
            if let objectTask = object as? URLSessionTask, objectTask === task && keyPath == KeyPath.State.rawValue && !removedObserved {

                if case .completed = task.state {
                    finish(task.error)
                }

                switch task.state {
                case .completed, .canceling:
                    task.removeObserver(self, forKeyPath: KeyPath.State.rawValue)
                    removedObserved = true
                default:
                    break
                }
            }
        }
    }
}

// swiftlint:disable variable_name
fileprivate var URLSessionTaskOperationKVOContext = 0
// swiftlint:enable variable_name
