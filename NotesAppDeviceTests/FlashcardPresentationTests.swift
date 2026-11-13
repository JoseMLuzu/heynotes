import XCTest
import SwiftUI
import SwiftData
@testable import NotesApp

@MainActor final class FlashcardPresentationTests: XCTestCase {
    func testRevealKeepsFlipCardAndSkipFramesStableAcrossWindowsAndLongContent() async throws {
      for mode in [StudyReviewMode.scheduled, .practice] {
        for size in [CGSize(width: 820, height: 1180), CGSize(width: 1180, height: 820), CGSize(width: 540, height: 820)] {
            let container = try PersistenceController.makeContainer(inMemory: true)
            let model = StudyViewModel(container: container)
            let deck = try model.saveDeck(title: "Biología · Repaso", notebookID: nil)
            let first = try model.saveCard(deckID: deck.id, question: "¿Cuál es la función de las mitocondrias?",
                                          answer: "Producir ATP mediante la respiración celular.", source: nil)
            let second = try model.saveCard(deckID: deck.id, question: String(repeating: "A longer question. ", count: 30),
                                           answer: String(repeating: "A longer explanation. ", count: 45), source: nil)
            let session = StudyReviewSession(cards: [first, second], mode: mode)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene); window.frame = CGRect(origin: .zero, size: size)
            let bounds = ReviewBoundsCapture()
            let host = UIHostingController(rootView: MeasuredReview(model: model, session: session, bounds: bounds))
            window.rootViewController = host; window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            host.view.frame = window.bounds; try await settle(host.view)
            let before = try frames(in: bounds)
            capture(window, name: "Refined-Question-\(mode)-\(Int(size.width))")
            session.flip()
            try await settle(host.view)
            XCTAssertTrue(session.isAnswerVisible)
            assertStable(before, try frames(in: bounds))
            capture(window, name: "Refined-Answer-\(mode)-\(Int(size.width))")
            session.flip()
            try await settle(host.view)
            XCTAssertFalse(session.isAnswerVisible)
            assertStable(before, try frames(in: bounds))
            session.flip()
            try await settle(host.view)
            if session.isPractice { try session.advancePractice(model: model) }
            else { try session.rate(.good, model: model) }
            try await settle(host.view)
            XCTAssertEqual(session.index, 1); XCTAssertFalse(session.isAnswerVisible)
            XCTAssertEqual(first.reviews.count, session.isPractice ? 0 : 1)
            assertStable(before, try frames(in: bounds))
            withExtendedLifetime(container) {}
        }
      }
    }

    private func frames(in capture: ReviewBoundsCapture) throws -> [String: CGRect] {
        for id in ["study.flip", "study.card", "study.skip"] {
            let frame = try XCTUnwrap(capture.frames[id], "Missing native bounds for \(id)")
            XCTAssertGreaterThan(frame.width, 0); XCTAssertGreaterThan(frame.height, 0)
        }
        return capture.frames
    }
    private func assertStable(_ before: [String: CGRect], _ after: [String: CGRect], file: StaticString = #filePath, line: UInt = #line) {
        for (name, frame) in before {
            guard let other = after[name] else { XCTFail("Missing \(name)", file: file, line: line); continue }
            XCTAssertEqual(frame.minY, other.minY, accuracy: 0.5, name, file: file, line: line)
            XCTAssertEqual(frame.height, other.height, accuracy: 0.5, name, file: file, line: line)
            XCTAssertEqual(frame.minX, other.minX, accuracy: 0.5, name, file: file, line: line)
            XCTAssertEqual(frame.width, other.width, accuracy: 0.5, name, file: file, line: line)
        }
    }
    private func settle(_ view: UIView) async throws {
        view.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(360)); view.layoutIfNeeded()
    }
    private func capture(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}


@MainActor private final class ReviewBoundsCapture {
    var frames: [String: CGRect] = [:]
}

@MainActor private struct MeasuredReview: View {
    let model: StudyViewModel
    let session: StudyReviewSession
    let bounds: ReviewBoundsCapture
    var body: some View {
        StudyReviewView(model: model, session: session) { _ in }
            .tint(AppTheme.accent)
            .overlayPreferenceValue(StudyReviewAnchors.self) { anchors in
                GeometryReader { geometry in
                    let frames = anchors.mapValues { geometry[$0] }
                    Color.clear.allowsHitTesting(false)
                        .onAppear { bounds.frames = frames }
                        .onChange(of: frames) { _, value in bounds.frames = value }
                }
            }
    }
}
