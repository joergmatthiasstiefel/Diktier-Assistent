import AVFoundation
import Speech

/// Nimmt Audio auf, solange die Taste gehalten wird, und transkribiert es
/// on-device über SFSpeechRecognizer (de-DE).
final class SpeechTranscriber {
    enum TranscriberError: Error {
        case recognizerUnavailable
        case audioEngineFailure(Error)
        case recognitionFailure(Error)
        case emptyResult
    }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var completionHandler: ((Result<String, TranscriberError>) -> Void)?

    func startRecording() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriberError.recognizerUnavailable
        }

        latestTranscript = ""
        completionHandler = nil

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            request = nil
            throw TranscriberError.audioEngineFailure(error)
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.latestTranscript = result.bestTranscription.formattedString
                if result.isFinal {
                    self.finish(.success(self.latestTranscript))
                }
            }
            if let error {
                if !self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.finish(.success(self.latestTranscript))
                } else {
                    self.finish(.failure(.recognitionFailure(error)))
                }
            }
        }
    }

    func stopRecording(completion: @escaping (Result<String, TranscriberError>) -> Void) {
        completionHandler = completion
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    private func finish(_ result: Result<String, TranscriberError>) {
        guard let handler = completionHandler else { return }
        completionHandler = nil
        task = nil
        request = nil

        let finalResult: Result<String, TranscriberError>
        switch result {
        case .success(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            finalResult = trimmed.isEmpty ? .failure(.emptyResult) : .success(trimmed)
        case .failure(let error):
            finalResult = .failure(error)
        }

        DispatchQueue.main.async { handler(finalResult) }
    }
}
