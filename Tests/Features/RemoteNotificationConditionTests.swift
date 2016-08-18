//
//  UserNotificationConditionTests.swift
//  Operations
//
//  Created by Daniel Thorpe on 20/07/2015.
//  Copyright © 2015 Daniel Thorpe. All rights reserved.
//

import XCTest
@testable import Operations

class TestableRemoteNotificationRegistrar: RemoteNotificationRegistrarType {

    var didRegister = false
    let error: Error?

    init(error: Error? = .none) {
        self.error = error
    }

    func opr_registerForRemoteNotifications() {
        didRegister = true
        if let error = error {
            RemoteNotificationCondition.didFailToRegisterForRemoteNotifications(error)
        }
        else {
            let data = "I'm a token!".data(using: String.Encoding.utf8, allowLossyConversion: true)
            RemoteNotificationCondition.didReceiveNotificationToken(data!)
        }
    }
}


class RemoteNotificationConditionTests: OperationTests {

    var registrar: TestableRemoteNotificationRegistrar!
    var condition: RemoteNotificationCondition!

    override func setUp() {
        super.setUp()
        registrar = TestableRemoteNotificationRegistrar()
        condition = RemoteNotificationCondition()
        condition.registrar = registrar
    }

    override func tearDown() {
        registrar = nil
        condition = nil
        super.tearDown()
    }

    func test__condition_succeeds__when_registration_succeeds() {
        let operation = TestOperation()
        operation.addCondition(condition)
        waitForOperation(operation)
        XCTAssertTrue(operation.didExecute)
    }

    func test__condition_fails__when_registration_fails() {
        registrar = TestableRemoteNotificationRegistrar(error: Error(domain: "me.danthorpe.Operations", code: -10_001, userInfo: nil))
        condition.registrar = registrar

        let operation = TestOperation()
        operation.addCondition(condition)

        let expectation = self.expectation(description: "Test: \(#function)")
        var receivedErrors = [ErrorProtocol]()
        operation.addObserver(DidFinishObserver { _, errors in
            receivedErrors = errors
            expectation.fulfill()
        })

        runOperation(operation)
        waitForExpectations(timeout: 3, handler: nil)

        XCTAssertFalse(operation.didExecute)
        if let error = receivedErrors.first as? RemoteNotificationCondition.Error {
            switch error {
            case .receivedError(_):
                break // expected.
            }
        }
        else {
            XCTFail("No error message was observed")
        }
    }
}
