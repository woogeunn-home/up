import AppKit
import Darwin
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct UpSettingsView: View {
    @EnvironmentObject private var monitor: ActivityMonitor
    @Environment(\.dismiss) private var dismiss
    var onPinPopover: ((Bool) -> Void)?
    var onBack: (() -> Void)?
    @State private var selectedMinutes = 60.0
    @State private var minuteInput = "60"
    @State private var isUpdatingMinuteInput = false
    @State private var selectedResetMinutes = 5.0
    @State private var resetMinuteInput = "5"
    @State private var isUpdatingResetInput = false
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    if let onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .help("Made by w")
            }

            HStack(spacing: 16) {
                Text("전체 시간")
                Spacer()

                Stepper {
                    minuteInputField
                } onIncrement: {
                    selectedMinutes = nextSteppedMinutes(from: selectedMinutes)
                    applySelectedMinutes()
                } onDecrement: {
                    selectedMinutes = previousSteppedMinutes(from: selectedMinutes)
                    applySelectedMinutes()
                }
                .controlSize(.small)
            }

            HStack(spacing: 16) {
                Text("일어난 시간")
                Spacer()

                Stepper {
                    resetMinuteInputField
                } onIncrement: {
                    selectedResetMinutes = min(selectedResetMinutes + 1, 60)
                    applySelectedResetMinutes()
                } onDecrement: {
                    selectedResetMinutes = max(selectedResetMinutes - 1, 1)
                    applySelectedResetMinutes()
                }
                .controlSize(.small)
            }

            HStack(spacing: 12) {
                Text("도형 이미지")
                Spacer()

                if let image = monitor.customShapeImage {
                    Button {
                        monitor.customShapeImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("기본 이미지로 되돌리기")

                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                } else {
                    Image("ShapeIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                }

                Button("변경") {
                    pickShapeImage()
                }
                .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                )) {
                    Text("컴퓨터 시작시 자동 실행")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button(role: .destructive) {
                quitApp()
            } label: {
                Label("앱 종료하기", systemImage: "power")
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(16)
        .frame(width: MenuBarContent.contentWidth)
        .onAppear {
            selectedMinutes = monitor.targetSeconds / 60
            setMinuteInput(minuteDisplay(selectedMinutes))
            selectedResetMinutes = monitor.inactivityResetSeconds / 60
            setResetInput(minuteDisplay(selectedResetMinutes))
            refreshLaunchAtLogin()
        }
    }

    private var minimumMinutes: Double {
        ActivityMonitor.minimumTargetSeconds / 60
    }

    private var resetMinuteInputField: some View {
        HStack(spacing: 4) {
            TextField("분", text: $resetMinuteInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onSubmit {
                    applyResetMinuteInput()
                }
                .onChange(of: resetMinuteInput) { _, newValue in
                    guard !isUpdatingResetInput else { return }
                    let filtered = decimalMinuteInput(from: newValue)
                    if filtered != newValue {
                        setResetInput(filtered)
                        return
                    }
                    if let minutes = Double(filtered), minutes >= 1 {
                        selectedResetMinutes = min(minutes, 60)
                        monitor.inactivityResetSeconds = selectedResetMinutes * 60
                    }
                }

            Text("분")
                .foregroundStyle(.secondary)
        }
    }

    private var minuteInputField: some View {
        HStack(spacing: 4) {
            TextField("분", text: $minuteInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onSubmit {
                    applyMinuteInput()
                }
                .onChange(of: minuteInput) { _, newValue in
                    guard !isUpdatingMinuteInput else { return }
                    let filtered = decimalMinuteInput(from: newValue)
                    if filtered != newValue {
                        setMinuteInput(filtered)
                        return
                    }

                    if let minutes = Double(filtered), minutes >= minimumMinutes {
                        selectedMinutes = min(minutes, 240)
                        monitor.targetSeconds = selectedMinutes * 60
                    }
                }

            Text("분")
                .foregroundStyle(.secondary)
        }
    }

    private func pickShapeImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        onPinPopover?(true)
        let response = panel.runModal()
        onPinPopover?(false)
        guard response == .OK, let url = panel.url else { return }
        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            monitor.customShapeImage = NSImage(contentsOf: url)
        }
    }

    private func quitApp() {
        NSApplication.shared.sendAction(#selector(NSApplication.terminate(_:)), to: nil, from: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            exit(EXIT_SUCCESS)
        }
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }

            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "자동 실행 설정을 변경하지 못했습니다."
        }

        refreshLaunchAtLogin()
    }

    private func nextSteppedMinutes(from minutes: Double) -> Double {
        if minutes < 10 {
            return 10
        }

        return min((floor(minutes / 10) + 1) * 10, 240)
    }

    private func previousSteppedMinutes(from minutes: Double) -> Double {
        if minutes <= 10 {
            return minimumMinutes
        }

        return max((ceil(minutes / 10) - 1) * 10, minimumMinutes)
    }

    private func applySelectedMinutes() {
        selectedMinutes = min(max(selectedMinutes, minimumMinutes), 240)
        setMinuteInput(minuteDisplay(selectedMinutes))
        monitor.targetSeconds = selectedMinutes * 60
    }

    private func applySelectedResetMinutes() {
        selectedResetMinutes = min(max(selectedResetMinutes, 1), 60)
        setResetInput(minuteDisplay(selectedResetMinutes))
        monitor.inactivityResetSeconds = selectedResetMinutes * 60
    }

    private func applyResetMinuteInput() {
        let minutes = Double(resetMinuteInput) ?? selectedResetMinutes
        selectedResetMinutes = min(max(minutes, 1), 60)
        applySelectedResetMinutes()
    }

    private func setResetInput(_ value: String) {
        isUpdatingResetInput = true
        resetMinuteInput = value
        isUpdatingResetInput = false
    }

    private func applyMinuteInput() {
        let minutes = Double(minuteInput) ?? selectedMinutes
        selectedMinutes = min(max(minutes, minimumMinutes), 240)
        applySelectedMinutes()
    }

    private func setMinuteInput(_ value: String) {
        isUpdatingMinuteInput = true
        minuteInput = value
        isUpdatingMinuteInput = false
    }

    private func minuteDisplay(_ minutes: Double) -> String {
        if minutes.rounded() == minutes {
            return "\(Int(minutes))"
        }

        return String(format: "%.2f", minutes)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private func decimalMinuteInput(from text: String) -> String {
        var result = ""
        var hasDecimalPoint = false

        for character in text {
            if character.isNumber {
                result.append(character)
            } else if character == ".", !hasDecimalPoint {
                result.append(character)
                hasDecimalPoint = true
            }
        }

        return result
    }
}
