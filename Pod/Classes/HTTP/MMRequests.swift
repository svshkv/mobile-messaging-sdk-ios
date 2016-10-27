//
//  MMRequests.swift
//  MobileMessaging
//
//  Created by Andrey K. on 23/02/16.
//
//

typealias RequestBody = [String: Any]
typealias RequestParameters = [String: Any]
typealias RequestHeaders = [String: String]

enum MMHTTPRequestError: Error {
	case EmptyDeviceToken
	case IncorrectApplicationCode
}

enum MMHTTPMethod {
	case POST
	case PUT
	case GET
}

enum MMHTTPAPIPath: String {
	case Registration = "/mobile/2/registration"
	case SeenMessages = "/mobile/1/messages/seen"
	case SyncMessages = "/mobile/3/messages"
	case UserData = "/mobile/3/data/user"
	case MOMessage = "/mobile/1/messages/mo"
	case SystemData = "/mobile/1/data/system"
	case LibraryVersion = "/mobile/3/version"
	case GeoEventsReports = "/mobile/3/geo/event"
}

protocol MMHTTPRequestResponsable {
	associatedtype ResponseType: JSONDecodable
	func responseObject(applicationCode: String, baseURL: String, completion: @escaping (Result<ResponseType>) -> Void)
}

protocol MMHTTPRequestData: MMHTTPRequestResponsable {
	var method: MMHTTPMethod {get}
	var path: MMHTTPAPIPath {get}
	var parameters: RequestParameters? {get}
	var headers: RequestHeaders? {get}
	var retryLimit: Int {get}
	var body: RequestBody? {get}
}

protocol MMHTTPGetRequest: MMHTTPRequestData { }
extension MMHTTPGetRequest {
	var method: MMHTTPMethod { return .GET }
}

protocol MMHTTPPostRequest: MMHTTPRequestData { }
extension MMHTTPPostRequest {
	var method: MMHTTPMethod { return .POST }
}

extension MMHTTPRequestData {
	var retryLimit: Int { return 0 }
	var headers: RequestHeaders? { return nil }
	var body: RequestBody? { return nil }
	var parameters: RequestParameters? { return nil }
	func responseObject(applicationCode: String, baseURL: String, completion: @escaping (Result<ResponseType>) -> Void) {
		let manager = MM_AFHTTPSessionManager(baseURL: URL(string: baseURL), sessionConfiguration: URLSessionConfiguration.default)
		manager.requestSerializer = MMHTTPRequestSerializer(applicationCode: applicationCode, jsonBody: body, headers: headers)
		manager.responseSerializer = MMResponseSerializer<ResponseType>()
		
		MMLogDebug("Sending request \(type(of: self))\nparameters: \(parameters)\nbody: \(body)\nto \(baseURL + path.rawValue)")
		
		let successBlock = { (task: URLSessionDataTask, obj: Any?) -> Void in
			if let obj = obj as? ResponseType {
				completion(Result.Success(obj))
			} else {
                let error = NSError(domain: AFURLResponseSerializationErrorDomain, code: NSURLErrorCannotDecodeContentData, userInfo:[NSLocalizedFailureReasonErrorKey : "Request succeeded with no return value or return value wasn't a ResponseType value."])
				completion(Result.Failure(error))
			}
		}
		
		let failureBlock = { (task: URLSessionDataTask?, error: Error) -> Void in
			completion(Result<ResponseType>.Failure(error as NSError?))
		}
		
		let urlString = manager.baseURL!.absoluteString + self.path.rawValue
		switch self.method {
		case .POST:
			manager.post(urlString, parameters: parameters, progress: nil, success: successBlock, failure: failureBlock)
		case .PUT:
			manager.put(urlString, parameters: parameters, success: successBlock, failure: failureBlock)
		case .GET:
			manager.get(urlString, parameters: parameters, progress: nil, success: successBlock, failure: failureBlock)
		}
	}
}

struct MMPostRegistrationRequest: MMHTTPPostRequest {
	typealias ResponseType = MMHTTPRegistrationResponse
	
