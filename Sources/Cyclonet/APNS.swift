//
//  APNS.swift
//  Cyclonet
//
//  Created by David Baraff on 5/9/19.
//  Copyright © 2019 David Baraff. All rights reserved.
//

import Foundation
import Starscream
import Debmate

fileprivate let apnsServer = "midnightharmonics.com"
fileprivate let apnsSandboxServerPort = 8080
fileprivate let apnsServerPort = 8081

/// Configure APNS notifications using Pixar's APNS server
public class APNSHandler {
    /// Struct to represent received APNS notifications.
    public struct Notification {
        public let category: String
        public let value: String
        public let timestamp: Date
        public let senderID: String?
    }
    
    /// A constant denoting the app is interested in any value for a particular subscribed category.
    static public let allValues = "__true__"

    public typealias NotificationHandler = (Notification, Bool) -> ()

    private let handler: NotificationHandler
    private var receivedNotifications = [Notification]()

    /// Construct a new APNSHandler.
    /// - Parameter handler: callback for receiving push notifications.
    public init(handler: @escaping NotificationHandler) {
        self.handler = handler
    }
    
    /// Entry point for the app delegate to route notifications.
    /// - Parameters:
    ///   - userInfo: The userInfo dictionary of the received push notification.
    ///   - background: If the notification was received while the app was backgrounded.
    ///
    /// Non-background notifications are handled immediately.  Otherwise, when the app wakes up,
    /// it should call `handleWaitingNotifications`().
    public func receivedRemoteNotification(userInfo: [AnyHashable : Any], background: Bool) {
        guard let category = userInfo["category"] as? String,
              let value = userInfo["value"] as? String,
              let timestamp = userInfo["timestamp"] as? Double else {
                print("Ignoring non-APNS push: \(userInfo)")
                return
        }
        
        let n = APNSHandler.Notification(category: category,
                                         value: value,
                                         timestamp: Date(timeIntervalSince1970: timestamp),
                                         senderID: userInfo["senderID"] as? String)
        if background {
            receivedNotifications.append(n)
        }
        else {
            handler(n, false)
        }
    }

    
    /// Handle all notifications that have accumulated while the app was in the background.
    public func handleWaitingNotifications() {
        let notifications = receivedNotifications
        receivedNotifications = []
        
        for n in notifications {
            handler(n, true)
        }
    }
    
    
    /// Set the values for a particular category for which the app should receive APNS push notifications via Pixar's APNS service.
    /// - Parameters:
    ///   - category: category name
    ///   - values: specific values the app is interested in
    ///   - deviceToken: The deviceToken of the app.
    ///   - appBundle: The appBundle string.
    ///   - sandbox: Whether or not the app is in sandbox (vs production) mode.
    ///   - login: login of the user of this app (for debugging purposes only)
    ///   - deviceDescription: description of this device (for debugging purposes only)
    ///
    /// When subscribing to a particular category, the app will only receiving notifications for values
    /// in that category contained in the values parameter.  Pass [APNSHandler.allValues] to subscribe
    /// to notifications for any value within that category.
    ///
    /// Conversely, set values to the empty array to unsubscribe from a particular category.
    static public func setSubscription(category: String, values: [String],
                                       deviceToken: String, appBundle: String,
                                       sandbox: Bool,
                                       login: String, deviceDescription: String) async throws {
        let url = try Debmate.Util.createURL(host: apnsServer,
                                             port: sandbox ? apnsSandboxServerPort : apnsServerPort,
                                             command: "setSubscriptions",
                                             parameters: ["category" : category,
                                                          "values" : values,
                                                          "deviceToken" : deviceToken,
                                                          "login" : login,
                                                          "appBundle" : appBundle,
                                                          "deviceDescription" : deviceDescription])
        let _: String = try await Cyclonet.sharedCyclonetURLSession.cyclonetHttpQuery(url)
    }
}

