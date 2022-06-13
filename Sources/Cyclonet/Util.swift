//
//  Util.swift
//  Cyclonet
//
//  Created by David Baraff on 7/3/17.
//  Copyright © 2017 David Baraff. All rights reserved.
//

import Foundation
import Debmate

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
        if progressHandler != nil {
            sessionTask.addObserver(self, forKeyPath: "countOfBytesReceived", options: .new, context: nil)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        progressHandler?(sessionTask.countOfBytesReceived, sessionTask.countOfBytesExpectedToReceive)
    }
    
    func shutdown() {
        if progressHandler != nil {
            sessionTask.removeObserver(self, forKeyPath: "countOfBytesReceived")
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
