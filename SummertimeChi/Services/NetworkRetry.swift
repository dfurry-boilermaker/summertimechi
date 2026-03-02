import Foundation

// MARK: - Exponential Back-off Retry

/// Retries `operation` up to `maxAttempts` times using exponential back-off.
///
/// - Back-off schedule: `initialDelay * 2^attempt` (1 s, 2 s, 4 s with defaults).
/// - `CancellationError` is never retried — it propagates immediately.
/// - Cap: individual delay capped at 30 s.
func withRetry<T>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 1.0,
    operation: @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?
    for attempt in 0..<maxAttempts {
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastError = error
            if attempt < maxAttempts - 1 {
                let delay = min(initialDelay * pow(2.0, Double(attempt)), 30.0)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    throw lastError!
}

// MARK: - In-Flight Request Deduplicator

/// Deduplicates concurrent async requests with the same key.
///
/// When two callers ask for the same key at the same time, only one network
/// request is issued. Both callers await the single in-flight task and receive
/// the same result (or error).
actor InFlightDeduplicator<Key: Hashable, Value> {
    private var inFlight: [Key: Task<Value, Error>] = [:]

    /// Returns a cached in-flight result or runs `work` exactly once for `key`.
    func deduplicate(key: Key, work: @escaping () async throws -> Value) async throws -> Value {
        if let existing = inFlight[key] {
            return try await existing.value
        }
        let task = Task { try await work() }
        inFlight[key] = task
        do {
            let result = try await task.value
            inFlight.removeValue(forKey: key)
            return result
        } catch {
            inFlight.removeValue(forKey: key)
            throw error
        }
    }
}
