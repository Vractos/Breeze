/// LG ThinQ Connect error codes (`error.code`, always a string on the wire).
/// Named cases follow the official Python SDK; anything else is `.unknown`.
public enum ThinQErrorCode: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    case badRequest                         // 1000
    case missingParameters                  // 1101
    case unacceptableParameters             // 1102
    case invalidToken                       // 1103
    case invalidMessageID                   // 1104
    case notRegisteredAdmin                 // 1201
    case notRegisteredUser                  // 1202
    case notRegisteredService               // 1203
    case notSubscribedEvent                 // 1204
    case notExistDevice                     // 1205
    case notSubscribedPush                  // 1206
    case alreadySubscribedPush              // 1207
    case notRegisteredServiceByAdmin        // 1208
    case notRegisteredUserInService         // 1209
    case notRegisteredDeviceInService       // 1210
    case notRegisteredDeviceByUser          // 1211
    case notOwnedDevice                     // 1212
    case notRegisteredDevice                // 1213
    case notSubscribableDevice              // 1214
    case incorrectHeader                    // 1216
    case alreadyDeviceDeleted               // 1217
    case invalidTokenAgain                  // 1218
    case notSupportedModel                  // 1219
    case notSupportedFeature                // 1220
    case notSupportedProduct                // 1221
    case notConnectedDevice                 // 1222
    case invalidStatusDevice                // 1223
    case invalidDeviceID                    // 1224
    case duplicateDeviceID                  // 1225
    case invalidServiceKey                  // 1301
    case notFoundToken                      // 1302
    case notFoundUser                       // 1303
    case notAcceptableTerms                 // 1304
    case notAllowedAPI                      // 1305
    case exceededAPICalls                   // 1306
    case notSupportedCountry                // 1307
    case noControlAuthority                 // 1308
    case notAllowedAPIAgain                 // 1309
    case notSupportedDomain                 // 1310
    case badRequestFormat                   // 1311
    case exceededNumberOfEventSubscription  // 1312
    case internalServerError                // 2000
    case notSupportedModelAgain             // 2101
    case notProvidedFeature                 // 2201
    case notSupportedProductAgain           // 2202
    case notExistentModelJSON               // 2203
    case invalidDeviceStatus                // 2205
    case invalidCommandError                // 2207
    case failDeviceControl                  // 2208
    case deviceResponseDelay                // 2209
    case retryRequest                       // 2210
    case syncing                            // 2212
    case retryAfterDeletingDevice           // 2213
    case failRequest                        // 2214
    case commandNotSupportedInRemoteOff     // 2301
    case commandNotSupportedInState         // 2302
    case commandNotSupportedInError         // 2303
    case commandNotSupportedInPowerOff      // 2304
    case commandNotSupportedInMode          // 2305
    case unknown(String)

    /// Every named case, used to build the reverse lookup.
    public static let allNamed: [ThinQErrorCode] = [
        .badRequest, .missingParameters, .unacceptableParameters, .invalidToken, .invalidMessageID,
        .notRegisteredAdmin, .notRegisteredUser, .notRegisteredService, .notSubscribedEvent,
        .notExistDevice, .notSubscribedPush, .alreadySubscribedPush, .notRegisteredServiceByAdmin,
        .notRegisteredUserInService, .notRegisteredDeviceInService, .notRegisteredDeviceByUser,
        .notOwnedDevice, .notRegisteredDevice, .notSubscribableDevice, .incorrectHeader,
        .alreadyDeviceDeleted, .invalidTokenAgain, .notSupportedModel, .notSupportedFeature,
        .notSupportedProduct, .notConnectedDevice, .invalidStatusDevice, .invalidDeviceID,
        .duplicateDeviceID, .invalidServiceKey, .notFoundToken, .notFoundUser, .notAcceptableTerms,
        .notAllowedAPI, .exceededAPICalls, .notSupportedCountry, .noControlAuthority,
        .notAllowedAPIAgain, .notSupportedDomain, .badRequestFormat,
        .exceededNumberOfEventSubscription, .internalServerError, .notSupportedModelAgain,
        .notProvidedFeature, .notSupportedProductAgain, .notExistentModelJSON, .invalidDeviceStatus,
        .invalidCommandError, .failDeviceControl, .deviceResponseDelay, .retryRequest, .syncing,
        .retryAfterDeletingDevice, .failRequest, .commandNotSupportedInRemoteOff,
        .commandNotSupportedInState, .commandNotSupportedInError, .commandNotSupportedInPowerOff,
        .commandNotSupportedInMode,
    ]

    private static let byRawValue: [String: ThinQErrorCode] = Dictionary(
        allNamed.map { ($0.rawValue, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Never fails: unrecognised codes become `.unknown(rawValue)`.
    public init(rawValue: String) {
        self = Self.byRawValue[rawValue] ?? .unknown(rawValue)
    }

    public var rawValue: String {
        codeAndName.code
    }

    /// LG's symbolic name, e.g. `NOT_CONNECTED_DEVICE`; `UNKNOWN` for unrecognised codes.
    public var name: String {
        codeAndName.name
    }

    public var description: String {
        "\(rawValue) \(name)"
    }

    private var codeAndName: (code: String, name: String) {
        switch self {
        case .badRequest: ("1000", "BAD_REQUEST")
        case .missingParameters: ("1101", "MISSING_PARAMETERS")
        case .unacceptableParameters: ("1102", "UNACCEPTABLE_PARAMETERS")
        case .invalidToken: ("1103", "INVALID_TOKEN")
        case .invalidMessageID: ("1104", "INVALID_MESSAGE_ID")
        case .notRegisteredAdmin: ("1201", "NOT_REGISTERED_ADMIN")
        case .notRegisteredUser: ("1202", "NOT_REGISTERED_USER")
        case .notRegisteredService: ("1203", "NOT_REGISTERED_SERVICE")
        case .notSubscribedEvent: ("1204", "NOT_SUBSCRIBED_EVENT")
        case .notExistDevice: ("1205", "NOT_EXIST_DEVICE")
        case .notSubscribedPush: ("1206", "NOT_SUBSCRIBED_PUSH")
        case .alreadySubscribedPush: ("1207", "ALREADY_SUBSCRIBED_PUSH")
        case .notRegisteredServiceByAdmin: ("1208", "NOT_REGISTERED_SERVICE_BY_ADMIN")
        case .notRegisteredUserInService: ("1209", "NOT_REGISTERED_USER_IN_SERVICE")
        case .notRegisteredDeviceInService: ("1210", "NOT_REGISTERED_DEVICE_IN_SERVICE")
        case .notRegisteredDeviceByUser: ("1211", "NOT_REGISTERED_DEVICE_BY_USER")
        case .notOwnedDevice: ("1212", "NOT_OWNED_DEVICE")
        case .notRegisteredDevice: ("1213", "NOT_REGISTERED_DEVICE")
        case .notSubscribableDevice: ("1214", "NOT_SUBSCRIBABLE_DEVICE")
        case .incorrectHeader: ("1216", "INCORRECT_HEADER")
        case .alreadyDeviceDeleted: ("1217", "ALREADY_DEVICE_DELETED")
        case .invalidTokenAgain: ("1218", "INVALID_TOKEN_AGAIN")
        case .notSupportedModel: ("1219", "NOT_SUPPORTED_MODEL")
        case .notSupportedFeature: ("1220", "NOT_SUPPORTED_FEATURE")
        case .notSupportedProduct: ("1221", "NOT_SUPPORTED_PRODUCT")
        case .notConnectedDevice: ("1222", "NOT_CONNECTED_DEVICE")
        case .invalidStatusDevice: ("1223", "INVALID_STATUS_DEVICE")
        case .invalidDeviceID: ("1224", "INVALID_DEVICE_ID")
        case .duplicateDeviceID: ("1225", "DUPLICATE_DEVICE_ID")
        case .invalidServiceKey: ("1301", "INVALID_SERVICE_KEY")
        case .notFoundToken: ("1302", "NOT_FOUND_TOKEN")
        case .notFoundUser: ("1303", "NOT_FOUND_USER")
        case .notAcceptableTerms: ("1304", "NOT_ACCEPTABLE_TERMS")
        case .notAllowedAPI: ("1305", "NOT_ALLOWED_API")
        case .exceededAPICalls: ("1306", "EXCEEDED_API_CALLS")
        case .notSupportedCountry: ("1307", "NOT_SUPPORTED_COUNTRY")
        case .noControlAuthority: ("1308", "NO_CONTROL_AUTHORITY")
        case .notAllowedAPIAgain: ("1309", "NOT_ALLOWED_API_AGAIN")
        case .notSupportedDomain: ("1310", "NOT_SUPPORTED_DOMAIN")
        case .badRequestFormat: ("1311", "BAD_REQUEST_FORMAT")
        case .exceededNumberOfEventSubscription: ("1312", "EXCEEDED_NUMBER_OF_EVENT_SUBSCRIPTION")
        case .internalServerError: ("2000", "INTERNAL_SERVER_ERROR")
        case .notSupportedModelAgain: ("2101", "NOT_SUPPORTED_MODEL_AGAIN")
        case .notProvidedFeature: ("2201", "NOT_PROVIDED_FEATURE")
        case .notSupportedProductAgain: ("2202", "NOT_SUPPORTED_PRODUCT_AGAIN")
        case .notExistentModelJSON: ("2203", "NOT_EXISTENT_MODEL_JSON")
        case .invalidDeviceStatus: ("2205", "INVALID_DEVICE_STATUS")
        case .invalidCommandError: ("2207", "INVALID_COMMAND_ERROR")
        case .failDeviceControl: ("2208", "FAIL_DEVICE_CONTROL")
        case .deviceResponseDelay: ("2209", "DEVICE_RESPONSE_DELAY")
        case .retryRequest: ("2210", "RETRY_REQUEST")
        case .syncing: ("2212", "SYNCING")
        case .retryAfterDeletingDevice: ("2213", "RETRY_AFTER_DELETING_DEVICE")
        case .failRequest: ("2214", "FAIL_REQUEST")
        case .commandNotSupportedInRemoteOff: ("2301", "COMMAND_NOT_SUPPORTED_IN_REMOTE_OFF")
        case .commandNotSupportedInState: ("2302", "COMMAND_NOT_SUPPORTED_IN_STATE")
        case .commandNotSupportedInError: ("2303", "COMMAND_NOT_SUPPORTED_IN_ERROR")
        case .commandNotSupportedInPowerOff: ("2304", "COMMAND_NOT_SUPPORTED_IN_POWER_OFF")
        case .commandNotSupportedInMode: ("2305", "COMMAND_NOT_SUPPORTED_IN_MODE")
        case .unknown(let code): (code, "UNKNOWN")
        }
    }
}
