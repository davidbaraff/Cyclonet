//
//  HttpHelpers.swift
//  Cyclonet
//
//  Created by David Baraff on 2/12/16.
//
//

import Foundation
import Debmate
#if !os(Linux)
import Combine
#else
import OpenCombineShim
import FoundationNetworking
import CurlHelper
#endif

public typealias CyclonetDictionary = [String : Any]

/**
 *  Error type thrown by various extensions to NSURLSession.
 */
public struct CyclonetQueryError : Error, CustomStringConvertible {
    /**
     Failure type.
     
     - unknownHost:         host unknown
     - connectionFailure:   connection to specified host/port failed
     - knownError:          a connection failure with a readable description
     - unknownError:        a connection failure with a numeric code
     - unknownResponseType: the internal response type (NSURLHTTPResponse) wasn't returned
     - illegalJsonData:     transmitted json is malformed/illegal
     - unexpectedDataType:  returned type not what was expected
     - clientError:         server raised an error indicating the client was at fault
     - serverError:         server raised an error for a known server error
     - badReturnCodeError:  server returned a status indicating an error
     - unknownServerError:  server unexectedly raised an error
     - dictionaryKeyError:  return dictionary doesn't have expected key
     - dictionaryValueTypeError: returned dictionary value has wrong type
     - canceled:            the request was canceled by the client
     - offline:             network connection not enabled
     */
    public enum Failure {
        case unknownHost(String)
        case connectionFailure(String, Int)
        case knownError(String)
        case unknownError(Int)
        case unknownResponseType(String)
        case illegalJsonData(String)
        case unexpectedDataType(String)
        case clientError(String, String)
        case serverError(String, String)
        case badReturnCodeError
        case unknownServerError(String)
        case dictionaryKeyError(String)
        case dictionaryValueTypeError(String, String)
        case canceled
        case offline
        case downloadNotFound
    }
    
    /// Failure enum.
    public let failure: Failure
    
    ///  numeric status code from http query
    public let statusCode: Int
    
    public init(_ failure: Failure, statusCode: Int = 0) {
        self.failure = failure
        self.statusCode = statusCode
    }
    
    /// description property (read-only)
    public var description: String {
        switch(failure) {
        case .unknownHost(let host):
            return "unknown host '\(host)'"
        case .connectionFailure(let host, let port):
            return "cannot connect to \(host):\(port)"
        case .knownError(let descr):
            return "query failure: \(descr)"
        case .unknownError(let errorCode):
            return "query failure: error code = \(errorCode)"
        case .unknownResponseType(let type):
            return "query returned unknown internal response type '\(type)'"
        case .illegalJsonData(let data):
            return "query returned illegal json data: \(data)"
        case .unexpectedDataType(let typeDescr):
            return "query failed: \(typeDescr)"
        case .clientError (let exception, let traceback):
            return exception + "\n" + traceback
        case .serverError (let exception, let traceback):
            return exception + "\n" + traceback
        case .badReturnCodeError:
            return "errored server return code"
        case .unknownServerError(let descr):
            return "unknown server error: status code = \(statusCode): \(descr)"
        case .dictionaryKeyError(let key):
            return "returned dictionary missing expected key '\(key)'"
        case .dictionaryValueTypeError(let key, let descr):
            return "returned dictionary had type error under key '\(key)': \(descr)"
        case .canceled:
            return "request was canceled"
        case .offline:
            return "network is switched off"
        case .downloadNotFound:
            return "file/data being downloaded not found"
        }
    }
    
    
    /// Like description, but skips any tracebacks.
    public var shortDescription: String {
        switch(failure) {
        case .clientError (let exception, _):
            return exception
        case .serverError (let exception, _):
            return exception
        default:
            return description
        }
    }
}


/// Create a new URL session suitable for cyclonet queries.
///
/// - Returns: the URL session.
public func cyclonetURLSession() -> URLSession {
    let sessionConfig = URLSessionConfiguration.ephemeral
    return URLSession(configuration: sessionConfig)
}


