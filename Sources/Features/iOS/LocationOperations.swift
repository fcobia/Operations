//
//  LocationOperations.swift
//  Operations
//
//  Created by Daniel Thorpe on 27/07/2015.
//  Copyright (c) 2015 Daniel Thorpe. All rights reserved.
//

import Foundation
import CoreLocation

// MARK: Consumer Interfaces -

@available(*, unavailable, renamed: "UserLocationOperation")
public typealias LocationOperation = UserLocationOperation

// MARK: - Implementation Details -

public protocol LocationManagerType: LocationCapabilityRegistrarType {
    func opr_setDesiredAccuracy(_ desiredAccuracy: CLLocationAccuracy)
    func opr_startUpdatingLocation()
    func opr_stopLocationUpdates()
}

extension CLLocationManager: LocationManagerType {

    public func opr_setDesiredAccuracy(_ accuracy: CLLocationAccuracy) {
        desiredAccuracy = accuracy
    }

    public func opr_startUpdatingLocation() {
        startUpdatingLocation()
    }

    public func opr_stopLocationUpdates() {
        stopUpdatingLocation()
    }
}

internal extension CLLocationManager {

    static func create() -> CLLocationManager {
        return dispatch_main_sync { CLLocationManager() }
    }
}

public enum LocationOperationError: Error, Equatable {
    case locationManagerDidFail(Error)
    case geocoderError(Error)
}

// MARK: - UserLocationOperation

public class UserLocationOperation: Procedure, CLLocationManagerDelegate, ResultOperationType {
    public typealias CompletionBlockType = (CLLocation) -> Void

    fileprivate let accuracy: CLLocationAccuracy
    fileprivate let completion: CompletionBlockType

    internal var capability: LocationCapability

    internal lazy var locationManager: LocationManagerType = CLLocationManager.create()

    internal var manager: LocationManagerType {
        get { return locationManager }
        set {
            locationManager = newValue
            capability.registrar = newValue
        }
    }

    /// - returns: the CLLocation if available
    public fileprivate(set) var location: CLLocation? = .none

    /// - returns: the CLLocation if available
    public var result: CLLocation? {
        return location
    }

    /**
     Initialize an operation which will determine the user's current location
     to the desired accuracy. It will ask for permission if required.

     - parameter accuracy: the location accuracy which defaults to 3km.
     - parameter completion: a closure CLLocation -> Void.
    */
    public init(accuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers, completion: CompletionBlockType = { _ in }) {
        self.accuracy = accuracy
        self.completion = completion
        self.capability = Capability.Location(.whenInUse)
        super.init()
        name = "User Location"
        capability.registrar = manager
        addCondition(AuthorizedFor(capability))
        addCondition(MutuallyExclusive<CLLocationManager>())
        addObserver(DidCancelObserver { [weak self] _ in
            Queue.main.queue.async {
                self?.stopLocationUpdates()
            }
        })
    }

    deinit {
        stopLocationUpdates()
    }

    /// Starts updating the location
    public override func execute() {
        manager.opr_setDesiredAccuracy(accuracy)
        manager.opr_setDelegate(self)
        manager.opr_startUpdatingLocation()
    }

    internal func stopLocationUpdates() {
        manager.opr_stopLocationUpdates()
        manager.opr_setDelegate(nil)
    }

    @objc public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if !isFinished, let location = locations.last {
            log.info("Updated last location: \(location)")
            if location.horizontalAccuracy <= accuracy {
                Queue.main.queue.async { [weak self] in
                    if let weakSelf = self {
                        if !weakSelf.isFinished {
                            weakSelf.stopLocationUpdates()
                            weakSelf.location = location
                            weakSelf.completion(location)
                            weakSelf.finish()
                        }
                    }
                }
            }
        }
    }

    @objc public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Queue.main.queue.async { [weak self] in
            if let weakSelf = self {
                weakSelf.stopLocationUpdates()
                weakSelf.finish(LocationOperationError.locationManagerDidFail(error))
            }
        }
    }
}

// MARK: - ReverseGeocodeOperation

public protocol ReverseGeocoderType {
    func opr_cancel()
    func opr_reverseGeocodeLocation(_ location: CLLocation, completion: @escaping ([CLPlacemark], Error?) -> Void)
}

extension CLGeocoder: ReverseGeocoderType {

    public func opr_cancel() {
        cancelGeocode()
    }

