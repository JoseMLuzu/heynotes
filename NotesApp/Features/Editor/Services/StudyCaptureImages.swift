import UIKit

actor StudyCaptureImages {
    static let shared = StudyCaptureImages()
    func store(snapshot: CapturedPage, question: CGRect, answer: CGRect, storage: DrawingStorage) async throws -> StudyCardImages {
        let front = try await PageCaptureService.shared.crop(snapshot.png, normalized: question)
        let back = try await PageCaptureService.shared.crop(snapshot.png, normalized: answer)
        let prefix = "Study/Images/\(UUID())"
        let questionPath = prefix + "/Question.png", answerPath = prefix + "/Answer.png"
        // A failed metadata save may retain these immutable bytes for recovery; no existing file is replaced.
        try await storage.write(front, to: questionPath); try await storage.write(back, to: answerPath)
        return StudyCardImages(question: questionPath, answer: answerPath)
    }
}
