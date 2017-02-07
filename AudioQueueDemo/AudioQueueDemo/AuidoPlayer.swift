import Foundation
import AudioToolbox

enum AudioPlayerState {
    case playing
    case paused
    case stopped
}


class AudioPlayer: NSObject {

    var dataTask: URLSessionDataTask?
    var fileStreamID: AudioFileStreamID? = nil
    var streamDescription: AudioStreamBasicDescription?
    var audioQueue: AudioQueueRef?
    var fileURL: URL
    var isRunning: UInt32 = 0
    var state: AudioPlayerState = .stopped


    fileprivate var streamPropertyListenerProc: AudioFileStream_PropertyListenerProc = { (clientData, audioFileStreamID, propertyID, ioFlags) -> Void in

        let selfPointee: AudioPlayer = unsafeBitCast(clientData, to: AudioPlayer.self)
        //let selfPointee = Unmanaged<AudioPlayer>.fromOpaque(clientData).takeUnretainedValue()
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

        let selfPointee: AudioPlayer = unsafeBitCast(clientData, to: AudioPlayer.self)
  //      print("numberBytes = \(numberBytes),numberPackets = \(numberPackets)")
        var buffer: AudioQueueBufferRef? = nil
        if let audioQueue = selfPointee.audioQueue {
            AudioQueueAllocateBuffer(audioQueue, numberBytes, &buffer)
            buffer?.pointee.mAudioDataByteSize = numberBytes
            memcpy(buffer?.pointee.mAudioData, inputData, Int(numberBytes)) //copied to buffer
            AudioQueueEnqueueBuffer(audioQueue, buffer!, numberPackets, packetDescriptions)
            AudioQueuePrime(audioQueue, 5, nil)
            AudioQueueStart (audioQueue, nil)
            //selfPointee.isRunning = 1
        }
    }

    fileprivate var AudioQueuePropertyCallbackProc: AudioQueuePropertyListenerProc = { (clientData, audioQueueRef, propertyID) in
        let selfPointee = unsafeBitCast(clientData, to: AudioPlayer.self)
        if propertyID == kAudioQueueProperty_IsRunning {
            var isRunning: UInt32 = 0
            var size: UInt32 = UInt32(MemoryLayout<UInt32>.size)
            AudioQueueGetProperty(audioQueueRef, propertyID, &isRunning, &size)
            selfPointee.isRunning = isRunning
        }
    }

    fileprivate var outputCallback: AudioQueueOutputCallback = { (clientData: UnsafeMutableRawPointer?, audioQueue: AudioQueueRef, buffer: AudioQueueBufferRef) -> Void in
        let selfPointee = Unmanaged<AudioPlayer>.fromOpaque(clientData!).takeUnretainedValue()
        AudioQueueFreeBuffer(audioQueue, buffer)
    }

    var volume: Float = 3.0 {
        didSet {
            if let audioQueue = audioQueue {
                AudioQueueSetParameter(audioQueue, AudioQueueParameterID(kAudioQueueParam_Volume), Float32(volume))
            }
        }
    }

    init(url: URL) {
        fileURL = url
        super.init()
        let selfPointee = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        AudioFileStreamOpen(selfPointee, streamPropertyListenerProc, streamPacketsProc, kAudioFileMP3Type, &self.fileStreamID)
        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        dataTask = urlSession.dataTask(with: fileURL)
        
    }

    deinit {
        if let audioQueue = audioQueue {
            AudioQueueReset(audioQueue)
        }
        AudioFileStreamClose(fileStreamID!)
    }


    func play() {
        dataTask?.resume()
    }
    func pause() {
        if state != .paused {
            dataTask?.suspend()
        }

        if let audioQueue = audioQueue {
            let status = AudioQueuePause(audioQueue)
            if status != noErr {
                print("=====  Pause failed: \(status)")
            }
        }
    }

    fileprivate func createAudioQueue(_ audioStreamDescription: AudioStreamBasicDescription) {
        var audioStreamDescription = audioStreamDescription
        self.streamDescription = audioStreamDescription
        var status: OSStatus = 0
        let selfPointee = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)
        status = AudioQueueNewOutput(&audioStreamDescription, outputCallback, selfPointee, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue, 0, &self.audioQueue)
        assert(status == noErr)
        status = AudioQueueAddPropertyListener(self.audioQueue!, kAudioQueueProperty_IsRunning, AudioQueuePropertyCallbackProc, selfPointee)
        assert(status == noErr)
     //   AudioQueuePrime(self.audioQueue!, 6, nil)
        AudioQueueStart(audioQueue!, nil)

    }
}

extension AudioPlayer: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var parseFlags: AudioFileStreamParseFlags
        if state == .paused { //paused
               parseFlags = .discontinuity
        } else {
            parseFlags = AudioFileStreamParseFlags(rawValue: 0)
            AudioFileStreamParseBytes(self.fileStreamID!, UInt32(data.count), (data as NSData).bytes, parseFlags)
        }


    }
}