/// A globally available cyclonet URL session.
#if !os(Linux)
public let sharedCyclonetURLSession = cyclonetURLSession()
#else
public var sharedCyclonetURLSession: URLSession { cyclonetURLSession() }
#endif

extension Dictionary {
    
    /// Lookup a value from a dictionary.
    ///
    /// - Parameters:
    ///   - key: dictionary key
    ///   - asType: expected type of stored value
    /// - Returns: value for key
    /// - Throws: if value not found or there is a type mismatch
    public func retrieve<T>(_ key: Dictionary.Key, asType: T.Type? = nil) throws -> T {
        guard let value = self[key] else {
            throw CyclonetQueryError(.dictionaryKeyError(String(describing: key)))
        }
            
        guard let typedValue = value as? T else {
            throw CyclonetQueryError(.dictionaryValueTypeError(String(describing: key),
                "expected type \(T.self); found type \(type(of: value)) instead"))
        }
        
        return typedValue
    }
    
    
    /// Lookup a value from a dictionary within a dictionary.
    ///
    /// - Parameters:
    ///   - key1: key for the dictionary contained in self
    ///   - key2: key for the dictionary stored under key1
    ///   - asType: required type of final looked up value
    /// - Returns: retrieved value
    /// - Throws: if value not found or there is a type mismatch.
    ///
    /// This is a shorthand for writing
    ///      retrieve(key1, asType: Dictionary.self).retrieve(key2)
    public func retrieve<T>(_ key1: Dictionary.Key, _ key2: Dictionary.Key, asType:T.Type? = nil) throws -> T {
        return try retrieve(key1, asType: Dictionary.self).retrieve(key2)
    }
    
    
    /// Lookup a value from a dictionary.
    ///
    /// - Parameters:
    ///   - key: dictionary key
    ///   - allowNull: allow null values in the dictionary (specifically, NSNull)
    ///   - asType: required type of final looked up value
    /// - Returns: stored value or nil if NSNull was stored (and allowNull is true)
    /// - Throws: if value not found, or there is a type mismatch, or allowNull is false and NSNull is found
    public func retrieve<T>(_ key: Dictionary.Key, allowNull: Bool, asType:T.Type? = nil) throws -> T? {
        guard let value = self[key] else {
            throw CyclonetQueryError(.dictionaryKeyError(String(describing: key)))
        }
        
        if let typedValue = value as? T {
            return typedValue
        }
        
        if allowNull {
            if let _ = value as? NSNull {
                return nil
            }
            throw CyclonetQueryError(.dictionaryValueTypeError(String(describing: key),
                "expected type \(T.self) (or null); found type \(type(of: value)) instead"))
        }
        else {
            throw CyclonetQueryError(.dictionaryValueTypeError(String(describing: key),
                "expected type \(T.self); found type \(type(of: value)) instead"))
        }
    }
}

public func translateError(url: URL, error: NSError) -> CyclonetQueryError {
    switch error.code {
    case NSURLErrorCannotFindHost:
        return CyclonetQueryError(.unknownHost(url.host ?? "<unknown hostname>"))
        
    case NSURLErrorCannotConnectToHost:
        let port = (url as NSURL).port ?? 80
        return CyclonetQueryError(.connectionFailure(url.host ?? "<unknown hostname>",  Int(truncating: port)))
        
    case NSURLErrorCancelled:
        return CyclonetQueryError(.canceled)
        
    // case NSURLErrorAppTransportSecurityRequiresSecureConnection:
    case -1022:
        return CyclonetQueryError(.knownError("connection blocked by AppTransportSecurity settings"))
        
    // case URLErrorNetworkConnectionLost
    case -1005:
        fallthrough
    case -1009:
        return CyclonetQueryError(.offline)
        
    default:
        return CyclonetQueryError(.unknownError(error.code))
    }
}

#if !os(Linux)
fileprivate class ProgressObserver : NSObject {
    weak var sessionTask: URLSessionTask?
    var handler: ((Int64, Int64) -> ())?
    
    init (sessionTask: URLSessionTask, handler: ((Int64, Int64) -> ())?) {
        super.init()
        self.sessionTask = sessionTask
        self.handler = handler
        sessionTask.addObserver(self, forKeyPath: "countOfBytesSent", options: .new, context: nil)
    }

    func shutdown() {
        sessionTask?.removeObserver(self, forKeyPath: "countOfBytesSent")
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let sessionTask = sessionTask {
            handler?(sessionTask.countOfBytesSent, sessionTask.countOfBytesExpectedToSend)
        }
    }
}
#endif

