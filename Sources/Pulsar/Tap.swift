import AudioToolbox
import Foundation
import OSLog

typealias PCMFrameHandler = (UnsafePointer<Float>, Int, Int) -> Void

final class SystemAudioTap {
    private let log = Logger(subsystem: "io.pulsar.audio", category: "Tap")

    private var processTapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioDeviceID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private var handlerBox: HandlerBox?

    private(set) var streamDescription: AudioStreamBasicDescription?
    var sampleRate: Double { streamDescription?.mSampleRate ?? 0 }
    var channelCount: Int { Int(streamDescription?.mChannelsPerFrame ?? 0) }

    private final class HandlerBox {
        let handler: PCMFrameHandler
        let channels: Int
        var rawCount = 0
        init(_ handler: @escaping PCMFrameHandler, channels: Int) {
            self.handler = handler
            self.channels = channels
        }
    }

    func start(_ handler: @escaping PCMFrameHandler) throws {
        // Every throw past a successful AudioHardware*Create call must
        // destroy the resource, otherwise coreaudiod keeps the half-built
        // tap or aggregate around until the next reboot. Track success
        // explicitly and only suppress cleanup once the full chain is wired.
        var success = false
        defer {
            if !success {
                if let p = deviceProcID, aggregateDeviceID.isValid {
                    AudioDeviceStop(aggregateDeviceID, p)
                    AudioDeviceDestroyIOProcID(aggregateDeviceID, p)
                    deviceProcID = nil
                }
                if aggregateDeviceID.isValid {
                    AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
                    aggregateDeviceID = .unknown
                }
                if processTapID.isValid {
                    AudioHardwareDestroyProcessTap(processTapID)
                    processTapID = .unknown
                }
                handlerBox = nil
            }
        }

        // Build tap description. For a system-wide ("global") tap with no
        // process exclusions we use the default constructor + property mutation
        // (matches audiotee, which is the reference for the global case —
        // AudioCap's `stereoMixdownOfProcesses:` constructor is per-process and
        // pairs with a different aggregate-device shape).
        let tapDesc = CATapDescription()
        tapDesc.name = "Pulsar"
        tapDesc.processes = []
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .unmuted
        tapDesc.isMixdown = true
        tapDesc.isMono = true
        tapDesc.isExclusive = true
        tapDesc.deviceUID = nil
        tapDesc.stream = 0

        var tapID: AudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        FileHandle.standardError.write(Data("tap create -> err=\(err) id=\(tapID)\n".utf8))
        guard err == noErr else { throw TapError.createTapFailed(err) }
        processTapID = tapID

        // Resolve the tap's UID via property (audiotee pattern). The UUID on
        // the description and the property-returned UID are not the same string
        // in macOS 15+, so query the live one.
        let tapUID: String = try tapID.readString(kAudioTapPropertyUID)
        streamDescription = try tapID.readAudioTapStreamBasicDescription()
        FileHandle.standardError.write(Data("tap uid=\(tapUID) sr=\(streamDescription?.mSampleRate ?? 0) ch=\(streamDescription?.mChannelsPerFrame ?? 0)\n".utf8))

        // Aggregate device — input-only for a global tap. The tap is attached
        // after creation via kAudioAggregateDevicePropertyTapList.
        let aggregateUID = UUID().uuidString
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Pulsar aggregate",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceSubDeviceListKey: [] as CFArray,
            kAudioAggregateDeviceMasterSubDeviceKey: 0,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]

        var aggID: AudioDeviceID = .unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggID)
        FileHandle.standardError.write(Data("aggregate create -> err=\(err) id=\(aggID)\n".utf8))
        guard err == noErr else { throw TapError.createAggregateFailed(err) }
        aggregateDeviceID = aggID

        // Attach tap to aggregate.
        var tapListAddr = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let tapArray: CFArray = [tapUID] as CFArray
        // The buffer is a single CFArrayRef (pointer-sized). Spell it as
        // UnsafeRawPointer.size so the intent is unambiguous; MemoryLayout
        // on the opaque CFArray placeholder type is implementation-defined.
        let arraySize = UInt32(MemoryLayout<UnsafeRawPointer>.size)
        err = withUnsafePointer(to: tapArray) { ptr in
            AudioObjectSetPropertyData(aggregateDeviceID, &tapListAddr, 0, nil, arraySize, ptr)
        }
        FileHandle.standardError.write(Data("attach tap -> err=\(err)\n".utf8))
        guard err == noErr else { throw TapError.createAggregateFailed(err) }

        // Poll for aggregate IsAlive before starting (audiotee pattern).
        for _ in 0..<50 {
            var alive: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let s = AudioObjectGetPropertyData(aggregateDeviceID, &addr, 0, nil, &size, &alive)
            if s == noErr && alive == 1 { break }
            Thread.sleep(forTimeInterval: 0.02)
        }

        // Read device format from the aggregate to lock channel count.
        var asbd = AudioStreamBasicDescription()
        var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectGetPropertyData(aggregateDeviceID, &fmtAddr, 0, nil, &sz, &asbd)
        if asbd.mChannelsPerFrame > 0 {
            streamDescription = asbd
        }
        let channels = Int(streamDescription?.mChannelsPerFrame ?? 1)
        FileHandle.standardError.write(Data("aggregate fmt sr=\(streamDescription?.mSampleRate ?? 0) ch=\(channels)\n".utf8))

        let box = HandlerBox(handler, channels: channels)
        handlerBox = box
        let boxPtr = Unmanaged.passUnretained(box).toOpaque()

        var procID: AudioDeviceIOProcID?
        err = AudioDeviceCreateIOProcID(
            aggregateDeviceID,
            { (_, _, inInputData, _, _, _, clientData) -> OSStatus in
                // RT context: no allocations, no Swift runtime calls that
                // can allocate, no locks held by non-RT threads. The
                // handler closure itself takes a lock — that's the only
                // permissible blocking, and the lock holder (main loop)
                // is bounded.
                guard let cd = clientData else { return noErr }
                let box = Unmanaged<HandlerBox>.fromOpaque(cd).takeUnretainedValue()
                box.rawCount &+= 1
                let abl = inInputData.pointee
                guard abl.mNumberBuffers > 0 else { return noErr }
                let buf = abl.mBuffers
                let byteSize = Int(buf.mDataByteSize)
                let chs = max(box.channels, 1)
                let frameCount = byteSize / (MemoryLayout<Float>.size * chs)
                guard let raw = buf.mData else { return noErr }
                let ptr = raw.assumingMemoryBound(to: Float.self)
                box.handler(ptr, frameCount, chs)
                return noErr
            },
            boxPtr,
            &procID
        )
        FileHandle.standardError.write(Data("ioProc create -> err=\(err)\n".utf8))
        guard err == noErr else { throw TapError.createIOProcFailed(err) }
        deviceProcID = procID

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        FileHandle.standardError.write(Data("device start -> err=\(err)\n".utf8))
        guard err == noErr else { throw TapError.startDeviceFailed(err) }
        success = true
        log.info("tap running")
    }

    func aggregateIsAlive() -> Bool {
        guard aggregateDeviceID.isValid else { return false }
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let s = AudioObjectGetPropertyData(aggregateDeviceID, &addr, 0, nil, &size, &alive)
        return s == noErr && alive == 1
    }

    func stop() {
        if aggregateDeviceID.isValid {
            if let p = deviceProcID {
                AudioDeviceStop(aggregateDeviceID, p)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, p)
                deviceProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .unknown
        }
        if processTapID.isValid {
            AudioHardwareDestroyProcessTap(processTapID)
            processTapID = .unknown
        }
    }

    deinit { stop() }
}
