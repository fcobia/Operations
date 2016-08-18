//
//  WebpageOperation.swift
//  Operations
//
//  Created by Daniel Thorpe on 21/07/2015.
//  Copyright © 2015 Daniel Thorpe. All rights reserved.
//

import Foundation
import SafariServices


/**
 An operation that presents an instance of the `SFSafariViewController` on a presenting view controller.
 */
@available(iOS 9.0, *)
public class WebpageOperation<From: PresentingViewController>: ComposedOperation<UIOperation<SFSafariViewController, From>>, SFSafariViewControllerDelegate {

    /**
     Composes an operation that presents an instance of the `SFSafariViewController` on a presenting view controller.

     - parameter url: the `URL` that will be opend by `SFSafariViewController`.
     - parameter displayControllerFrom: a `ViewControllerDisplayStyle`.
     - parameter entersReaderIfAvailable: an optional flag that tells the `SFSafariViewController` to open the webpage in a reader mode if available.
     - parameter sender: an `AnyObject` sender.
     */
    public convenience init(url: URL, displayControllerFrom from: ViewControllerDisplayStyle<From>, entersReaderIfAvailable: Bool = true, sender: AnyObject? = .none) {
        let operation = UIOperation(controller: SFSafariViewController(url: url, entersReaderIfAvailable: entersReaderIfAvailable), displayControllerFrom: from, sender: sender)
        self.init(operation: operation)

        addObserver(WillExecuteObserver { [weak self] _ in
            self?.operation.controller.delegate = self
        })

        addCondition(MutuallyExclusive<UIViewController>())
    }

    // Annotated to be fileprivate so a consumer needs to call init(_:, displayControllerFrom:) because a URL is needed.
    override fileprivate init(operation composed: UIOperation<SFSafariViewController, From>) {
        super.init(operation: composed)
    }

    @objc public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true) {
            self.finish()
        }
    }
}
