//
//  NegatedConditionTests.swift
//  Operations
//
//  Created by Daniel Thorpe on 20/07/2015.
//  Copyright © 2015 Daniel Thorpe. All rights reserved.
//

import XCTest
@testable import Operations

class NegatedConditionTests: OperationTests {

    func test__operation_with_successful_block_condition_fails() {
        let expectation = self.expectation(description: "Test: \(#function)")
        let operation = TestOperation()
        operation.addCondition(NegatedCondition(TrueCondition()))

        var receivedErrors = [Error]()
        operation.addObserver(DidFinishObserver { _, errors in
            receivedErrors = errors
            expectation.fulfill()
        })

        runOperation(operation)

        waitForExpectations(timeout: 3, handler: nil)
        XCTAssertFalse(operation.didExecute)
        XCTAssertEqual(receivedErrors.count, 1)
        if let error = receivedErrors.first as? NegatedConditionError {
            XCTAssertTrue(error == .conditionSatisfied("True Condition"))
        }
        else {
            XCTFail("No error message was observed")
        }
    }

    func test__operation_with_unsuccessful_block_condition_executes() {

        let operation = TestOperation()
        operation.addCondition(NegatedCondition(FalseCondition()))

        addCompletionBlockToTestOperation(operation)
        runOperation(operation)
        waitForExpectations(timeout: 3, handler: nil)

        XCTAssertTrue(operation.didExecute)
        XCTAssertTrue(operation.isFinished)
        XCTAssertFalse(operation.isCancelled)
    }

    func test__negated_condition_name() {
        let condition = NegatedCondition(NoFailedDependenciesCondition())
        XCTAssertEqual(condition.name, "Not<No Cancelled Condition>")
    }

    func test__negated_condition_is_mutually_exclusive_when_nested_condition_is_mutually_exclusive() {
        let condition = NegatedCondition(MutuallyExclusive<String>())
        XCTAssertTrue(condition.mutuallyExclusive)
    }

    func test__negated_condition_is_not_mutually_exclusive_when_nested_condition_is_not_mutually_exclusive() {
        let condition = NegatedCondition(NoFailedDependenciesCondition())
        XCTAssertFalse(condition.mutuallyExclusive)
    }

}
