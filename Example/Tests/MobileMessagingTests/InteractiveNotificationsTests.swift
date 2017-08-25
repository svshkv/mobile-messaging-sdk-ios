//
//  InteractiveNotificationsTests.swift
//  MobileMessagingExample
//
//  Created by okoroleva on 24.07.17.
//

import XCTest
@testable import MobileMessaging
import UserNotifications

class MessagHandlerMock: MMMessageHandler {
	var setSeenWasCalled: (() -> Void)?
	var sendMessageWasCalled: (([MOMessage]) -> Void)?
	
	convenience init(originalHandler: MMMessageHandler) {
		self.init(storage: originalHandler.storage, mmContext: originalHandler.mmContext)
	}
	
	override func setSeen(_ messageIds: [String], completion: ((SeenStatusSendingResult) -> Void)?) {
		setSeenWasCalled?()
		completion?(SeenStatusSendingResult.Cancel)
	}
	
	override func sendMessages(_ messages: [MOMessage], isUserInitiated: Bool, completion: (([MOMessage]?, NSError?) -> Void)?) {
		sendMessageWasCalled?(messages)
		completion?(messages, nil)
	}
}

class InteractiveNotificationsTests: MMTestCase {
	let actionId = "actionId"
	let categoryId = "categoryId"
	
	func testActionHandlerCalledAndMOSent() {
		weak var testCompleted = expectation(description: "testCompleted")
		
		let action = NotificationAction(identifier: actionId, title: "Action", options: [.moRequired])!
		let category = NotificationCategory(identifier: categoryId, actions: [action], options: nil, intentIdentifiers: nil)!
		var set = Set<NotificationCategory>()
		set.insert(category)
		
		
		cleanUpAndStop()
		
		
		let mm = mockedMMInstanceWithApplicationCode(MMTestConstants.kTestCorrectApplicationCode)!.withInteractiveNotificationCategories(set)
		mm.start()
		
		
		let msgHandlerMock = MessagHandlerMock(originalHandler: mobileMessagingInstance.messageHandler)
		weak var seenCalled = expectation(description: "seenCalled")
		weak var sendMessageCalled = expectation(description: "sendMessageCalled")
		msgHandlerMock.sendMessageWasCalled = { messages in
			XCTAssertEqual(messages.first!.text, "\(self.categoryId) \(self.actionId)")
			sendMessageCalled?.fulfill()
		}
		msgHandlerMock.setSeenWasCalled = { seenCalled?.fulfill() }
		mm.messageHandler = msgHandlerMock
		
		
		MobileMessaging.notificationActionHandler = NotificationActionHandlerMock(handlingBlock: { (_action, message, completionHandler) in
			if _action == action {
				testCompleted?.fulfill()
			}
			completionHandler()
		})
		
		MobileMessaging.handleActionWithIdentifier(identifier: action.identifier, forRemoteNotification: ["messageId": UUID.init().uuidString, "aps": ["alert": ["body": "text"], "category": category.identifier]], responseInfo: nil) {}
		
		waitForExpectations(timeout: 10, handler: nil)
	}
	
	func testActionOptions() {
		
		let checkingBlock: ([NotificationActionOptions]) -> Void = { options in
			let action = NotificationAction(identifier: "actionId1", title: "Action", options: options)
			XCTAssertTrue(action != nil)
			let uiUserNotificationAction = action!.uiUserNotificationAction
			XCTAssertTrue(uiUserNotificationAction.isAuthenticationRequired == options.contains(.authenticationRequired))
			XCTAssertTrue(uiUserNotificationAction.isDestructive == options.contains(.destructive))
			XCTAssertTrue(uiUserNotificationAction.activationMode == (options.contains(.foreground) ? .foreground : .background))
			
			if #available(iOS 10.0, *) {
				let unUserNotificationAction = action!.unUserNotificationAction
				
				XCTAssertTrue(unUserNotificationAction.options.contains(.authenticationRequired) == options.contains(.authenticationRequired))
				XCTAssertTrue(unUserNotificationAction.options.contains(.destructive) == options.contains(.destructive))
				XCTAssertTrue(unUserNotificationAction.options.contains(.foreground) == options.contains(.foreground))
			}
		}
		
