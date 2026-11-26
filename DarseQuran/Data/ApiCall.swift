import Foundation
import os

/// A failed API call, with a message ready to show to the user.
struct ApiError: Error, Sendable, Equatable {
    let message: String
    var status: Int? = nil
    var code: String? = nil
    /// The call was cancelled (the screen went away); nothing to show.
    var cancelled: Bool = false

    static let cancelledError = ApiError(message: "", cancelled: true)
}

/// The outcome of an API call (Android's ApiResult): `.success(value)` or `.failure(ApiError)`.
typealias ApiResult<T> = Result<T, ApiError>

extension Result where Failure == ApiError {
    /// The value, or nil on failure (Android's orNull()).
    var value: Success? { if case .success(let v) = self { v } else { nil } }
    var error: ApiError? { if case .failure(let e) = self { e } else { nil } }
    var isOk: Bool { if case .success = self { true } else { false } }
}

/// An HTTP answer outside 2xx.
struct HTTPError: Error, Sendable {
    let status: Int
    let body: Data
}

private let log = Logger(subsystem: "com.darsequran.academy", category: "ApiCall")

/// Runs [block], turning HTTP and network failures into an [ApiError] with the server's message.
func apiCall<T>(_ block: () async throws -> T) async -> ApiResult<T> {
    do {
        return .success(try await block())
    } catch {
        return .failure(apiError(from: error))
    }
}

func apiError(from error: Error) -> ApiError {
    switch error {
    case is CancellationError:
        return .cancelledError
    case let e as URLError where e.code == .cancelled:
        return .cancelledError
    case let e as HTTPError:
        let body = try? JSONDecoder().decode(ErrorBody.self, from: e.body)
        let message = body?.error ?? {
            switch e.status {
            case 401: return "Please sign in again."
            case 403: return "You don't have access to this."
            case 404: return "Not found."
            case 429: return "Too many attempts. Please wait a moment and try again."
            case 500...599: return "The academy's server had a problem. Please try again."
            default: return "Something went wrong (\(e.status))."
            }
        }()
        return ApiError(message: message, status: e.status, code: body?.code)
    case let e as DecodingError:
        // Usually a web page where JSON was expected: the server is older (or newer) than this app.
        #if DEBUG
        log.warning("Unexpected response: \(String(describing: e), privacy: .public)")
        #else
        log.warning("Unexpected response: DecodingError")
        #endif
        return ApiError(message: "The server's answer wasn't what this app expects. The server may not have this feature yet.")
    case is URLError:
        return ApiError(message: "No connection. Check your internet and try again.")
    case let e as ApiError:
        return e
    default:
        // The error's own description is for developers (it can name types or internals), so it goes to the log only.
        log.warning("Unexpected failure: \(String(describing: type(of: error)), privacy: .public)")
        return ApiError(message: "Something went wrong. Please try again.")
    }
}
