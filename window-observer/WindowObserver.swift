import ArgumentParser
import Foundation
import ScreenCaptureKit
import Vision

struct Result: Codable {
    var windows: [Window]
}

struct Window: Codable {
    let id: CGWindowID
    let pid: pid_t?
    let name: String?
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let observations: [Observation]?
}

struct Observation: Codable {
    let string: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

@main
struct Command: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "window-observer",
        abstract: "Recognize text from on-screen windows.",
    )

    @Option(help: "The window ID of the window to observe.")
    var id: CGWindowID?

    @Option(help: "The process ID of the application to observe.")
    var pid: pid_t?

    @Option(help: "The name of the application to observe.")
    var name: String?

    @Flag(inversion: .prefixedNo, help: "Capture windows and recognize text.")
    var capture: Bool = true

    mutating func run() async throws {
        let sharable = try await SCShareableContent.current
        var result = Result(windows: [])

        for window in sharable.windows {
            if window.isOnScreen
                && (id == nil || id == window.windowID)
                && (pid == nil || pid == window.owningApplication?.processID)
                && (name == nil || name == window.owningApplication?.applicationName)
            {
                var observations: [Observation]? = nil

                if capture {
                    observations = try! await getWindowObservations(window: window)
                }

                result.windows.append(
                    Window(
                        id: window.windowID,
                        pid: window.owningApplication?.processID,
                        name: window.owningApplication?.applicationName,
                        x: Int(window.frame.minX),
                        y: Int(window.frame.minY),
                        width: Int(window.frame.width),
                        height: Int(window.frame.height),
                        observations: observations,
                    )
                )
            }
        }

        print(String(data: try! JSONEncoder().encode(result), encoding: .utf8)!)
    }

    func getWindowObservations(window: SCWindow) async throws -> [Observation] {
        let image = try await SCScreenshotManager.captureImage(in: window.frame)
        let request = RecognizeTextRequest()
        let observations = try await request.perform(on: image)
        var results: [Observation] = []

        for observation in observations {
            let text = observation.topCandidates(1).first!
            let box = text.boundingBox(for: text.string.startIndex..<text.string.endIndex)!

            results.append(
                Observation(
                    string: text.string,
                    x: Int(window.frame.width * box.topLeft.x),
                    y: Int(window.frame.height * (1 - box.topLeft.y)),
                    width: Int(window.frame.width * box.boundingBox.width),
                    height: Int(window.frame.height * box.boundingBox.height),
                )
            )
        }

        return results
    }
}
