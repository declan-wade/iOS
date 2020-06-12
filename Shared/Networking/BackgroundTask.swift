import Foundation
import PromiseKit
#if os(iOS)
import UIKit
#endif

public enum BackgroundTaskError: Error {
    case outOfTime
}

// enum for namespacing
public enum HomeAssistantBackgroundTask {
    public static func execute<ReturnType, IdentifierType>(
        withName name: String,
        beginBackgroundTask: @escaping (String, @escaping () -> Void) -> IdentifierType?,
        endBackgroundTask: @escaping (IdentifierType) -> Void,
        wrapping: () -> Promise<ReturnType>
    ) -> Promise<ReturnType> {
        func describe(_ identifier: IdentifierType?) -> String {
            if let identifier = identifier {
                #if os(iOS)
                if let identifier = identifier as? UIBackgroundTaskIdentifier {
                    return String(describing: identifier.rawValue)
                } else {
                    return String(describing: identifier)
                }
                #else
                    return String(describing: identifier)
                #endif
            } else {
                return "(none)"
            }
        }

        var identifier: IdentifierType?

        // we can't guarantee to Swift that this will be assigned, but it will
        var finished: () -> Void = {}

        let promise = Promise<Void> { seal in
            identifier = beginBackgroundTask(name) {
                seal.reject(BackgroundTaskError.outOfTime)
            }

            Current.Log.info("started background task \(name) (\(describe(identifier)))")

            finished = {
                seal.fulfill(())
            }
        }.tap { result in
            guard let endableIdentifier = identifier else { return }

            let endBackgroundTask = {
                Current.Log.info("ending background task \(name) (\(describe(endableIdentifier)))")
                endBackgroundTask(endableIdentifier)
                identifier = nil
            }

            if case .rejected(BackgroundTaskError.outOfTime) = result {
                // immediately execute, or we'll be terminated by the system!
                endBackgroundTask()
            } else {
                // give it a run loop, since we want the promise's e.g. completion handlers to be invoked first
                DispatchQueue.main.async { endBackgroundTask() }
            }
        }

        // make sure we only invoke the promise-returning block once, in case it has side-effects
        let underlying = wrapping()

        let underlyingWithFinished = underlying
            .ensure { finished() }

        return firstly {
            when(fulfilled: [promise.asVoid(), underlyingWithFinished.asVoid()])
        }.then {
            underlying
        }
    }
}