		checkingBlock([.foreground])
		checkingBlock([.destructive])
		checkingBlock([.authenticationRequired])
		checkingBlock([.foreground,.authenticationRequired])
		checkingBlock([.foreground, .destructive])
		checkingBlock([.authenticationRequired, .destructive])
		checkingBlock([.authenticationRequired, .destructive, .foreground])
	}
	
	func testCategoryOptions() {
		let testIntentIds = ["test_intent_id"]
		let action = NotificationAction(identifier: actionId, title: "Action", options: nil)
		XCTAssertNotNil(action)
		let category: NotificationCategory!
		if #available(iOS 10.0, *) {
			category = NotificationCategory(identifier: categoryId,
			                                actions: [action!],
			                                options: [.allowInCarPlay, .customDismissAction],
			                                intentIdentifiers: testIntentIds)
		} else {
			category = NotificationCategory(identifier: categoryId,
			                                actions: [action!],
			                                options: nil,
			                                intentIdentifiers: nil)
		}
		XCTAssertNotNil(category)
		let uiCategory = category?.uiUserNotificationCategory
		XCTAssertTrue(uiCategory?.actions(for: .minimal)?.count == 1)
		XCTAssertTrue(uiCategory?.actions(for: .default)?.count == 1)
		
		if #available(iOS 10.0, *) {
			let unCategory = category!.unUserNotificationCategory
			XCTAssertTrue(unCategory.actions.count == 1)
			XCTAssertTrue(unCategory.options.contains(.allowInCarPlay))
			XCTAssertTrue(unCategory.options.contains(.customDismissAction))
			XCTAssertTrue(unCategory.intentIdentifiers == testIntentIds)
		}
	}
	
	func testThatPredefinedCategoriesWork() {
		weak var testCompleted = expectation(description: "testCompleted")
		XCTAssertEqual(NotificationsInteractionService.sharedInstance?.allNotificationCategories?.count, PredefinedCategoriesTest().categoriesIds?.count)
		
		let allActions = NotificationsInteractionService.sharedInstance?.allNotificationCategories?.reduce([String: XCTestExpectation](), { (result, category) -> [String: XCTestExpectation] in
			return result + category.actions.reduce([String: XCTestExpectation](), { (result, action) -> [String: XCTestExpectation] in
				return result + ["\(category.identifier)+\(action.identifier)": expectation(description: "\(category.identifier)+\(action.identifier)")]
			})
		})
		
		MobileMessaging.notificationActionHandler = NotificationActionHandlerMock(handlingBlock: { (_action, message, completionHandler) in
			allActions?["\(message.category!)+\(_action.identifier)"]?.fulfill()
			completionHandler()
		})
		
		mobileMessagingInstance.messageHandler = MessagHandlerMock(originalHandler: mobileMessagingInstance.messageHandler)
		
		NotificationsInteractionService.sharedInstance?.allNotificationCategories?.forEach { category in
			category.actions.forEach { action in
				MobileMessaging.handleActionWithIdentifier(identifier: action.identifier, forRemoteNotification: ["messageId": UUID.init().uuidString, "aps": ["alert": ["body": "text"], "category": category.identifier]], responseInfo: nil) {
					// do nothing
				}
			}
		}
		
		testCompleted?.fulfill()
		waitForExpectations(timeout: 60, handler: nil)
	}
	
	func testSystemDefinedDismissAction() {
		guard #available(iOS 10.0, *) else {
			return
		}
		weak var testCompleted = expectation(description: "testCompleted")
		
		let category = NotificationCategory(identifier: categoryId, actions: [], options: [.customDismissAction], intentIdentifiers: nil)!
		var set = Set<NotificationCategory>()
		set.insert(category)
		
		cleanUpAndStop()
		
		let mm = mockedMMInstanceWithApplicationCode(MMTestConstants.kTestCorrectApplicationCode)!.withInteractiveNotificationCategories(set)
		mm.start()
		
		let msgHandlerMock = MessagHandlerMock(originalHandler: mobileMessagingInstance.messageHandler)
		weak var seenCalled = expectation(description: "seenCalled")
		msgHandlerMock.setSeenWasCalled = { seenCalled?.fulfill() }
		mm.messageHandler = msgHandlerMock
		
		MobileMessaging.notificationActionHandler = NotificationActionHandlerMock(handlingBlock: { (_action, message, completionHandler) in
			if _action.identifier == UNNotificationDismissActionIdentifier {
				testCompleted?.fulfill()
			}
			completionHandler()
		})
		
		MobileMessaging.handleActionWithIdentifier(identifier: UNNotificationDismissActionIdentifier, forRemoteNotification: ["messageId": UUID.init().uuidString, "aps": ["alert": ["body": "text"], "category": category.identifier]], responseInfo: nil) {}
		
		waitForExpectations(timeout: 10, handler: nil)
	}
}

class PredefinedCategoriesTest {
	var bundle: Bundle? {
		return Bundle(identifier:"org.cocoapods.MobileMessaging")
	}
	var path: String? {
		return bundle?.path(forResource: "PredefinedNotificationCategories", ofType: "plist")
	}
	
	var categoriesIds: Set<String>? {
		if let path = path,
			let categories = NSArray(contentsOfFile: path) as? [[String: Any]] {
			let catIds = categories.map { categDict -> String in
				return categDict["identifier"] as! String
			}
			return Set(catIds)
		}
		return nil
	}
}

class NotificationActionHandlerMock: NotificationActionHandling {
	let handlingBlock: (_ action: NotificationAction, _ message: MTMessage, _ completion: () -> Void) -> Void
	init(handlingBlock: @escaping (_ action: NotificationAction, _ message: MTMessage, _ completion: () -> Void) -> Void) {
		self.handlingBlock = handlingBlock
	}
	
	func handle(action: NotificationAction, forMessage message: MTMessage, withCompletionHandler completionHandler: @escaping () -> Void) {
		handlingBlock(action, message, completionHandler)
	}
}