fileprivate typealias DataURLResponseError = (data: Data?, response: URLResponse?, error: NSError?)

fileprivate func resumeContinuation(continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>, result: DataURLResponseError) {
    if let error = result.error {
        return continuation.resume(throwing: error)
    }

    if let response = result.response as? HTTPURLResponse {
        if let data = result.data {
            return continuation.resume(returning: (data, response))
        }

        return continuation.resume(throwing: CyclonetQueryError(.unknownResponseType("unexpected nil data with valid HTTPURLResponse")))
    }

    if let response = result.response {
        return continuation.resume(throwing: CyclonetQueryError(.unknownResponseType(String(describing: type(of: response)))))
    }

    return continuation.resume(throwing: CyclonetQueryError(.unknownResponseType("unexpected nil response")))
}


fileprivate func sendOrComplete(publisher: PassthroughSubject<(Data, HTTPURLResponse), Error>, result: DataURLResponseError, url: URL) {
    if let error = result.error {
        publisher.send(completion: .failure(translateError(url: url, error: error)))
    }
    else if let response = result.response as? HTTPURLResponse {
        if let data = result.data {
            publisher.send((data, response))
        }
        else {
            publisher.send(completion: .failure(CyclonetQueryError(.unknownResponseType("unexpected nil data with valid HTTPURLResponse"))))
        }
    }
    else if let response = result.response {
        publisher.send(completion: .failure(CyclonetQueryError(.unknownResponseType(String(describing: type(of: response))))))
    }
    else {
        publisher.send(completion: .failure(CyclonetQueryError(.unknownResponseType("unexpected nil response"))))
    }
}

private func decodeCyclonetResponse<T>(data: Data, response: HTTPURLResponse) throws -> T {
    var decodedObject:Any
    
    do {
        decodedObject = try JSONSerialization.jsonObject(with: data, options:.mutableContainers)
    } catch {
        let dataStr = String(data: data, encoding: String.Encoding.utf8) ?? "<unrepresentable response string>"
        throw CyclonetQueryError(.illegalJsonData(dataStr), statusCode: response.statusCode)
    }
    
    guard let resultList = decodedObject as? [Any] else {
        throw CyclonetQueryError(.illegalJsonData("expected array of objects; got \(type(of: decodedObject))"),
                                statusCode: response.statusCode)
        
    }
    
    if (response.statusCode == 200) {
        if resultList.count != 2 {
            throw CyclonetQueryError(.illegalJsonData("expected array of 2 objects; got length \(resultList.count) instead"),
                                    statusCode:response.statusCode)
        }
        
        guard let resultTuple = resultList[1] as? [AnyObject] else {
            throw CyclonetQueryError(.unexpectedDataType("expected object tuple; got \(type(of: resultList[1]))"),
                                    statusCode:response.statusCode)
        }
        
        if resultTuple.count != 2 {
            throw CyclonetQueryError(.unexpectedDataType("expected tuple of length; tuple had length \(resultTuple.count)"),
                                    statusCode:response.statusCode)
        }
        
        guard let resultCode = resultTuple[0] as? Bool else {
            throw CyclonetQueryError(.unexpectedDataType("expected bool in tuple at position 0; got \(type(of: resultTuple[0])) instead"),
                                    statusCode:response.statusCode)
        }
        
        guard resultCode else {
            throw CyclonetQueryError(.badReturnCodeError)
        }
        
        guard let resultValue = resultTuple[1] as? T else {
            throw CyclonetQueryError(.unexpectedDataType("expected \(type(of: T.self)) in tuple at position 1; got \(type(of: resultTuple[1])) instead"),
                                    statusCode:response.statusCode)
        }
        
        return resultValue
    }
    
    if response.statusCode == 400 || response.statusCode == 500 {
        if resultList.count != 4 {
            throw CyclonetQueryError(.illegalJsonData("expected array of 3 objects; got length \(resultList.count) instead"),
                                    statusCode:response.statusCode)
        }
        
        if response.statusCode == 400 {
            throw CyclonetQueryError(.clientError(String(describing: resultList[2]), String(describing: resultList[3])),
                                    statusCode:response.statusCode)
        }
        throw CyclonetQueryError(.serverError(String(describing: resultList[2]), String(describing: resultList[3])),
                                statusCode:response.statusCode)
    }
    
    throw CyclonetQueryError(.unknownServerError(String(data: data, encoding: String.Encoding.utf8) ?? "<unrepresentable response string>"),
                            statusCode:response.statusCode)
}