    public func opr_reverseGeocodeLocation(_ location: CLLocation, completion: @escaping ([CLPlacemark], Error?) -> Void) {
        reverseGeocodeLocation(location) { (results, error) in
            completion(results ?? [], error)
        }
    }
}

internal extension CLGeocoder {

    static func create() -> CLGeocoder {
        return dispatch_main_sync { CLGeocoder() }
    }
}

public class ReverseGeocodeOperation: Procedure, ResultOperationType {

    public typealias CompletionBlockType = (CLPlacemark) -> Void

    public let location: CLLocation

    internal lazy var geocoder: ReverseGeocoderType = CLGeocoder.create()

    fileprivate let completion: CompletionBlockType

    /// - returns: the CLPlacemark from the geocoder
    public fileprivate(set) var placemark: CLPlacemark? = .none

    /// - returns: the CLPlacemark from the geocoder
    public var result: CLPlacemark? {
        return placemark
    }

    /**
    Initialize an operation which will use a custom geocoder to
    reverse lookup the given location.

    - parameter location: the location to reverse lookup.
    - parameter completion: a completion block of CompletionBlockType
    */
    public init(location: CLLocation, completion: CompletionBlockType = { _ in }) {
        self.location = location
        self.completion = completion
        super.init()
        name = "Reverse Geocode"
        addObserver(NetworkObserver())
        addObserver(BackgroundObserver())
        addCondition(MutuallyExclusive<ReverseGeocodeOperation>())
        addObserver(DidCancelObserver { [weak self] _ in
            if let geocoder = self?.geocoder {
                Queue.main.queue.async {
                    geocoder.opr_cancel()
                }
            }
        })
    }

    public override func execute() {
        geocoder.opr_reverseGeocodeLocation(location) { results, error in
            Queue.main.queue.async { [weak self] in
                guard let weakSelf = self, !weakSelf.isFinished else { return }

                if let error = error {
                    weakSelf.finish(LocationOperationError.geocoderError(error))
                }
                else if let placemark = results.first {
                    weakSelf.placemark = placemark
                    weakSelf.completion(placemark)
                    weakSelf.finish()
                }
            }
        }
    }
}

// MARK: - ReverseGeocodeUserLocationOperation

public class ReverseGeocodeUserLocationOperation: GroupOperation, ResultOperationType {
    public typealias CompletionBlockType = (CLLocation, CLPlacemark) -> Void

    fileprivate let completion: CompletionBlockType

    internal let userLocationOperation: UserLocationOperation
    internal var reverseGeocodeOperation: ReverseGeocodeOperation?
    internal var geocoder: ReverseGeocoderType? = .none

    /// - returns: the CLLocation if available
    public var location: CLLocation? {
        return userLocationOperation.location
    }

    /// - returns: the CLPlacemark from the geocoder
    public var placemark: CLPlacemark? {
        return reverseGeocodeOperation?.placemark
    }

    /// - returns: the CLPlacemark from the geocoder, note that CLPlacemark
    /// composes the associated CLLocation.
    public var result: CLPlacemark? {
        return placemark
    }

    /**
    Initialize a group operation which will use a custom geocoder to
    reverse lookup the device location (using a custom location manager).

    - parameter accuracy: the location accuracy.
    - parameter completion: a completion block of CompletionBlockType
    */
    public init(accuracy: CLLocationAccuracy = kCLLocationAccuracyThreeKilometers, completion: CompletionBlockType = { _, _ in }) {
        self.completion = completion
        self.userLocationOperation = UserLocationOperation(accuracy: accuracy, completion: { _ in })
        super.init(operations: [ userLocationOperation ])
        name = "Reverse Geocode User Location"
        addCondition(MutuallyExclusive<ReverseGeocodeUserLocationOperation>())
    }

    public override func willFinishOperation(_ operation: Operation) {
        guard userLocationOperation == operation && !operation.isCancelled, let location = location else { return }

        let reverseOp = ReverseGeocodeOperation(location: location) { [unowned self] placemark in
            self.completion(location, placemark)
        }

        if let geocoder = geocoder {
            reverseOp.geocoder = geocoder
        }

        addOperation(reverseOp)
        reverseGeocodeOperation = reverseOp
    }
}

public func == (lhs: LocationOperationError, rhs: LocationOperationError) -> Bool {
    switch (lhs, rhs) {
    case let (.locationManagerDidFail(aError), .locationManagerDidFail(bError)):
        return aError as NSError == bError as NSError
    case let (.geocoderError(aError), .geocoderError(bError)):
        return aError as NSError == bError as NSError
    default:
        return false
    }
}