	var retryLimit: Int { return 3 }
	var path: MMHTTPAPIPath { return .Registration }
	var parameters: RequestParameters? {
		var params = [MMAPIKeys.kRegistrationId: currentDeviceToken,
		              MMAPIKeys.kPlatformType: MMAPIValues.kPlatformType]
		params[MMAPIKeys.kInternalRegistrationId] = internalId
		return params
	}
	let currentDeviceToken: String
	let internalId: String?
	
	init(internalId: String?, deviceToken: String) {
		self.internalId = internalId
		self.currentDeviceToken = deviceToken
	}
}

extension Date {
	var timestampDelta: UInt {
		return UInt(max(0, Date().timeIntervalSinceReferenceDate - self.timeIntervalSinceReferenceDate))
	}
}

struct SeenData: DictionaryRepresentable {
	let messageId: String
	let seenDate: Date
	init(messageId: String, seenDate: Date) {
		self.messageId = messageId
		self.seenDate = seenDate
	}
	init?(dictRepresentation dict: DictionaryRepresentation) {
		return nil // unused
	}
	var dictionaryRepresentation: DictionaryRepresentation {
		return [MMAPIKeys.kMessageId: messageId,
		        MMAPIKeys.kSeenTimestampDelta: seenDate.timestampDelta]
	}
	static func requestBody(seenList: [SeenData]) -> RequestBody {
		return [MMAPIKeys.kSeenMessages: seenList.map{ $0.dictionaryRepresentation } ]
	}
}

struct MMPostSeenMessagesRequest: MMHTTPPostRequest {
	typealias ResponseType = MMHTTPSeenMessagesResponse
	
	var path: MMHTTPAPIPath { return .SeenMessages }
	var parameters: RequestParameters? { return nil }
	let seenList: [SeenData]
	var body: RequestBody? { return SeenData.requestBody(seenList: seenList) }
	
	init(seenList: [SeenData]) {
		self.seenList = seenList
	}
}

struct MMGetLibraryVersionRequest: MMHTTPGetRequest {
	typealias ResponseType = MMHTTPLibraryVersionResponse

	var path: MMHTTPAPIPath { return .LibraryVersion }
	var parameters: [String: Any]? = [MMAPIKeys.kPlatformType: MMAPIValues.kPlatformType]

	init() {
	}
}

struct MMPostSyncRequest: MMHTTPPostRequest {

	typealias ResponseType = MMHTTPSyncMessagesResponse
	var path: MMHTTPAPIPath { return .SyncMessages }
	var parameters: RequestParameters? {
		var params = RequestParameters()
		params[MMAPIKeys.kInternalRegistrationId] = internalId
		params[MMAPIKeys.kPlatformType] = MMAPIValues.kPlatformType
		return params
	}
	
	let internalId: String
	let archiveMsgIds: [String]?
	let dlrMsgIds: [String]?

	var body: RequestBody? {
		var result = RequestBody()
		result[MMAPIKeys.kArchiveMsgIds] = (archiveMsgIds?.isEmpty ?? true) ? nil : archiveMsgIds
		result[MMAPIKeys.kDLRMsgIds] = (dlrMsgIds?.isEmpty ?? true) ? nil : dlrMsgIds
		return result
	}
	
	init(internalId: String, archiveMsgIds: [String]?, dlrMsgIds: [String]?) {
		self.internalId = internalId
		self.archiveMsgIds = archiveMsgIds
		self.dlrMsgIds = dlrMsgIds
	}
}

struct MMPostUserDataRequest: MMHTTPPostRequest {
	typealias ResponseType = MMHTTPUserDataSyncResponse
	typealias UserDataDictionary = [String: Any]
	var path: MMHTTPAPIPath { return .UserData }
	var parameters: RequestParameters? {
		var params = [MMAPIKeys.kInternalRegistrationId: internalUserId]
		if let externalUserId = externalUserId {
			params[MMAPIKeys.kUserDataExternalUserId] = externalUserId
		}
		return params
	}
	var body: RequestBody? {
		var result = RequestBody()
		result[MMAPIKeys.kUserDataPredefinedUserData] = predefinedUserData ?? UserDataDictionary()
		if let customUserData = customUserData {
			result[MMAPIKeys.kUserDataCustomUserData] = customUserData.reduce(UserDataDictionary(), { (result, element) -> UserDataDictionary in
				return result + element.dictionaryRepresentation
			})
		} else {
			result[MMAPIKeys.kUserDataCustomUserData] = UserDataDictionary()
		}
		return result
	}
	