extension Publisher {
    /// Block until publisher has completed.
    /// - Parameter publisher: Publisher to wait on.
    /// - Throws: The error in the publisher, if there is one.
    /// - Returns: The first value the publisher delivers.
    ///
    /// This call blocks until either the first value is received or the publisher completes with an error (which is then rethrown).
    public func blockTillCompletion(_ queue: DispatchQueue) throws -> Output {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Output?
        var failure: Failure?
        
        let cancellable: Cancellable = queue.sync {
            self.sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    failure = error
                    semaphore.signal()
                case .finished:
                    ()
                }
            }) { value in
                result = value
                semaphore.signal()
            }
        }
        
        AsyncTask.addCancelationHandler {
            queue.sync {
                cancellable.cancel()
            }
        }
        
        _ = semaphore.wait(timeout: .distantFuture)
        queue.sync { cancellable.cancel() }
        
        if let result = result {
            return result
        }
        
        throw failure!
    }
}

extension URLSession {
    // MARK: - async REST calls
    
    /// Launch a query.
    /// - Parameters:
    ///   - url: URL for query
    ///   - body: body for query (optional)
    ///   - post: if the method should be post
    ///   - progressHandler:  optional progress callback, taking (nbytesSent, totalSize)
    ///
    /// - Returns: (Data, HTTPURLResponse).
    public func httpQuery(_ url: URL, body: Data? = nil, post: Bool = false,
                          progressHandler: ((Int64, Int64) -> Void)? = nil) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = URLRequest(url: url)
        if let body = body {
            urlRequest.httpBody = body
            urlRequest.httpMethod = "POST"
        }
        else if post {
            urlRequest.httpMethod = "POST"
        }
        
        #if !os(Linux)
        var progressObserver: ProgressObserver!
        #endif

