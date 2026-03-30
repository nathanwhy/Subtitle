import AVFoundation
import CoreMedia
import ScreenCaptureKit

enum SystemAudioCaptureError: LocalizedError {
    case noDisplayAvailable
    case sampleConversionFailed

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display is available for system-audio capture."
        case .sampleConversionFailed:
            return "Failed to convert captured system audio into PCM data."
        }
    }
}

final class SystemAudioCapture: NSObject {
    private let sampleHandlerQueue = DispatchQueue(label: "subtitle.capture.audio")
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private let onError: @Sendable (Error) -> Void
    private var stream: SCStream?

    init(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.onBuffer = onBuffer
        self.onError = onError
    }

    func start() async throws {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = shareableContent.displays.first else {
            throw SystemAudioCaptureError.noDisplayAvailable
        }

        let excludedApplications = shareableContent.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 3
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleHandlerQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }
}

extension SystemAudioCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else {
            return
        }

        do {
            let pcmBuffer = try sampleBuffer.makePCMBuffer()
            onBuffer(pcmBuffer)
        } catch {
            onError(error)
        }
    }
}

extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onError(error)
    }
}

private extension CMSampleBuffer {
    func makePCMBuffer() throws -> AVAudioPCMBuffer {
        guard
            let formatDescription = CMSampleBufferGetFormatDescription(self),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            throw SystemAudioCaptureError.sampleConversionFailed
        }

        var audioStreamDescription = streamDescription.pointee
        guard let format = AVAudioFormat(streamDescription: &audioStreamDescription) else {
            throw SystemAudioCaptureError.sampleConversionFailed
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw SystemAudioCaptureError.sampleConversionFailed
        }

        pcmBuffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )

        guard status == noErr else {
            throw SystemAudioCaptureError.sampleConversionFailed
        }

        return pcmBuffer
    }
}
