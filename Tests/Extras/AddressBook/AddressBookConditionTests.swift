//
//  AddressBookConditionTests.swift
//  Operations
//
//  Created by Daniel Thorpe on 20/07/2015.
//  Copyright © 2015 Daniel Thorpe. All rights reserved.
//

import XCTest
import AddressBook

@testable import Operations

@available(iOS, deprecated: 9.0)
class TestableAddressBookRegistrar: AddressBookPermissionRegistrar {

    var didAccessStatus = false
    var didCreateAddressBook = false
    var didRequestAccess = false
    var requestShouldSucceed = true

    var status: ABAuthorizationStatus

    var addressBook: CFTypeRef! = nil

    var creationError: CFError! = nil
    var accessError: CFError! = nil

    init(status: ABAuthorizationStatus) {
        self.status = status
    }

    func createAddressBook() -> (ABAddressBook?, AddressBookPermissionRegistrarError?) {
        didCreateAddressBook = true

        if let _ = creationError {
            return (.none, AddressBookPermissionRegistrarError.addressBookAccessDenied)
        }
        else if let addressBook: CFTypeRef = addressBook {
            return (addressBook as ABAddressBook, .none)
        }
        return (.none, AddressBookPermissionRegistrarError.addressBookUnknownErrorOccured)
    }

    func requestAccessToAddressBook(_ addressBook: ABAddressBook, completion: @escaping (AddressBookPermissionRegistrarError?) -> Void) {
        didRequestAccess = true
        if requestShouldSucceed {
            status = .authorized
            completion(nil)
        }
        else {
            status = .denied
            if let _ = accessError {
                completion(AddressBookPermissionRegistrarError.addressBookAccessDenied)
            }
            else {
                completion(AddressBookPermissionRegistrarError.addressBookUnknownErrorOccured)
            }
        }
    }
}

@available(iOS, deprecated: 9.0)
class AddressBookOperationTests: OperationTests {

    var registrar: TestableAddressBookRegistrar!

    override func setUp() {
        super.setUp()
        registrar = TestableAddressBookRegistrar(status: .authorized)
        let posedAddressBook = "I'm posing as an Address Book Ref!"
        registrar.addressBook = posedAddressBook as CFTypeRef
    }

    func test__given_authorization_granted__access_succeeds() {

        var didStart = false
        var didSucceed = false
        let operation = AddressBookOperation(registrar: registrar)
        operation.addObserver(BlockObserver(
            willExecute: { _ in
                didStart = true
            },
            didFinish: { (_, errors) in
                didSucceed = errors.isEmpty
            }
        ))

        addCompletionBlockToTestOperation(operation, withExpectation: expectation(description: "Test: \(#function)"))
        runOperation(operation)

        waitForExpectations(timeout: 3, handler: nil)

        XCTAssertTrue(didStart)
        XCTAssertTrue(registrar.didRequestAccess)
        XCTAssertTrue(didSucceed)
    }

    func test__given_authorization_denied__access_fails() {
        var didStart = false
        var didSucceed = false
        var receivedErrors = [Error]()

        registrar.status = .notDetermined
        registrar.requestShouldSucceed = false

        let operation = AddressBookOperation(registrar: registrar)
        operation.addObserver(BlockObserver(
            willExecute: { _ in
                didStart = true
            },
            didFinish: { (_, errors) in
                didSucceed = errors.isEmpty
                receivedErrors = errors
            }
        ))

        addCompletionBlockToTestOperation(operation, withExpectation: expectation(description: "Test: \(#function)"))
        runOperation(operation)

        waitForExpectations(timeout: 3, handler: nil)

        XCTAssertTrue(didStart)
        XCTAssertTrue(registrar.didRequestAccess)
        XCTAssertFalse(didSucceed)

        if let error = receivedErrors.first as? AddressBookPermissionRegistrarError {
            switch error {
            case .addressBookUnknownErrorOccured:
                break
            default:
                XCTFail("Incorrect AddressBookPermissionRegistrarError type received")
            }
        }
        else {
            XCTFail("Incorrect error type received")
        }
    }
}

@available(iOS, deprecated: 9.0)
class AddressBookConditionTests: OperationTests {

    var registrar: TestableAddressBookRegistrar!
    var condition: AddressBookCondition!

    override func setUp() {
        super.setUp()
        registrar = TestableAddressBookRegistrar(status: .notDetermined)
        let posedAddressBook = "I'm posing as an Address Book Ref!"
        registrar.addressBook = posedAddressBook as CFTypeRef
        registrar.requestShouldSucceed = true

        condition = AddressBookCondition()
        condition.registrar = registrar
    }

    func test__given_authorization_granted__condition_succeeds() {

        let operation = TestOperation()
        operation.addCondition(condition)

        addCompletionBlockToTestOperation(operation, withExpectation: expectation(description: "Test: \(#function)"))
        runOperation(operation)

        waitForExpectations(timeout: 3, handler: nil)
        XCTAssertTrue(registrar.didRequestAccess)
        XCTAssertTrue(operation.didExecute)
    }

    func test__given_authorization_denied__condition_fails() {
        registrar.requestShouldSucceed = false

        var receivedErrors = [Error]()

        let operation = TestOperation()
        operation.addCondition(condition)

        operation.addObserver(DidFinishObserver { _, errors in
            receivedErrors = errors
        })

        addCompletionBlockToTestOperation(operation, withExpectation: expectation(description: "Test: \(#function)"))
        runOperation(operation)

        waitForExpectations(timeout: 3, handler: nil)
        XCTAssertTrue(registrar.didRequestAccess)
        XCTAssertFalse(operation.didExecute)

        if let error = receivedErrors.first as? AddressBookCondition.Error {
            switch error {
            case .authorizationDenied:
                break
            default:
                XCTFail("Incorrect AddressBookCondition.Error type received")
            }
        }
        else {
            XCTFail("Incorrect error type received")
        }
    }

}
