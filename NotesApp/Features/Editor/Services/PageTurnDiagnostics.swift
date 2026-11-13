import os

/// Local Instruments markers only. No note titles, ink, paths or telemetry leave the device.
enum PageTurnDiagnostics {
    static let signposter = OSSignposter(subsystem: "com.local.notesapp", category: "PageTurning")
}
