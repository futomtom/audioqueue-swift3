

import Foundation
import UIKit
import AudioToolbox


/*
enum PlayerState: CustomStringConvertible {
    case Initialized
    case Starting
    case Playing
    case Paused
    case Error

    var description: String {
        switch self {
        case .Initialized: return "Initialized"
        case .Starting: return "Starting"
        case .Playing: return "Playing"
        case .Paused: return "Paused"
        case .Error: return "Error"
        }
    }
}


protocol PlayerInfoDelegate: class {
    func stateChangedForPlayerInfo(playerInfo: PlayerInfo)
}


class PlayerInfo {
    var dataFormat: AudioStreamBasicDescription?
    var audioQueue: AudioQueueRef?
    var totalPacketsReceived: UInt32 = 0
    var queueStarted: Bool = false
    weak var delegate: PlayerInfoDelegate?
    var state: PlayerState = .Initialized {
        didSet {
            if state != oldValue {
                delegate?.stateChangedForPlayerInfo(self)
            }
        }
    }
}
 */


extension AudioPlayer: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        print("hi")
        parseData(data)
    }
}

class AudioPlayer: NSObject {
    var fileURL: URL
    var dataTask: URLSessionDataTask?
    var fileStreamID: AudioFileStreamID? = nil
    var streamDescription: AudioStreamBasicDescription?
    var audioQueue: AudioQueueRef?
    var totalPacketsReceived: UInt32 = 0
    var queueStarted: Bool = false

    var packets = [Data]()

    var readHead: Int = 0
    var loaded = false
    //  var stopped = false
    var isRunning: UInt32 = 0

    fileprivate var streamPropertyListenerProc: AudioFileStream_PropertyListenerProc = { (clientData, audioFileStreamID, propertyID, ioFlags) -> Void in

        //    let player = Unmanaged<AudioPlayer>.fromOpaque(clientData).takeUnretainedValue()
        let this: AudioPlayer = unsafeBitCast(clientData, to: AudioPlayer.self)
        if propertyID == kAudioFileStreamProperty_DataFormat {
            var status: OSStatus = 0
            var dataSize: UInt32 = 0
            var writable: DarwinBoolean = false
            status = AudioFileStreamGetPropertyInfo(audioFileStreamID, kAudioFileStreamProperty_DataFormat, &dataSize, &writable)
            assert(noErr == status)
            var audioStreamDescription = AudioStreamBasicDescription()
            status = AudioFileStreamGetProperty(audioFileStreamID, kAudioFileStreamProperty_DataFormat, &dataSize, &audioStreamDescription)
            assert(noErr == status)
            DispatchQueue.main.async {
                this.createAudioQueue(audioStreamDescription) // use audioStreamDescription tp create AudioQueue
            }
        }
    }


    let streamPacketsProc: AudioFileStream_PacketsProc = { (clientData, numberBytes, numberPackets, inputData, packetDescriptions) -> Void in

        var err = noErr
        print ("streamPacketsProc got \(numberPackets) packets")
        let this: AudioPlayer = unsafeBitCast(clientData, to: AudioPlayer.self)

        var buffer: AudioQueueBufferRef? = nil
        if let audioQueue = this.audioQueue {
            err = AudioQueueAllocateBuffer(audioQueue,
                                           numberBytes,
                                           &buffer)
            print ("allocated buffer, err is \(err) buffer is \(buffer)")
            buffer?.pointee.mAudioDataByteSize = numberBytes
            memcpy(buffer?.pointee.mAudioData, inputData, Int(numberBytes))
            print ("copied data, not dead yet")

            err = AudioQueueEnqueueBuffer(audioQueue,
                                          buffer!,
                                          numberPackets,
                                          packetDescriptions)
            NSLog ("enqueued buffer, err is \(err)")

            this.totalPacketsReceived += numberPackets

            err = AudioQueueStart (audioQueue,
                                   nil)
            NSLog ("started playing, err is \(err)")
            this.isRunning = 1
        }
    }

    fileprivate var AudioQueuePropertyCallbackProc: AudioQueuePropertyListenerProc = { (inUserData: UnsafeMutableRawPointer?, inAQ: AudioQueueRef, inID: AudioQueuePropertyID) in
        let this = unsafeBitCast(inUserData, to: AudioPlayer.self)
        if inID == kAudioQueueProperty_IsRunning {
            var isRunning: UInt32 = 0
            var size: UInt32 = UInt32(MemoryLayout<UInt32>.size)
            AudioQueueGetProperty(inAQ, inID, &isRunning, &size)

            this.isRunning = isRunning
        }
    }


    init(url: URL) {
        self.fileURL = url
        super.init()

        let selfPointee = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        AudioFileStreamOpen(selfPointee, streamPropertyListenerProc, AudioFileStreamPacketsCallback, kAudioFileMP3Type, &self.fileStreamID)
    }

    func start() {
        isRunning = 1
        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        dataTask = urlSession.dataTask(with: fileURL)
        dataTask?.resume()
    }


    deinit {
        if self.audioQueue != nil {
            AudioQueueReset(audioQueue!)
        }
        AudioFileStreamClose(fileStreamID!)
    }

    var framePerSecond: Double {
        get {
            if let streamDescription = self.streamDescription, streamDescription.mFramesPerPacket > 0 {
                return Double(streamDescription.mSampleRate) / Double(streamDescription.mFramesPerPacket)
            }
            return 44100.0 / 1152.0
        }
    }

    func play() {
        if self.audioQueue == nil {
            return
        }

        AudioQueueStart(audioQueue!, nil)
    }
    func pause() {
        if self.audioQueue == nil {
        }

        AudioQueuePause(audioQueue!)
    }