        return try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: urlRequest) { data, response, error in

                #if !os(Linux)
                progressObserver.shutdown()
                #endif
                resumeContinuation(continuation: continuation, result: (data: data, response: response, error: error as NSError?))
            }
            #if !os(Linux)
            progressObserver = ProgressObserver(sessionTask: task, handler: progressHandler)
            #endif

            task.resume()
        }
    }
    
    /// Upload data from a file.
    /// - Parameters:
    ///   - url: URL for post
    ///   - fileURL: a file URL for the body
    ///   - progressHandler: optional progress callback, taking (nbytesSent, totalSize)
    /// - Returns: (Data, HTTPURLResponse).
    /// - Note: The request is made as a POST.
    public func httpQuery(_ url: URL, fromFile fileURL: URL,
                          progressHandler: ((Int64, Int64) -> Void)? = nil) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        
        #if !os(Linux)
        var progressObserver: ProgressObserver!
        #endif
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = self.uploadTask(with: urlRequest, fromFile: fileURL) {
                data, response, error in
                
                #if !os(Linux)
                progressObserver.shutdown()
                #endif

                resumeContinuation(continuation: continuation, result: (data: data, response: response, error: error as NSError?))
            }
            #if !os(Linux)
            progressObserver = ProgressObserver(sessionTask: task, handler: progressHandler)
            #endif
            task.resume()
        }
    }
    
    
    /// Execute a Cyclonet query, returning the result.
    /// - Parameters:
    ///   - url: URL for query
    ///   - body: body for query (optional)
    ///   - progressHandler: optional progress callback, taking (nbytesSent, totalSize)
    /// - Returns: Specified datatype
    ///
    /// The return json data has the format
    ///        ["<protocol-version>", <data>]
    ///
    /// When the request completes normally, <data> is returned.
    /// If the server responds to the query but encounters an error, the returned
    /// json object has the form
    ///
    ///  ["<protocol-version>", statusCode, "<shortError>", "<traceback>"]
    ///
    /// and a CyclonetError of either ClientError or ServerError is thrown.
    public func cyclonetHttpQuery<T>(_ url: URL, body: Data? = nil,
                                    progressHandler: ((Int64, Int64) -> Void)? = nil) async throws -> T {
        let result: (Data, HTTPURLResponse) = try await httpQuery(url, body: body, progressHandler: progressHandler)
        return try decodeCyclonetResponse(data: result.0, response: result.1)
    }
    
    /// Unlike cyclonetQuury, this function does not attempt to decode the data, and simply
    /// returns Void as the value (on success).
    /// - Parameters:
    ///   - url: URL for query
    ///   - body: body for query (optional)
    public func cyclonetHttpCall(_ url: URL, body: Data? = nil) async throws {
        let _: Any = try await cyclonetHttpQuery(url, body: body)
    }
    
    // MARK: - Publisher based REST calls
    
    /// Launch a query.
    /// - Parameters:
    ///   - url: URL for query
    ///   - body: body for query (optional)
    ///   - post: if the method should be post
    ///   - progressHandler:  optional progress callback, taking (nbytesSent, totalSize)
    ///
    /// - Returns: Publisher.
    public func httpQuery(_ url: URL, body: Data? = nil, post: Bool = false, queue: DispatchQueue? = nil,
                          progressHandler: ((Int64, Int64) -> Void)? = nil) -> AnyPublisher<(Data, HTTPURLResponse), Error>  {
        var urlRequest = URLRequest(url: url)
        
        if let body = body {
            urlRequest.httpBody = body
            urlRequest.httpMethod = "POST"
        }
        else if post {
            urlRequest.httpMethod = "POST"
        }
        
        let publisher = PassthroughSubject<(Data, HTTPURLResponse), Error>()
        #if !os(Linux)
        var progressObserver: ProgressObserver!
        #endif

        let task = self.dataTask(with: urlRequest) {
            data, response, error in
            
            #if !os(Linux)
            progressObserver.shutdown()
            #endif
            if let queue = queue {
                queue.sync {
                    sendOrComplete(publisher: publisher, result: (data: data, response: response, error: error as NSError?), url: url)
                }
            }
            else {
                sendOrComplete(publisher: publisher, result: (data: data, response: response, error: error as NSError?), url: url)
            }
        }

        #if !os(Linux)
        progressObserver = ProgressObserver(sessionTask: task, handler: progressHandler)
        #endif

        if let queue = queue {
            return publisher.receive(on: queue).handleEvents(receiveSubscription: { _ in task.resume() },
               receiveCancel: { task.cancel() }).eraseToAnyPublisher()
        }
        else {
            return publisher.handleEvents(receiveSubscription: { _ in task.resume() },
               receiveCancel: { task.cancel() }).eraseToAnyPublisher()
        }
    }
    
    /// Upload data from a file and wait
    /// - Parameters:
    ///   - url: URL for post
    ///   - fileURL: a file URL for the body
    ///   - progressHandler: optional progress callback, taking (nbytesSent, totalSize)
    /// - Returns: publisher.
    /// - Note: The request is made as a POST.
    public func httpQuery(_ url: URL, fromFile fileURL: URL, queue: DispatchQueue? = nil,
                          progressHandler: ((Int64, Int64) -> Void)? = nil) -> AnyPublisher<(Data, HTTPURLResponse), Error> {
        var urlRequest = URLRequest(url: url)
        
        urlRequest.httpMethod = "POST"
        
        let publisher = PassthroughSubject<(Data, HTTPURLResponse), Error>()
        #if !os(Linux)
        var progressObserver: ProgressObserver!
        #endif
        
        let task = self.uploadTask(with: urlRequest, fromFile: fileURL) {
            data, response, error in
            
            #if !os(Linux)
            progressObserver.shutdown()
            #endif
            
            if let queue = queue {
                queue.sync { sendOrComplete(publisher: publisher, result: (data: data, response: response, error: error as NSError?), url: url) }
            }
            else {
                sendOrComplete(publisher: publisher, result: (data: data, response: response, error: error as NSError?), url: url)
            }
        }

        #if !os(Linux)
        progressObserver = ProgressObserver(sessionTask: task, handler: progressHandler)
        #endif
        if let queue = queue {
            return publisher.receive(on: queue).handleEvents(receiveSubscription: { _ in task.resume() }, receiveCancel: { task.cancel() }).eraseToAnyPublisher()
        }
        else {
            return publisher.handleEvents(receiveSubscription: { _ in task.resume() }, receiveCancel:{ task.cancel() }).eraseToAnyPublisher()
        }
    }
    
    /// Execute a query, returning a publisher with the result.
    /// - Parameters:
    ///   - url: URL for query
    ///   - body: body for query (optional)
    ///   - progressHandler: optional progress callback, taking (nbytesSent, totalSize)
    /// - Returns: Specified datatype
    ///
    /// The return json data has the format
    ///        ["<protocol-version>", <data>]
    ///
    /// When the request completes normally, <data> is returned.
    /// If the server responds to the query but encounters an eror, the returned
    /// json object has the form
    ///
    ///  ["<protocol-version>", statusCode, "<shortError>", "<traceback>"]
    ///
    /// and a CyclonetError of either ClientError or ServerError is delivered as the complettion
    /// result to the publisher.
    public func cyclonetHttpQuery<T>(_ url: URL, body: Data? = nil, queue: DispatchQueue? = nil,
                                    progressHandler: ((Int64, Int64) -> Void)? = nil) -> AnyPublisher<T, Error> {
        return httpQuery(url, body: body, queue: queue, progressHandler: progressHandler)
            .tryMap { try decodeCyclonetResponse(data: $0.0, response: $0.1) }.eraseToAnyPublisher()
    }
    
    /// Unlike cyclonetQuury, this function does not attempt to decode the data, and simply
    /// returns Void as the value in the publisher (on success).
    /// - Parameters:
    ///   - url: URL for query
    ///   - body: body for query (optional)
    public func cyclonetHttpCall(_ url: URL, body: Data? = nil, queue: DispatchQueue? = nil) -> AnyPublisher<Void, Error> {
        return cyclonetHttpQuery(url, body: body, queue: queue).map { (result: Any) in () }.eraseToAnyPublisher()
    }
    
    
    // MARK: - Blocking REST calls (deprecated)
    
    /// Upload data from a file and wait
    /// - Parameters:
    ///   - url: URL for post
    ///   - fileURL: a file URL for the body
    ///   - progressHandler: optional progress callback, taking (nbytesSent, totalSize)
    /// - Returns: Data and response.
    /// - Note: This is a blocking call (and deprecated).  Use the publisher version instead.
    public func httpQueryAndWait(_ url: URL, fromFile fileURL: URL, progressHandler: ((Int64, Int64) -> Void)? = nil) throws -> (Data, HTTPURLResponse) {
        let queue = DispatchQueue(label: "com.pixar.blockTillCompletion")
        return try httpQuery(url, fromFile: fileURL, queue: queue).blockTillCompletion(queue)
    }
    
   
    /**
     Launch the given query and wait for a reply.
     
     - parameter url: URL for query
     - parameter body: body for query (optional)
     - parameter post: if the method should be post
     - parameter progressHandler: optional progress callback, taking (nbytesSent, totalSize)
     
     - throws: Throws if something goes wrong.
     
     - returns: a tuple (data, response)
     
     Note: if a body is supplied, post is taken to be true.
     */
    public func httpQueryAndWait(_ url: URL, body: Data? = nil, post: Bool = false,  progressHandler: ((Int64, Int64) -> Void)? = nil) throws -> (Data, HTTPURLResponse) {
        // print("----> Begin blocking async httpQueryAndWait for \(url)...")
        // defer { print("<---- Return from blocking async httpQueryandWait for \(url)") }

        #if !os(Linux)
        let queue = DispatchQueue(label: "com.pixar.blockTillCompletion")
        return try httpQuery(url, body: body, post: post,
                            progressHandler: progressHandler).blockTillCompletion(queue)
        #else
        var statusCode: Int32 = 0
        var nbytes: Int32 = 0

        guard let bytesPtr = curlHelper_download(url.absoluteString, &statusCode, &nbytes) else {
            throw GeneralError("httpQueryAndWait: curlHelper_download return NULL: this should not happen.")
        }
        defer { curlHelper_delete_result(bytesPtr) }

        guard let response = HTTPURLResponse(url: url, statusCode: Int(statusCode),
                                             httpVersion: nil, headerFields: nil) else {
            throw GeneralError("Failed to construct an HTTPURLReponse in httpQueryAndWait: this should not happen")
        
        }

        if statusCode == 200 {
            return (Data(bytes: bytesPtr, count: Int(nbytes)), response)
        }
        else {
            return (Data(bytes: bytesPtr, count: Int(nbytes)+1), response)
        }
        #endif
    }
    
  
    /// Wait for a Cyclonet query to complete.
    /// - Parameters:
    ///   - url: URL for query
    ///   - body: body for query (optional)
    /// - Throws: On error, throws a CyclonetError.
    /// - Note: this is a blocking calling (and thus deprecated).  Use the publisher version instead.
    public func cyclonetHttpCallAndWait(_ url: URL, body: Data? = nil) throws {
        let _: Any = try cyclonetHttpQueryAndWait(url, body: body)
    }
    
    
    /// Wait for a query to complete, returning the requested type.
    /// - Parameters:
    ///   - url: URL for query
    ///   - body: body for query (optional)
    ///   - progressHandler: optional progress callback, taking (nbytesSent, totalSize)
    /// - Throws: errors for network errors or type errors.
    /// - Returns: Specified datatype
    /// - Note: This is a blocking call (and deprecated).  Use the publisher version instead.
    ///
    /// The query must return a json string, which is decoded into the required type.
    ///        The json string has the format
    ///
    ///        ["<protocol-version>", <data>]
    ///
    /// When the request completes normally, <data> is returned.
    /// If the server responds to the query but encounters an eror, the returned
    /// json object has the form
    ///
    ///   ["<protocol-version>", statusCode, "<shortError>", "<traceback>"]
    ///
    /// and a CyclonetError of either ClientError or ServerError is thrown.
    public func cyclonetHttpQueryAndWait<T>(_ url: URL, body: Data? = nil, progressHandler: ((Int64, Int64) -> Void)? = nil) throws -> T {
        let (data, response) = try httpQueryAndWait(url, body: body, progressHandler: progressHandler)
        return try decodeCyclonetResponse(data: data, response: response)
    }
    
    /// Wait for n upload to complete, returning the requested type.
    /// - Parameters:
    ///   - url: URL for query
    ///   - fromFile: fileURL containing data to be uploaded
    ///   - progressHandler: optional progress callback, taking (nbytesSent, totalSize)
    /// - Throws: errors for network errors or type errors.
    /// - Returns: Specified datatype
    /// - Note: This is a blocking call (and deprecated).  Use the publisher version instead.
    ///
    /// The query must return a json string, which is decoded into the required type.
    ///        The json string has the format
    ///
    ///        ["<protocol-version>", <data>]
    ///
    /// When the request completes normally, <data> is returned.
    /// If the server responds to the query but encounters an eror, the returned
    /// json object has the form
    ///
    ///   ["<protocol-version>", statusCode, "<shortError>", "<traceback>"]
    ///
    /// and a CyclonetError of either ClientError or ServerError is thrown.
    public func cyclonetHttpQueryAndWait<T>(_ url: URL, fromFile fileURL: URL, progressHandler: ((Int64, Int64) -> Void)? = nil) throws -> T {
        let (data, response) = try httpQueryAndWait(url, fromFile: fileURL, progressHandler: progressHandler)
        return try decodeCyclonetResponse(data: data, response: response)
    }
}