	let internalUserId: String
	let externalUserId: String?
	let predefinedUserData: UserDataDictionary?
	let customUserData: [CustomUserData]?
	
	init(internalUserId: String, externalUserId: String?, predefinedUserData: UserDataDictionary? = nil, customUserData: [String: CustomUserDataValue]? = nil) {
		self.internalUserId = internalUserId
		self.externalUserId = externalUserId
		self.predefinedUserData = predefinedUserData
		if let customUserData = customUserData {
			self.customUserData = customUserData.map{ CustomUserData(dataKey: $0.0, dataValue: $0.1.dataValue) }
		} else {
			self.customUserData = nil
		}
	}
}

struct MMPostSystemDataRequest: MMHTTPPostRequest {
	typealias ResponseType = MMHTTPSystemDataSyncResponse
	var path: MMHTTPAPIPath { return .SystemData }
	var parameters: RequestParameters? {
		return [MMAPIKeys.kInternalRegistrationId: internalUserId]
	}
	var body: RequestBody? {
		return systemData.dictionaryRepresentation
	}
	
	let internalUserId: String
	let systemData: MMSystemData
	
	init(internalUserId: String, systemData: MMSystemData) {
		self.internalUserId = internalUserId
		self.systemData = systemData
	}
}

struct MMPostMessageRequest: MMHTTPPostRequest {

	typealias ResponseType = MMHTTPMOMessageResponse
	var path: MMHTTPAPIPath { return .MOMessage }
	var parameters: RequestParameters? {
		return [MMAPIKeys.kPlatformType : MMAPIValues.kPlatformType]
	}
	var body: RequestBody? {
		var result = RequestBody()
		result[MMAPIKeys.kMOFrom] = internalUserId
		result[MMAPIKeys.kMOMessages] = messages.map { msg -> RequestBody in
			var dict = msg.dictRepresentation
			dict[MMAPIKeys.kMOMessageSentStatusCode] = nil // this attribute is redundant, the Mobile API would not expect it.
			return dict
		}
		return result
	}
	
	let internalUserId: String
	let messages: [MOMessage]
	
	init?(internalUserId: String, messages: [MOMessage]) {
		guard !messages.isEmpty else {
			return nil
		}
		self.internalUserId = internalUserId
		self.messages = messages
	}
}

struct GeoEventReportData: DictionaryRepresentable {
	let campaignId: String
	let eventDate: Date
	let geoAreaId: String
	let messageId: String
	let eventType: MMRegionEventType
	
	init(geoAreaId: String, eventType: MMRegionEventType, campaignId: String, eventDate: Date, messageId: String) {
		self.campaignId = campaignId
		self.eventDate = eventDate
		self.geoAreaId = geoAreaId
		self.eventType = eventType
		self.messageId = messageId
	}
	
	init?(dictRepresentation dict: DictionaryRepresentation) {
		return nil // unused
	}
	
	var dictionaryRepresentation: DictionaryRepresentation {
		return [GeoReportingAPIKeys.campaignId: campaignId,
		        GeoReportingAPIKeys.timestampDelta: eventDate.timestampDelta,
		        GeoReportingAPIKeys.geoAreaId: geoAreaId,
		        GeoReportingAPIKeys.event: eventType.rawValue,
		        GeoReportingAPIKeys.messageId: messageId
				]
	}
	
	static func requestBody(reportList: [GeoEventReportData]) -> RequestBody {
		return [GeoReportingAPIKeys.reports: reportList.map{ $0.dictionaryRepresentation } ]
	}
}

struct MMGeoEventsReportingRequest: MMHTTPPostRequest {
	typealias ResponseType = MMHTTPGeoEventReportingResponse
	
	var path: MMHTTPAPIPath { return .GeoEventsReports }
	var parameters: RequestParameters? { return nil }
	let eventsDataList: [GeoEventReportData]
	var body: RequestBody? { return GeoEventReportData.requestBody(reportList: eventsDataList) }
	
	init?(eventsDataList: [GeoEventReportData]) {
		guard !eventsDataList.isEmpty else {
			return nil
		}
		self.eventsDataList = eventsDataList
	}
}
