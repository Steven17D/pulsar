import AudioToolbox
import Foundation

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown

    var isUnknown: Bool { self == .unknown }
    var isValid: Bool { !isUnknown }
}

extension AudioObjectID {
    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try AudioDeviceID.system.readDefaultSystemOutputDevice()
    }

    func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try requireSystemObject()
        return try read(kAudioHardwarePropertyDefaultSystemOutputDevice, defaultValue: AudioDeviceID.unknown)
    }

    func readDeviceUID() throws -> String { try readString(kAudioDevicePropertyDeviceUID) }

    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }

    private func requireSystemObject() throws {
        if self != .system { throw TapError.notSystemObject }
    }
}

extension AudioObjectID {
    func read<T>(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                 defaultValue: T) throws -> T
    {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element),
                 defaultValue: defaultValue)
    }

    func readString(_ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> String
    {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element),
                 defaultValue: "" as CFString) as String
    }

    private func read<T>(_ inAddress: AudioObjectPropertyAddress, defaultValue: T) throws -> T {
        var address = inAddress
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr else { throw TapError.propertyRead(code: err, address: address) }
        var value: T = defaultValue
        err = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, ptr)
        }
        guard err == noErr else { throw TapError.propertyRead(code: err, address: address) }
        return value
    }
}

enum TapError: Error, CustomStringConvertible {
    case notSystemObject
    case propertyRead(code: OSStatus, address: AudioObjectPropertyAddress)
    case createTapFailed(OSStatus)
    case createAggregateFailed(OSStatus)
    case createIOProcFailed(OSStatus)
    case startDeviceFailed(OSStatus)

    var description: String {
        switch self {
        case .notSystemObject: return "operation requires system AudioObject"
        case .propertyRead(let c, let a): return "AudioObjectGetPropertyData(\(a.mSelector))=\(c)"
        case .createTapFailed(let c): return "AudioHardwareCreateProcessTap=\(c)"
        case .createAggregateFailed(let c): return "AudioHardwareCreateAggregateDevice=\(c)"
        case .createIOProcFailed(let c): return "AudioDeviceCreateIOProcIDWithBlock=\(c)"
        case .startDeviceFailed(let c): return "AudioDeviceStart=\(c)"
        }
    }
}
