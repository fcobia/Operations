//
//  UserConfirmationCondition.swift
//  Operations
//
//  Created by Daniel Thorpe on 05/08/2015.
//  Copyright (c) 2015 Daniel Thorpe. All rights reserved.
//

import UIKit

enum UserConfirmationResult {
    case unknown
    case confirmed
    case cancelled
}

enum UserConfirmationError: Error {
    case confirmationUnknown
    case confirmationCancelled
}

/**
    Attach this condition to an operation to present an alert
    to the user requesting their confirmation before proceeding.
*/
public class UserConfirmationCondition<From: PresentingViewController>: Condition {

    fileprivate let action: String
    fileprivate let isDestructive: Bool
    fileprivate let cancelAction: String
    fileprivate var alert: AlertOperation<From>
    fileprivate var confirmation: UserConfirmationResult = .unknown
    fileprivate var alertOperationErrors = [Error]()

    public init(title: String, message: String? = .none, action: String, isDestructive: Bool = true, cancelAction: String = NSLocalizedString("Cancel", comment: "Cancel"), presentConfirmationFrom from: From) {
        self.action = action
        self.isDestructive = isDestructive
        self.cancelAction = cancelAction
        self.alert = AlertOperation(presentAlertFrom: from)
        super.init()
        name = "UserConfirmationCondition(\(title))"

        alert.title = title
        alert.message = message
        alert.addActionWithTitle(action, style: isDestructive ? .destructive : .default) { [weak self] _ in
            self?.confirmation = .confirmed
        }
        alert.addActionWithTitle(cancelAction, style: .cancel) { [weak self] _ in
            self?.confirmation = .cancelled
        }
        alert.addObserver(WillFinishObserver { [weak self] _, errors in
            self?.alertOperationErrors = errors
        })
        addDependency(alert)
    }

    public override func evaluate(_ operation: Procedure, completion: @escaping (OperationConditionResult) -> Void) {
        switch confirmation {
        case .unknown:
            // This should never happen, but you never know.
            completion(.failed(UserConfirmationError.confirmationUnknown))
        case .cancelled:
            completion(.failed(UserConfirmationError.confirmationCancelled))
        case .confirmed:
            completion(.satisfied)
        }
    }
}