    fileprivate func parseData(_ data: Data) {
        AudioFileStreamParseBytes(self.fileStreamID!, UInt32(data.count), (data as NSData).bytes, AudioFileStreamParseFlags(rawValue: 0))
    }


    fileprivate func createAudioQueue(_ audioStreamDescription: AudioStreamBasicDescription) {
        var audioStreamDescription = audioStreamDescription
        self.streamDescription = audioStreamDescription
        var status: OSStatus = 0
        let selfPointer = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        status = AudioQueueNewOutput(&audioStreamDescription, outputCallback, selfPointer, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue, 0, &self.audioQueue)
        assert(noErr == status)
        status = AudioQueueAddPropertyListener(self.audioQueue!, kAudioQueueProperty_IsRunning, AudioQueuePropertyCallbackProc, selfPointer)
        assert(noErr == status)
        AudioQueuePrime(self.audioQueue!, 0, nil)
        AudioQueueStart(self.audioQueue!, nil)
    }
    func storePackets(numberOfPackets: UInt32, numberOfBytes: UInt32, data: UnsafeRawPointer, packetDescription: UnsafeMutablePointer<AudioStreamPacketDescription>) {
        for i in 0 ..< Int(numberOfPackets) {
            let packetStart = packetDescription[i].mStartOffset
            let packetSize = packetDescription[i].mDataByteSize
            let packetData = NSData(bytes: data.advanced(by: Int(packetStart)), length: Int(packetSize))
            self.packets.append(packetData as Data)
        }
        if readHead == 0 && Double(packets.count) > self.framePerSecond * 3 {
            AudioQueueStart(self.audioQueue!, nil)
            self.enqueueDataWithPacketsCount(packetCount: Int(self.framePerSecond * 3))
        }
    }
    func enqueueDataWithPacketsCount(packetCount: Int) {
        if self.audioQueue == nil {
            return
        }
        var packetCount = packetCount
        if readHead + packetCount > packets.count {
            packetCount = packets.count - readHead
        }
        let totalSize = packets[readHead ..< readHead + packetCount].reduce(0, { $0 + $1.count })
        var status: OSStatus = 0
        var buffer: AudioQueueBufferRef? = nil
        status = AudioQueueAllocateBuffer(audioQueue!, UInt32(totalSize), &buffer)
        assert(noErr == status)
        buffer?.pointee.mAudioDataByteSize = UInt32(totalSize)
        let selfPointer = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        buffer?.pointee.mUserData = selfPointer
        var copiedSize = 0
        var packetDescs = [AudioStreamPacketDescription]()
        for i in 0 ..< packetCount {
            let readIndex = readHead + i
            let packetData = packets[readIndex]
            memcpy(buffer!.pointee.mAudioData.advanced(by: copiedSize), packetData.withUnsafeBytes { $0.pointee }, packetData.count)
            let description = AudioStreamPacketDescription(mStartOffset: Int64(copiedSize), mVariableFramesInPacket: 0, mDataByteSize: UInt32(packetData.count))
            packetDescs.append(description)
            copiedSize += packetData.count
        }
        print("enqueue")
        status = AudioQueueEnqueueBuffer(audioQueue!, buffer!, UInt32(packetCount), packetDescs);
        readHead += packetCount
    }

}

let streamPropertyListenerProc: AudioFileStream_PropertyListenerProc = { (clientData, audioFileStreamID, propertyID, ioFlags) -> Void in

    let player = Unmanaged<AudioPlayer>.fromOpaque(clientData).takeUnretainedValue()
    if propertyID == kAudioFileStreamProperty_DataFormat {
        var status: OSStatus = 0
        var dataSize: UInt32 = 0
        var writable: DarwinBoolean = false
        status = AudioFileStreamGetPropertyInfo(audioFileStreamID, kAudioFileStreamProperty_DataFormat, &dataSize, &writable)
        assert(noErr == status)
        var audioStreamDescription: AudioStreamBasicDescription = AudioStreamBasicDescription()
        status = AudioFileStreamGetProperty(audioFileStreamID, kAudioFileStreamProperty_DataFormat, &dataSize, &audioStreamDescription)
        assert(noErr == status)
        DispatchQueue.main.async {
            player.createAudioQueue(audioStreamDescription)
        }
    }
}

func AudioFileStreamPacketsCallback(_ clientData: UnsafeMutableRawPointer, numberBytes: UInt32, numberPackets: UInt32, ioData: UnsafeRawPointer, packetDescription: UnsafeMutablePointer<AudioStreamPacketDescription>) {

    let this = Unmanaged<AudioPlayer>.fromOpaque(clientData).takeUnretainedValue()
    this.storePackets(numberOfPackets: numberPackets, numberOfBytes: numberBytes, data: ioData, packetDescription: packetDescription)
}

fileprivate var outputCallback: AudioQueueOutputCallback = { (
                                                              clientData: UnsafeMutableRawPointer?,
                                                              inAQ: AudioQueueRef,
                                                              inBuffer: AudioQueueBufferRef) -> Void in
    let this = Unmanaged<AudioPlayer>.fromOpaque(clientData!).takeUnretainedValue()
    AudioQueueFreeBuffer(inAQ, inBuffer)
    this.enqueueDataWithPacketsCount(packetCount: Int(this.framePerSecond * 5))
}

/*
func AudioQueueOutputCallback(_ clientData: UnsafeMutableRawPointer, AQ: AudioQueueRef, buffer: AudioQueueBufferRef) {
    let this = Unmanaged<AudioPlayer>.fromOpaque(clientData).takeUnretainedValue()
    AudioQueueFreeBuffer(AQ, buffer)
    this.enqueueDataWithPacketsCount(packetCount: Int(this.framePerSecond * 5))
}*/



