//
//  MobileMessaging.swift
//  MobileMessaging
//
//  Created by Andrey K. on 17/02/16.
//
//

import Foundation

public final class MobileMessaging: NSObject {
	//MARK: Public

	/// Fabric method for Mobile Messaging session.
	/// - parameter userNotificationType: Preferable notification types that indicating how the app alerts the user when a  push notification arrives.
	/// - parameter applicationCode: The application code of your Application from Push Portal website.
	public class func withApplicationCode(_ code: String, notificationType: UIUserNotificationType) -> MobileMessaging? {
		return MobileMessaging.withApplicationCode(code, notificationType: notificationType, backendBaseURL: MMAPIValues.kProdBaseURLString)
	}
	
	/// Fabric method for Mobile Messaging session.
	/// - parameter userNotificationType: Preferable notification types that indicating how the app alerts the user when a  push notification arrives.
	/// - parameter applicationCode: The application code of your Application from Push Portal website.
	/// - parameter backendBaseURL: Your backend server base URL, optional parameter. Default is http://oneapi.infobip.com.
	public class func withApplicationCode(_ code: String, notificationType: UIUserNotificationType, backendBaseURL: String) -> MobileMessaging? {
		sharedInstance = MobileMessaging(applicationCode: code, notificationType: notificationType, backendBaseURL: backendBaseURL)
		return sharedInstance
	}
	
	/// Fabric method for Mobile Messaging session.
	/// Use this method to enable the Geofencing service.
	public func withGeofencingService() -> MobileMessaging {
		self.isGeoServiceEnabled = true
		return self
	}
	
	/// Fabric method for Mobile Messaging session.
	/// It is possible to supply a default implementation of Message Storage to the Mobile Messaging library during initialization. In this case the library will save all received Push messages using the `MMDefaultMessageStorage`. Library can also be initialized either without message storage or with user-provided one (see `withMessageStorage(messageStorage:)`).
	public func withDefaultMessageStorage() -> MobileMessaging {
		self.messageStorage = MMDefaultMessageStorage()
		return self
	}
	
	/// Fabric method for Mobile Messaging session.
	/// It is possible to supply an implementation of Message Storage to the Mobile Messaging library during initialization. In this case the library will save all received Push messages to the supplied `messageStorage`. Library can also be initialized either without message storage or with the default message storage (see `withDefaultMessageStorage()` method).
	/// - parameter messageStorage: a storage object, that implements the `MessageStorage` protocol
	public func withMessageStorage(_ messageStorage: MessageStorage) -> MobileMessaging {
		self.messageStorage = messageStorage
		return self
	}
	
	/// Starts a new Mobile Messaging session.
	///
	/// This method should be called form AppDelegate's `application(_:didFinishLaunchingWithOptions:)` callback.
	/// - remark: For now, Mobile Messaging SDK doesn't support Badge. You should handle the badge counter by yourself.
	public func start(_ completion: ((Void) -> Void)? = nil) {
		MMLogDebug("Starting service...")

		messageStorage?.start()
		
		if MobileMessaging.isPushRegistrationEnabled {
			messageHandler.start()
			if isGeoServiceEnabled {
				self.geofencingService.start()
			}
		}

		if MobileMessaging.application.isRegisteredForRemoteNotifications && currentInstallation.deviceToken == nil {
			MMLogDebug("The application is registered for remote notifications but MobileMessaging lacks of device token. Unregistering...")
			MobileMessaging.application.unregisterForRemoteNotifications()
		}
	
		MobileMessaging.application.registerUserNotificationSettings(UIUserNotificationSettings(types: userNotificationType, categories: nil))
		
		if MobileMessaging.application.isRegisteredForRemoteNotifications == false {
			MMLogDebug("Registering for remote notifications...")
			MobileMessaging.application.registerForRemoteNotifications()
		}
		
		if !isTestingProcessRunning {
			#if DEBUG
				VersionManager.shared.validateVersion()
			#endif
		}
		
		completion?()
		MMLogDebug("Service started!")
	}
	
	/// Current push registration status.
	/// The status defines whether the device is allowed to be receiving push notifications (regular push messages/geofencing campaign messages/messages fetched from the server).
	/// MobileMessaging SDK has the push registration enabled by default.
	public static var isPushRegistrationEnabled: Bool {
		return MobileMessaging.sharedInstance?.isPushRegistrationEnabled ?? true
	}
	
