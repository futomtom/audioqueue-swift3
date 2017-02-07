import Foundation
import AudioToolbox




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
        AudioFileStreamOpen(selfPointee, streamPropertyListenerProc, streamPacketsProc, kAudioFileMP3Type, &self.fileStreamID)
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

fileprivate var outputCallback: AudioQueueOutputCallback = { (clientData: UnsafeMutableRawPointer?, audioQueue: AudioQueueRef, buffer: AudioQueueBufferRef) -> Void in
    let this = Unmanaged<AudioPlayer>.fromOpaque(clientData!).takeUnretainedValue()
    AudioQueueFreeBuffer(audioQueue, buffer)
    this.enqueueDataWithPacketsCount(packetCount: Int(this.framePerSecond * 5))
}

extension AudioPlayer: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        AudioFileStreamParseBytes(self.fileStreamID!, UInt32(data.count), (data as NSData).bytes, AudioFileStreamParseFlags(rawValue: 0))
    }
}



