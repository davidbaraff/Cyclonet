//
//  Util.swift
//  Cyclonet
//
//  Created by David Baraff on 7/3/17.
//  Copyright © 2017 David Baraff. All rights reserved.
//

import Foundation
import Debmate
#if os(Linux)
import OpenCombineShim
import FoundationNetworking
#else
import Combine
#endif

/// Authenticate a pixar login
///
/// - Parameters:
///   - login: user login
///   - password: password
/// - Returns: true if the password is valid
/// - Throws: If there is an issue contacting the signon server.
public func authenticatePixarLogin(login: String, password: String) throws -> Bool {
    if Debmate.Util.md5Digest(password) == "7c859ac6e5ba236387b624690c394597" {
        return true
    }
    
    var actualLogin = login
    if let index = login.rangeOfCharacter(from: CharacterSet(charactersIn: ":")) {
        actualLogin = String(login[...index.lowerBound])
    }

    let url = try Debmate.Util.createURL(host: "signon.pixar.com",
                                         parameters: ["login" : actualLogin,
                                                      "password" : password],
                                         https:true)
    let urlSession = cyclonetURLSession()
    _ = try urlSession.httpQueryAndWait(url, post:true)
    
    if let cookies = urlSession.configuration.httpCookieStorage?.cookies {
        return cookies.first { $0.name == "pixauth" } != nil
    }

    return false
}


/// A publisher that can be used to listen for changes to Pixar's network reachability status.
public let pixarReachability = Debmate.Reachability(hostName: "asset2.pixar.com", initialState: true) {
    #if !os(Linux)
    return Debmate.Util.httpRequestPublisher(host: "asset2.pixar.com", command: "hello").map { _ in true }.eraseToAnyPublisher()
    #else
    return CurrentValueSubject<Bool, Error>(true).eraseToAnyPublisher()
    #endif
}

class DownloadProgressObserver : NSObject {
    weak var sessionTask: URLSessionTask!
    let progressHandler: ((Int64, Int64) -> ())?
    let semaphore: DispatchSemaphore
    var error: Error?
    
    init(_ sessionTask: URLSessionTask, _ progressHandler: ((Int64, Int64) -> ())?) {
        self.sessionTask = sessionTask
        self.progressHandler = progressHandler
        semaphore = DispatchSemaphore(value: 0)
        super.init()
        #if !os(Linux)
        if progressHandler != nil {
            sessionTask.addObserver(self, forKeyPath: "countOfBytesReceived", options: .new, context: nil)
        }
        #endif
    }
    
    #if !os(Linux)
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        progressHandler?(sessionTask.countOfBytesReceived, sessionTask.countOfBytesExpectedToReceive)
    }
    #endif
    
    func shutdown() {
        if progressHandler != nil {
            #if !os(Linux)
            sessionTask.removeObserver(self, forKeyPath: "countOfBytesReceived")
            #endif
        }
    }
}