	/// Enables the push registration so the device can receive push notifications (regular push messages/geofencing campaign messages/messages fetched from the server).
	/// MobileMessaging SDK has the push registration enabled by default.
	public static func enablePushRegistration(completion: ((NSError?) -> Void)? = nil) {
		MobileMessaging.sharedInstance?.updateRegistrationEnabledStatus(true, completion: completion)
	}
	
	/// Disables the push registration so the device no longer receives any push notifications (regular push messages/geofencing campaign messages/messages fetched from the server).
	/// MobileMessaging SDK has the push registration enabled by default.
	public static func disablePushRegistration(completion: ((NSError?) -> Void)? = nil) {
		MobileMessaging.sharedInstance?.updateRegistrationEnabledStatus(false, completion: completion)
	}
	
	/// Stops all the currently running Mobile Messaging services.
	/// - Parameter cleanUpData: defines whether the Mobile Messaging internal storage will be dropped. False by default.
	/// - Attention: This function doesn't disable push notifications, they are still being received by the OS.
	public class func stop(_ cleanUpData: Bool = false) {
		if cleanUpData {
			MobileMessaging.sharedInstance?.cleanUpAndStop()
		} else {
			MobileMessaging.sharedInstance?.stop()
		}
	}
	
	/// Logging utility is used for:
	/// - setting up the logging options and logging levels.
	/// - obtaining a path to the logs file in case the Logging utility is set up to log in file (logging options contains `.file` option).
	public static var logger: MMLogging = MMLogger()

	/// This service manages geofencing areas, emits geografical regions entering/exiting notifications.
	///
	/// You access the Geofencing service APIs through this property.
	public class var geofencingService: MMGeofencingService? {
		return MobileMessaging.sharedInstance?.geofencingService
	}
	
	/// This method handles a new APNs device token and updates user's registration on the server.
	///
	/// This method should be called form AppDelegate's `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` callback.
	/// - parameter token: A token that identifies a particular device to APNs.
	public class func didRegisterForRemoteNotificationsWithDeviceToken(_ token: Data) {
		MobileMessaging.sharedInstance?.didRegisterForRemoteNotificationsWithDeviceToken(token)
	}
	
	/// This method handles incoming remote notifications and triggers sending procedure for delivery reports. The method should be called from AppDelegate's `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` callback.
	///
	/// - parameter userInfo: A dictionary that contains information related to the remote notification, potentially including a badge number for the app icon, an alert sound, an alert message to display to the user, a notification identifier, and custom data.
	/// - parameter fetchCompletionHandler: A block to execute when the download operation is complete. The block is originally passed to AppDelegate's `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` callback as a `fetchCompletionHandler` parameter. Mobile Messaging will execute this block after sending notification's delivery report.
	public class func didReceiveRemoteNotification(_ userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		MobileMessaging.sharedInstance?.didReceiveRemoteNotification(userInfo, newMessageReceivedCallback: nil, completion: { result in
			completionHandler(.newData)
		})
	}
	
	/// This method is called when a running app receives a local notification. The method should be called from AppDelegate's `application(_:didReceiveLocalNotification:)` or `application(_:didReceive:)` callback.
	///
	/// - parameter notification: A local notification that encapsulates details about the notification, potentially including custom data.
	public class func didReceiveLocalNotification(_ notification: UILocalNotification) {
		let wasNotificationTapped = application.applicationState == .inactive
		if wasNotificationTapped {
			if	let userInfo = notification.userInfo,
				let payload = userInfo[LocalNotificationKeys.pushPayload] as? APNSPayload,
				let createdDate = userInfo[LocalNotificationKeys.createdDate] as? Date,
				let message = MTMessage(payload: payload, createdDate: createdDate)
			{
				MMQueue.Main.queue.executeAsync {
					MobileMessaging.notificationTapHandler?(message)
				}
			}
		}
	}
	
	/// Maintains attributes related to the current application installation such as APNs device token, badge number, etc.
	public class var currentInstallation: MMInstallation? {
		return MobileMessaging.sharedInstance?.currentInstallation
	}
	
	/// Returns the default message storage if used. For more information see `MMDefaultMessageStorage` class description.
	public class var defaultMessageStorage: MMDefaultMessageStorage? {
		return MobileMessaging.sharedInstance?.messageStorage as? MMDefaultMessageStorage
	}

	/// Maintains attributes related to the current user such as unique ID for the registered user, email, MSISDN, custom data, external id.
	public class var currentUser: MMUser? {
		return MobileMessaging.sharedInstance?.currentUser
	}
	
