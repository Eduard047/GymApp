import Foundation

enum BoundedURLSessionError: Error, Sendable {
    case invalidResponse
    case responseTooLarge(statusCode: Int?)
}

enum BoundedURLSessionLoader {
    typealias TaskCompletionObserver = @Sendable (URLSessionTask.State, Bool) -> Void

    static func data(
        for request: URLRequest,
        using sourceSession: URLSession,
        successLimit: Int,
        errorLimit: Int,
        taskCompletionObserver: TaskCompletionObserver? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        precondition(successLimit > 0 && errorLimit > 0, "Response limits must be positive.")
        guard let origin = HTTPSOrigin(url: request.url) else {
            throw BoundedURLSessionError.invalidResponse
        }

        let collector = BoundedURLSessionCollector(
            successLimit: successLimit,
            errorLimit: errorLimit,
            origin: origin,
            taskCompletionObserver: taskCompletionObserver
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                collector.start(
                    request: request,
                    configuration: sourceSession.configuration,
                    continuation: continuation
                )
            }
        } onCancel: {
            collector.cancel()
        }
    }
}

private struct HTTPSOrigin: Sendable {
    let host: String
    let port: Int

    init?(url: URL?) {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        let port = url.port ?? 443
        guard (1...65_535).contains(port) else { return nil }
        self.host = host
        self.port = port
    }

    func contains(_ url: URL?) -> Bool {
        guard let candidate = HTTPSOrigin(url: url) else { return false }
        return candidate.host == host && candidate.port == port
    }
}

private final class BoundedURLSessionCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Output = (Data, HTTPURLResponse)

    private let successLimit: Int
    private let errorLimit: Int
    private let origin: HTTPSOrigin
    private let taskCompletionObserver: BoundedURLSessionLoader.TaskCompletionObserver?
    private let lock = NSLock()

    private var continuation: CheckedContinuation<Output, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var responseLimit: Int?
    private var buffer = Data()
    private var cancellationRequested = false
    private var completed = false

    init(
        successLimit: Int,
        errorLimit: Int,
        origin: HTTPSOrigin,
        taskCompletionObserver: BoundedURLSessionLoader.TaskCompletionObserver?
    ) {
        self.successLimit = successLimit
        self.errorLimit = errorLimit
        self.origin = origin
        self.taskCompletionObserver = taskCompletionObserver
    }

    func start(
        request: URLRequest,
        configuration: URLSessionConfiguration,
        continuation: CheckedContinuation<Output, Error>
    ) {
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .userInitiated

        lock.lock()
        precondition(self.continuation == nil && task == nil, "A response collector is single-use.")
        self.continuation = continuation
        if cancellationRequested {
            completed = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }

        let childSession = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
        let dataTask = childSession.dataTask(with: request)
        session = childSession
        task = dataTask
        lock.unlock()

        dataTask.resume()
    }

    func cancel() {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        cancellationRequested = true
        let dataTask = task
        lock.unlock()

        // URLSessionTask.cancel() is asynchronous. Keep the continuation, child
        // session, and delegate alive until didCompleteWithError acknowledges the
        // cancellation instead of racing session invalidation against URL loading.
        dataTask?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse, origin.contains(http.url) else {
            completionHandler(.cancel)
            finish(.failure(BoundedURLSessionError.invalidResponse), cancelSession: true)
            return
        }

        let limit = (200..<300).contains(http.statusCode) ? successLimit : errorLimit
        if http.expectedContentLength > Int64(limit) {
            completionHandler(.cancel)
            finish(
                .failure(BoundedURLSessionError.responseTooLarge(statusCode: http.statusCode)),
                cancelSession: true
            )
            return
        }

        lock.lock()
        guard !completed else {
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        self.response = http
        responseLimit = limit
        if http.expectedContentLength > 0 {
            buffer.reserveCapacity(min(Int(http.expectedContentLength), limit))
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        var failure: BoundedURLSessionError?
        lock.lock()
        if !completed {
            if let responseLimit {
                if data.count > responseLimit - buffer.count {
                    failure = .responseTooLarge(statusCode: response?.statusCode)
                } else {
                    buffer.append(data)
                }
            } else {
                failure = .invalidResponse
            }
        }
        lock.unlock()

        if let failure {
            finish(.failure(failure), cancelSession: true)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard origin.contains(request.url) else {
            completionHandler(nil)
            finish(.failure(BoundedURLSessionError.invalidResponse), cancelSession: true)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let errorValue = error as NSError?
        let wasCancelled = errorValue?.domain == NSURLErrorDomain
            && errorValue?.code == NSURLErrorCancelled
        taskCompletionObserver?(task.state, wasCancelled)

        if let error {
            finish(.failure(error), cancelSession: false, taskCompleted: true)
            return
        }

        lock.lock()
        let result: Result<Output, Error>
        if let response {
            result = .success((buffer, response))
        } else {
            result = .failure(BoundedURLSessionError.invalidResponse)
        }
        lock.unlock()
        finish(result, cancelSession: false, taskCompleted: true)
    }

    private func finish(
        _ result: Result<Output, Error>,
        cancelSession: Bool,
        taskCompleted: Bool = false
    ) {
        lock.lock()
        guard !completed, let continuation else {
            lock.unlock()
            return
        }
        if cancellationRequested && !taskCompleted {
            let dataTask = task
            lock.unlock()
            dataTask?.cancel()
            return
        }
        let finalResult: Result<Output, Error> = cancellationRequested
            ? .failure(CancellationError())
            : result
        completed = true
        self.continuation = nil
        let childSession = session
        let dataTask = task
        session = nil
        task = nil
        lock.unlock()

        if cancelSession { dataTask?.cancel() }
        childSession?.finishTasksAndInvalidate()
        continuation.resume(with: finalResult)
    }
}
