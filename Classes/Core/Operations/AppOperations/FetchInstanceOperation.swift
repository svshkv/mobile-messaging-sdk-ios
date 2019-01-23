//
//  FetchInstanceOperation.swift
//  MobileMessaging
//
//  Created by Andrey Kadochnikov on 09/11/2018.
//

import Foundation

class FetchInstanceOperation : Operation {
	let mmContext: MobileMessaging
	let installation: InstallationDataService
	let attributesSet: AttributesSet
	let finishBlock: ((FetchInstanceDataResult) -> Void)?
	var result: FetchInstanceDataResult = FetchInstanceDataResult.Cancel
	let pushRegistrationId: String

	init?(attributesSet: AttributesSet, installation: InstallationDataService, mmContext: MobileMessaging, finishBlock: ((FetchInstanceDataResult) -> Void)?) {
		self.installation = installation
		self.mmContext = mmContext
		self.finishBlock = finishBlock
		if attributesSet.isEmpty {
			MMLogDebug("[FetchInstanceOperation] There are no attributes to fetch. Aborting...")
			return nil
		} else {
			self.attributesSet = attributesSet
		}

		if let pushRegistrationId = installation.pushRegistrationId {
			self.pushRegistrationId = pushRegistrationId
		} else {
			MMLogDebug("[FetchInstanceOperation] There is no registration. Abortin...")
			return nil
		}
	}

	override func execute() {
		guard !isCancelled else {
			MMLogDebug("[FetchInstanceOperation] cancelled...")
			finish()
			return
		}
		MMLogDebug("[FetchInstanceOperation] started...")
		sendServerRequestIfNeeded()
	}

	private func sendServerRequestIfNeeded() {
		guard mmContext.apnsRegistrationManager.isRegistrationHealthy else {
			MMLogWarn("[FetchInstanceOperation] Registration is not healthy. Finishing...")
			finishWithError(NSError(type: MMInternalErrorType.InvalidRegistration))
			return
		}

		mmContext.remoteApiProvider.getInstance(applicationCode: mmContext.applicationCode, pushRegistrationId: pushRegistrationId) { (result) in
			self.handleResult(result)
			self.finishWithError(result.error)
		}
	}

	private func handleResult(_ result: FetchInstanceDataResult) {
		self.result = result
		guard !isCancelled else {
			MMLogDebug("[FetchInstanceOperation] cancelled.")
			return
		}
		switch result {
		case .Success(let response):
			//TODO: use apply Installation to InstallationService
			attributesSet.forEach { (att) in
				switch att {
				case .pushRegistrationId:
					installation.pushRegistrationId = response.pushRegistrationId
				case .applicationUserId:
					installation.applicationUserId = response.applicationUserId
				case .registrationEnabled:
					installation.isPushRegistrationEnabled = response.isPushRegistrationEnabled
				case .isPrimaryDevice:
					installation.isPrimaryDevice = response.isPrimaryDevice
				case .customInstanceAttributes:
					installation.customAttributes = response.customAttributes
				case .systemDataHash:
					installation.systemDataHash = Int64(MobileMessaging.userAgent.systemData.hashValue)
				case .customInstanceAttribute(key: _),.applicationCode,.badgeNumber,.birthday,.customUserAttribute(key: _),.customUserAttributes,.pushServiceToken,.emails,.externalUserId,.firstName,.gender,.phones,.instances,.lastName,.location,.depersonalizeFailCounter,.depersonalizeStatusValue,.middleName,.tags:
					break
				}
			}
			installation.persist()
			installation.resetNeedToSync(attributesSet: attributesSet)
			installation.persist()
			MMLogDebug("[FetchInstanceOperation] successfully synced")
		case .Failure(let error):
			MMLogError("[FetchInstanceOperation] sync request failed with error: \(error.orNil)")
		case .Cancel:
			MMLogWarn("[FetchInstanceOperation] sync request cancelled.")
		}
	}

	override func finished(_ errors: [NSError]) {
		MMLogDebug("[FetchInstanceOperation] finished with errors: \(errors)")
		finishBlock?(result) //check what to do with errors/
	}
}