	/// This method sets seen status for messages and sends a corresponding request to the server. If something went wrong, the library will repeat the request until it reaches the server.
	/// - parameter messageIds: Array of identifiers of messages that need to be marked as seen.
	public class func setSeen(messageIds: [String]) {
		MobileMessaging.sharedInstance?.setSeen(messageIds)
	}
	
	//FIXME: MOMEssage should be replaced with something lighter
	/// This method sends mobile originated messages to the server.
	/// - parameter messages: Array of objects of `MOMessage` class that need to be sent.
	/// - parameter completion: The block to execute after the server responded, passes an array of `MOMessage` messages, that cont
	public class func sendMessages(_ messages: [MOMessage], completion: (([MOMessage]?, NSError?) -> Void)? = nil) {
		MobileMessaging.sharedInstance?.sendMessages(messages, completion: completion)
	}
	
	/// A boolean variable that indicates whether the library will be sending the carrier information to the server.
	///
	/// Default value is `false`.
	public static var carrierInfoSendingDisabled: Bool = false
	
	/// A boolean variable that indicates whether the library will be sending the system information such as OS version, device model, application version to the server.
	///
	/// Default value is `false`.
	public static var systemInfoSendingDisabled: Bool = false
	
	/// An auxillary component provides the convinient access to the user agent data.
	public static var userAgent = MMUserAgent()
	
	/// A block object to be executed when user opens the app by tapping on the notification alert. This block takes:
	/// - single MTMessage object initialized from the Dictionary.
	public static var notificationTapHandler: ((_ message: MTMessage) -> Void)?
	
	/// The message handling object defines the behaviour that is triggered during the message handling.
	///
	/// You can implement your own message handling either by subclassing `MMDefaultMessageHandling` or implementing the `MessageHandling` protocol.
	public static var messageHandling: MessageHandling = MMDefaultMessageHandling()
	
//MARK: Internal
	static var sharedInstance: MobileMessaging?
	let userNotificationType: UIUserNotificationType
	let applicationCode: String
	
	var storageType: MMStorageType = .SQLite
	let remoteAPIBaseURL: String
	var isGeoServiceEnabled: Bool = false
	
	/// - parameter clearKeychain: Bool, true by default, used in unit tests
	func cleanUpAndStop(_ clearKeychain: Bool = true) {
		MMLogDebug("Cleaning up MobileMessaging service...")
		MMCoreDataStorage.dropStorages(internalStorage: internalStorage, messageStorage: messageStorage as? MMDefaultMessageStorage)
		if (clearKeychain) {
			keychain.clear()
		}
		stop()
	}
	
	func stop() {
		MMLogInfo("Stopping MobileMessaging service...")
		if MobileMessaging.application.isRegisteredForRemoteNotifications {
			MobileMessaging.application.unregisterForRemoteNotifications()
		}

		messageStorage?.stop()

		MobileMessaging.application = UIApplication.shared
		MobileMessaging.notificationTapHandler = nil
		MobileMessaging.messageHandling = MMDefaultMessageHandling()
		
		geofencingService.stop()
		messageHandler.stop()
	}
	
	func didReceiveRemoteNotification(_ userInfo: [AnyHashable : Any], newMessageReceivedCallback: (([AnyHashable : Any]) -> Void)? = nil, completion: ((NSError?) -> Void)? = nil) {
		MMLogDebug("New remote notification received \(userInfo)")
		messageHandler.handleAPNSMessage(userInfo, applicationState: MobileMessaging.application.applicationState, newMessageReceivedCallback: newMessageReceivedCallback, completion: completion)
	}
	
	func didRegisterForRemoteNotificationsWithDeviceToken(_ token: Data, completion: ((NSError?) -> Void)? = nil) {
		MMLogDebug("Application did register with device token \(token.mm_toHexString)")
		NotificationCenter.mm_postNotificationFromMainThread(name: MMNotificationDeviceTokenReceived, userInfo: [MMNotificationKeyDeviceToken: token.mm_toHexString])
		currentInstallation.updateDeviceToken(token: token, completion: completion)
	}
	
	func updateRegistrationEnabledStatus(_ value: Bool, completion: ((NSError?) -> Void)? = nil) {
		currentInstallation.updateRegistrationEnabledStatus(value: value, completion: completion)
		updateRegistrationEnabledSubservicesStatus(isPushRegistrationEnabled: value)
	}
	