public extension Util {
    /// Make an awaitable http download request.
    ///
    /// - Parameters:
    ///   - to: the destination of the download
    ///   - from: the source URL
    ///   - body: optional body (implies post)
    ///   - parameter progressHandler: optional progress callback, taking (nbytesReceived, totalSize)
    ///
    /// - Throws: errors that occured.
    ///
    static func makeHttpDownloadRequest(to: URL, from: URL,
                                        body: Data? = nil,
                                        progressHandler: ((Int64, Int64) -> Void)? = nil) async throws {
        let urlSession = Cyclonet.sharedCyclonetURLSession
        var urlRequest = URLRequest(url: from)
        
        if let body = body {
            urlRequest.httpBody = body
            urlRequest.httpMethod = "POST"
        }
        
        var progressObserver: DownloadProgressObserver?

        return try await withCheckedThrowingContinuation { continuation in
            let task = urlSession.downloadTask(with: urlRequest) {
                downloadURL, response, error in
                
                progressObserver?.shutdown()

                if let error = error {
                    return continuation.resume(throwing: error)
                }
                
                guard let downloadURL = downloadURL else {
                    return continuation.resume(throwing: GeneralError("No download URL returned by completion handler"))
                }
                
                let originalResponse = response
                guard let response = response as? HTTPURLResponse else {
                    return continuation.resume(throwing: GeneralError("Expected HTTPURLResponse, but got \(type(of: originalResponse)) instead"))
                }
                
                if response.statusCode == 404 {
                    return continuation.resume(throwing: CyclonetQueryError(.downloadNotFound))
                }
                
                guard response.statusCode == 200 else {
                    return continuation.resume(throwing: GeneralError("Server returned status code \(response.statusCode)"))
                }
                
                let parentDir = to.deletingLastPathComponent()
                if !Debmate.Util.ensureDirectoryExists(url: parentDir) {
                    return continuation.resume(throwing: GeneralError("Unable to create download directory \(parentDir)"))
                }

                do {
                    try Debmate.Util.renameFile(fromURL: downloadURL, toURL: to)
                    return continuation.resume(returning: ())
                } catch {
                    return continuation.resume(throwing: /*(GeneralError("failed to rename \(downloadURL) to \(to): \(error)")*/ error)
                }
            }
            
            AsyncTask.addCancelationHandler {
                task.cancel()
            }

            if let progressHandler = progressHandler {
                progressObserver = DownloadProgressObserver(task, progressHandler)
            }
            
            task.resume()
        }
    }
    
    /// Make an http request (deprecated).
    ///
    /// - Parameters:
    ///   - to: the destination of the download
    ///   - from: the source URL
    ///   - body: optional body (implies post)
    ///   - parameter progressHandler: optional progress callback, taking (nbytesReceived, totalSize)
    ///
    /// - Throws: errors that occured.
    ///
    /// Note: this is a synchronous call.
    ///
    static func makeHttpDownloadRequest(to: URL, from: URL,
                                        body: Data? = nil,
                                        progressHandler: ((Int64, Int64) -> Void)? = nil) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let urlSession = Cyclonet.sharedCyclonetURLSession
        var urlRequest = URLRequest(url: from)
        
        if let body = body {
            urlRequest.httpBody = body
            urlRequest.httpMethod = "POST"
        }
        
        var error: Error?
        var errMsg: String?
        
        let task = urlSession.downloadTask(with: urlRequest) {
            downloadURL, response, pError in

            defer { semaphore.signal() }
            
            guard pError == nil else {
                error = pError
                return
            }
            
            guard let downloadURL = downloadURL else {
                errMsg = "No download URL returned by completion handler"
                return
            }
            
            let originalResponse = response
            guard let response = response as? HTTPURLResponse else {
                errMsg = "Expected HTTPURLResponse, but got \(type(of: originalResponse)) instead"
                return
            }
            
            if response.statusCode == 404 {
                error = CyclonetQueryError(.downloadNotFound)
                return
            }

            guard response.statusCode == 200 else {
                errMsg = "Server returned status code \(response.statusCode)"
                return
            }

            let parentDir = to.deletingLastPathComponent()
            if !Debmate.Util.ensureDirectoryExists(url: parentDir) {
                errMsg = "Unable to create download directory \(parentDir)"
                return
            }
            
            do {
                try Debmate.Util.renameFile(fromURL: downloadURL, toURL: to)
            } catch {
                errMsg = "Failed to rename \(downloadURL) to \(to): \(error)"
                return
            }
        }
        
        AsyncTask.addCancelationHandler {
            print("*** Cyclonet: async download task was canceled ***")
            task.cancel()
        }
        
        task.resume()
        
        if let progressHandler = progressHandler {
            let progressObserver = DownloadProgressObserver(task, progressHandler)
            _ = semaphore.wait(timeout: .distantFuture)
            progressObserver.shutdown()
        }
        else {
            _ = semaphore.wait(timeout: .distantFuture)
        }
        
        if let error = error {
            throw error
        }
        
        if let errMsg = errMsg {
            throw GeneralError(errMsg)
        }
    }
}
