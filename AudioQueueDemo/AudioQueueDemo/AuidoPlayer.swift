import Foundation
import AudioToolbox

class AudioPlayer: NSObject {
  	
    var dataTask: URLSessionDataTask?
    var fileStreamID: AudioFileStreamID? = nil
    var streamDescription: AudioStreamBasicDescription?
    var audioQueue: AudioQueueRef?
    var totalPacketsReceived: UInt32 = 0
    var queueStarted: Bool = false
    var fileURL: URL


    var packets = [Data]()

    var readHead: Int = 0
    var loaded = false
    var isRunning: UInt32 = 0

    fileprivate var streamPropertyListenerProc: AudioFileStream_PropertyListenerProc = { (clientData, audioFileStreamID, propertyID, ioFlags) -> Void in

        let selfPointee: AudioPlayer = unsafeBitCast(clientData, to: AudioPlayer.self)
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
                selfPointee.createAudioQueue(audioStreamDescription)
            }
        }
    }


    let streamPacketsProc: AudioFileStream_PacketsProc = { (clientData, numberBytes, numberPackets, inputData, packetDescriptions) -> Void in

        var err = noErr
        let selfPointee: AudioPlayer = unsafeBitCast(clientData, to: AudioPlayer.self)

        var buffer: AudioQueueBufferRef? = nil
        if let audioQueue = selfPointee.audioQueue {
            err = AudioQueueAllocateBuffer(audioQueue,numberBytes,&buffer)
            buffer?.pointee.mAudioDataByteSize = numberBytes
            memcpy(buffer?.pointee.mAudioData, inputData, Int(numberBytes))             //copied to buffer
             print("2")
            err = AudioQueueEnqueueBuffer(audioQueue,buffer!,numberPackets,packetDescriptions)
            selfPointee.totalPacketsReceived += numberPackets
            err = AudioQueueStart (audioQueue,nil)
            selfPointee.isRunning = 1
        }
    }

    fileprivate var AudioQueuePropertyCallbackProc: AudioQueuePropertyListenerProc = { (clientData, audioQueueRef , propertyID) in
        let selfPointee = unsafeBitCast(clientData, to: AudioPlayer.self)
        if propertyID == kAudioQueueProperty_IsRunning {
            var isRunning: UInt32 = 0
            var size: UInt32 = UInt32(MemoryLayout<UInt32>.size)
            AudioQueueGetProperty(audioQueueRef, propertyID, &isRunning, &size)

            selfPointee.isRunning = isRunning
        }
    }


    init(url: URL) {
        fileURL = url
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
        guard audioQueue != nil else {
            return
        }
        AudioQueueStart(audioQueue!, nil)
    }
    func pause() {
        guard audioQueue != nil else {
            return
        }
        print("p")
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
    let selfPointee = Unmanaged<AudioPlayer>.fromOpaque(clientData!).takeUnretainedValue()
    AudioQueueFreeBuffer(audioQueue, buffer)
}

extension AudioPlayer: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        AudioFileStreamParseBytes(self.fileStreamID!, UInt32(data.count), (data as NSData).bytes, AudioFileStreamParseFlags(rawValue: 0))
    }
}