	func updateRegistrationEnabledSubservicesStatus(isPushRegistrationEnabled value: Bool) {
		if value == false {
			geofencingService.stop()
			messageHandler.stop()
		} else {
			messageHandler.start()
			if isGeoServiceEnabled {
				geofencingService.start()
			}
		}
	}

	func setSeen(_ messageIds: [String], completion: ((SeenStatusSendingResult) -> Void)? = nil) {
		MMLogDebug("Setting seen status: \(messageIds)")
		messageHandler.setSeen(messageIds, completion: completion)
	}
	
	func sendMessages(_ messages: [MOMessage], completion: (([MOMessage]?, NSError?) -> Void)? = nil) {
		MMLogDebug("Sending mobile originated messages...")
		messageHandler.sendMessages(messages, completion: completion)
	}
	
	var isPushRegistrationEnabled: Bool {
		return (self.currentInstallation.installationManager.getValueForKey("isRegistrationEnabled") as? Bool) ?? true
	}
	
	//MARK: Private
	private init?(applicationCode: String, notificationType: UIUserNotificationType, backendBaseURL: String) {
		var storage: MMCoreDataStorage? = try? MMCoreDataStorage.makeInternalStorage(self.storageType)
		
		let logCoreDataInitializationError = {
			MMLogError("Unable to initialize Core Data stack. MobileMessaging SDK service stopped because of the fatal error!")
		}
		
		guard let unwrappedStorage = storage else {
			logCoreDataInitializationError()
			return nil
		}
		
		if MMInstallation(storage: unwrappedStorage).applicationCodeChanged(applicationCode) {
			MMLogWarn("Data will be cleaned up due to change of the application code.")
			MMCoreDataStorage.dropStorages(internalStorage: unwrappedStorage, messageStorage: messageStorage as? MMDefaultMessageStorage)
			storage = try? MMCoreDataStorage.makeInternalStorage(self.storageType)
		}
		
		self.applicationCode = applicationCode
		userNotificationType = notificationType
		self.remoteAPIBaseURL = backendBaseURL
		
		if let unwrappedStorage = storage {
			self.internalStorage = unwrappedStorage
			self.remoteApiManager = RemoteAPIManager(baseUrl: self.remoteAPIBaseURL, applicationCode: self.applicationCode)
			self.currentInstallation = MMInstallation(storage: unwrappedStorage)
			self.currentInstallation.applicationCode = applicationCode
			self.currentUser = MMUser(installation: self.currentInstallation)
			self.keychain = MMKeychain(applicationCode: self.applicationCode)
			self.messageHandler = MMMessageHandler(storage: unwrappedStorage)
			self.geofencingService = MMGeofencingService(storage: unwrappedStorage)
			self.appListener = MMApplicationListener(messageHandler: self.messageHandler, installation: self.currentInstallation, user: self.currentUser, geofencingService: self.geofencingService)
			
			MMLogInfo("SDK successfully initialized!")
		} else {
			logCoreDataInitializationError()
			return nil
		}
	}

	class var messageStorage: MessageStorage? {
		return MobileMessaging.sharedInstance?.messageStorage
	}
	
	var messageStorageAdapter: MMMessageStorageQueuedAdapter?
	private(set) var messageStorage: MessageStorage? {
		didSet {
			messageStorageAdapter = MMMessageStorageQueuedAdapter(adapteeStorage: messageStorage)
		}
	}
	let internalStorage: MMCoreDataStorage
	let currentInstallation: MMInstallation
	let currentUser: MMUser
	let appListener: MMApplicationListener
	let messageHandler: MMMessageHandler
	var geofencingService: MMGeofencingService // variable only for testing purposes
	let remoteApiManager: RemoteAPIManager
	static var application: UIApplicationProtocol = UIApplication.shared
	let keychain: MMKeychain
}

extension UIApplication: UIApplicationProtocol {}

protocol UIApplicationProtocol {
	var applicationIconBadgeNumber: Int { get set }
	var applicationState: UIApplicationState { get }
	var isRegisteredForRemoteNotifications: Bool { get }
	func unregisterForRemoteNotifications()
	func registerForRemoteNotifications()
	func presentLocalNotificationNow(_ notification: UILocalNotification)
	func registerUserNotificationSettings(_ notificationSettings: UIUserNotificationSettings)
	var currentUserNotificationSettings: UIUserNotificationSettings? { get }
}
