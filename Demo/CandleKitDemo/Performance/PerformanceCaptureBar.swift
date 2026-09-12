import CandleKit
import SwiftUI
import UIKit

/// Records a timed window of chart work and hands back a markdown table to paste into
/// `docs/PERFORMANCE.md`.
///
/// The point is to stop guessing. Start a capture, do one thing (pan, fling, pinch) for ten
/// seconds, stop, copy, paste. Each row names the device, the dataset and the interaction, so rows
/// from different sessions are actually comparable.
struct PerformanceCaptureBar: View {
    /// Included in the report heading so a pasted table says what it was measuring.
    let scenario: String
    let candleCount: Int

    @State private var isCapturing = false
    @State private var report: String?
    @State private var showsReport = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                isCapturing ? stop() : start()
            } label: {
                Label(
                    isCapturing ? "Stop capture" : "Capture",
                    systemImage: isCapturing ? "stop.circle.fill" : "record.circle"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(isCapturing ? .red : .accentColor)
            .controlSize(.small)

            if isCapturing {
                Text("Recording — pan, fling and pinch now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if report != nil {
                Button("View report") { showsReport = true }
                    .font(.caption)
            }

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showsReport) {
            PerformanceReportSheet(report: report ?? "")
        }
    }

    private func start() {
        ChartPerformance.setEnabled(true)
        ChartPerformance.reset()
        isCapturing = true
    }

    private func stop() {
        report = ChartPerformance.report(scenario: "\(scenario) · \(candleCount.formatted()) candles · \(Self.deviceDescription)")
        // Turn instrumentation back off so the numbers from the next capture aren't polluted by
        // idle frames, and so the app isn't paying for measurement it isn't using.
        ChartPerformance.setEnabled(false)
        isCapturing = false
        showsReport = true
    }

    /// Model identifier plus OS version. `UIDevice.name` is deliberately not used — it's often the
    /// owner's real name, and these reports get pasted into a public repository.
    private static var deviceDescription: String {
        var info = utsname()
        uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        let version = UIDevice.current.systemVersion
        #if targetEnvironment(simulator)
        return "Simulator (\(model)) · iOS \(version) — NOT REPRESENTATIVE"
        #else
        return "\(model) · iOS \(version)"
        #endif
    }
}

private struct PerformanceReportSheet: View {
    let report: String
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Performance report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = report
                        didCopy = true
                    }
                }
            }
        }
    }
}
