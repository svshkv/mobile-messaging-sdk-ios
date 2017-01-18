//
//  MMKeychain.swift
//
//  Created by okoroleva on 13.01.17.
//
//

struct KeychainKeys {
	static let prefix = "com.mobile-messaging"
	static let internalId = "internalId"
	static let applicationCode = "applicationCode"
}

class MMKeychain: KeychainSwift {
	var internalId: String? {
		get {
			let internalId = get(KeychainKeys.internalId)
			MMLogDebug("[Keychain] get internalId \(internalId)")
			return internalId
		}
		set {
			if let unwrappedValue = newValue {
				MMLogDebug("[Keychain] set internalId \(unwrappedValue)")
				set(unwrappedValue, forKey: KeychainKeys.internalId, withAccess: .accessibleWhenUnlockedThisDeviceOnly)
			}
		}
	}
	
	init(applicationCode: String) {
		let prefix = KeychainKeys.prefix + "/" + (Bundle.main.bundleIdentifier ?? "")
		super.init(keyPrefix: prefix)
		update(withApplicationCode: applicationCode)
	}
	
	//MARK: private
	private var applicationCode: String? {
		get {
			let applicationCode = get(KeychainKeys.applicationCode)
			MMLogDebug("[Keychain] get applicationCode \(applicationCode)")
			return applicationCode
		}
		set {
			if let unwrappedValue = newValue {
				MMLogDebug("[Keychain] set applicationCode \(unwrappedValue)")
				set(unwrappedValue, forKey: KeychainKeys.applicationCode, withAccess: .accessibleWhenUnlockedThisDeviceOnly)
			}
		}
	}
	
	private func update(withApplicationCode applicationCode: String) {
		if self.applicationCode != applicationCode {
		    clear()
			self.applicationCode = applicationCode
		}
	}
	
	@discardableResult
	override func clear() -> Bool {
		MMLogDebug("[Keychain] clearing")
		let cleared = delete(KeychainKeys.applicationCode) && delete(KeychainKeys.internalId)
		if !cleared {
			MMLogError("[Keychain] clearing failure \(lastResultCode)")
		}
		return cleared
	}
}
