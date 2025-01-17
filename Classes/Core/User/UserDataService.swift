//
// Created by Andrey Kadochnikov on 31/10/2018.
//

import Foundation

class UserDataService: MobileMessagingService {

	init(mmContext: MobileMessaging) {
		super.init(mmContext: mmContext, uniqueIdentifier: "UserDataService")
	}

	func setInstallation(withPushRegistrationId pushRegId: String, asPrimary primary: Bool, completion: @escaping ([MMInstallation]?, NSError?) -> Void) {
		let finish: (NSError?) -> Void = { (error) in
			if error == nil {
				let ins = self.resolveInstallationsAfterPrimaryChange(pushRegId, primary)
				MMUser.modifyAll(with: { user in
					user.installations = ins
				})
			}
			completion(self.mmContext.resolveUser().installations, error)
		}

		if mmContext.currentInstallation().pushRegistrationId == pushRegId {
			let ci = mmContext.currentInstallation()
			ci.isPrimaryDevice = primary
			mmContext.installationService.save(installationData: ci, completion: finish)
		} else {
			guard let authPushRegistrationId = mmContext.currentInstallation().pushRegistrationId else {
				logError("There is no registration. Finishing setting other reg primary...")
				completion(self.mmContext.resolveUser().installations, NSError(type: MMInternalErrorType.NoRegistration))
				return
			}
			let body = ["isPrimary": primary]
			mmContext.remoteApiProvider.patchOtherInstance(applicationCode: mmContext.applicationCode, authPushRegistrationId: authPushRegistrationId, pushRegistrationId: pushRegId, body: body) { (result) in
				switch result {
				case .Cancel :
					finish(NSError(type: MMInternalErrorType.UnknownError)) // cannot happen!
				default:
					finish(result.error)
				}
			}
		}
	}

	func depersonalizeInstallation(withPushRegistrationId pushRegId: String, completion: @escaping ([MMInstallation]?, NSError?) -> Void) {
		guard pushRegId != mmContext.currentInstallation().pushRegistrationId else {
			logError("Attempt to depersonalize current installation with inappropriate API. Aborting depersonalizing other oreg...")
			completion(mmContext.resolveUser().installations, NSError(type: MMInternalErrorType.CantLogoutCurrentRegistration))
			return
		}
		guard let authPushRegistrationId = mmContext.currentInstallation().pushRegistrationId else {
			logError("There is no registration. Finishing depersonalizing other reg...")
			completion(mmContext.resolveUser().installations, NSError(type: MMInternalErrorType.NoRegistration))
			return
		}

		mmContext.remoteApiProvider.depersonalize(applicationCode: mmContext.applicationCode, pushRegistrationId: authPushRegistrationId, pushRegistrationIdToDepersonalize: pushRegId) { (result) in

			if result.error == nil {
				let ins = self.resolveInstallationsAfterLogout(pushRegId)
				MMUser.modifyAll(with: { (user) in
					user.installations = ins
				})
			}
			completion(self.mmContext.resolveUser().installations, result.error)
		}
	}

	func save(userData: MMUser, completion: @escaping (NSError?) -> Void) {
		logDebug("saving \(userData.dictionaryRepresentation)")
		userData.archiveDirty()
		syncWithServer(completion)
	}

	var isChanged: Bool {
		return MMUser.delta != nil
	}

	func resolveInstallationsAfterPrimaryChange(_ pushRegId: String, _ isPrimary: Bool) -> [MMInstallation]? {
		let ret = mmContext.resolveUser().installations
		if let idx = ret?.firstIndex(where: { $0.isPrimaryDevice == true }) {
			ret?[idx].isPrimaryDevice = false
		}
		if let idx = ret?.firstIndex(where: { $0.pushRegistrationId == pushRegId }) {
			ret?[idx].isPrimaryDevice = isPrimary
		}
		return ret
	}

	func resolveInstallationsAfterLogout(_ pushRegId: String) -> [MMInstallation]? {
		var ret = mmContext.resolveUser().installations
		if let idx = ret?.firstIndex(where: { $0.pushRegistrationId == pushRegId }) {
			ret?.remove(at: idx)
		}
		return ret
	}

	func personalize(forceDepersonalize: Bool, userIdentity: MMUserIdentity, userAttributes: MMUserAttributes?, completion: @escaping (NSError?) -> Void) {

		let du = mmContext.dirtyUser()
		UserDataMapper.apply(userIdentity: userIdentity, to: du)
		if let userAttributes = userAttributes {
			UserDataMapper.apply(userAttributes: userAttributes, to: du)
		}
		du.archiveDirty()

		let op = PersonalizeOperation(
			forceDepersonalize: forceDepersonalize,
			userIdentity: userIdentity,
			userAttributes: userAttributes,
			mmContext: mmContext,
			finishBlock: { completion($0) })

		op.queuePriority = .veryHigh
		installationQueue.addOperation(op)

	}

	func fetchFromServer(completion: @escaping (MMUser, NSError?) -> Void) {
		logDebug("fetch from server")
		let op = FetchUserOperation(
			currentUser: mmContext.currentUser(),
			dirtyUser: mmContext.dirtyUser(),
			mmContext: mmContext,
			finishBlock: { completion(self.mmContext.resolveUser(), $0) })
		
		installationQueue.addOperation(op)
	}

	// MARK: - MobileMessagingService protocol {
	override func depersonalizeService(_ mmContext: MobileMessaging, completion: @escaping () -> Void) {
		logDebug("log out")
		MMUser.empty.archiveAll()
		completion()
	}

	override func appWillEnterForeground(_ n: Notification) {
		syncWithServer({_ in})
	}

	override func mobileMessagingDidStart(_ mmContext: MobileMessaging) {
		syncWithServer({_ in})
	}
    
    override func mobileMessagingWillStop(_ mmContext: MobileMessaging) {
        MMUser.cached.reset()
    }

	override func syncWithServer(_ completion: @escaping (NSError?) -> Void) {
		logDebug("sync user data with server")

		if let op = UpdateUserOperation(
			currentUser: mmContext.currentUser(),
			dirtyUser: mmContext.dirtyUser(),
			mmContext: mmContext,
			requireResponse: false,
			finishBlock: { completion($0) })
		{
			installationQueue.addOperation(op)
		} else {
			completion(nil)
		}
	}
	// MARK: }
}
