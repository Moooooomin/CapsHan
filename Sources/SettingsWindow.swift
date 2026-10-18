import Cocoa
import SwiftUI

/// The settings window, opened by clicking the app (Apps / Launchpad / Finder) or from
/// the menu bar icon. Built with the system SwiftUI form, so on macOS 26 it gets the
/// Liquid Glass look automatically.
final class SettingsWindow {
    private var window: NSWindow?
    private let preview: () -> Void

    init(preview: @escaping () -> Void) {
        self.preview = preview
    }

    func show() {
        if window == nil {
            // Fits the screen; the form scrolls when it is taller than this.
            let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
            let height = min(760, screenHeight - 80)
            let hosting = NSHostingController(rootView: SettingsView(preview: preview, height: height))
            let window = NSWindow(contentViewController: hosting)
            window.title = "CapsHan 설정"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 480, height: height))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    let preview: () -> Void
    let height: CGFloat

    @AppStorage(Settings.Key.showHUD) private var showHUD = true
    @AppStorage(Settings.Key.hudDuration) private var duration = 0.8
    @AppStorage(Settings.Key.hudFade) private var fade = true
    @AppStorage(Settings.Key.hudFadeDuration) private var fadeDuration = 0.3
    @AppStorage(Settings.Key.hudTheme) private var theme = HUDTheme.system
    @AppStorage(Settings.Key.hudStyle) private var style = HUDStyle.liquidGlass
    @AppStorage(Settings.Key.glassStyle) private var glassStyle = GlassStyle.clear
    @AppStorage(Settings.Key.liquidStrength) private var liquidStrength = 0.8
    @AppStorage(Settings.Key.hudScale) private var hudScale = 1.0
    @AppStorage(Settings.Key.capsLockSwitch) private var capsLockSwitch = true
    @AppStorage(Settings.Key.menuBarIcon) private var menuBarIcon = MenuBarIconStyle.hanYeong
    @AppStorage(Settings.Key.hideSystemInputMenu) private var hideSystemInputMenu = false
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CapsHan").font(.title2.weight(.semibold))
                        Text("Caps Lock으로 한/영을 바로 바꾸고, 바뀔 때마다 화면 아래에 입력 언어를 보여 줘요.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("한/영이 바뀌면 팝업 표시", isOn: $showHUD)

                Group {
                    sliderRow("표시 시간", value: $duration, in: Settings.durationRange, step: 0.1,
                              label: String(format: "%.1f초", duration)) { editing in
                        if !editing { preview() }
                    }

                    Toggle("페이드 인/아웃", isOn: $fade)

                    sliderRow("페이드 시간", value: $fadeDuration, in: Settings.fadeDurationRange, step: 0.1,
                              label: String(format: "%.1f초", fadeDuration)) { editing in
                        if !editing { preview() }
                    }
                    .disabled(!fade)

                    sliderRow("팝업 크기", value: $hudScale, in: Settings.hudScaleRange, step: 0.1,
                              label: "\(Int((hudScale * 100).rounded()))%")

                    Picker("테마", selection: $theme) {
                        Text("시스템 설정").tag(HUDTheme.system)
                        Text("라이트").tag(HUDTheme.light)
                        Text("다크").tag(HUDTheme.dark)
                    }
                    .pickerStyle(.segmented)

                    Picker("디자인", selection: $style) {
                        Text("리퀴드 글래스").tag(HUDStyle.liquidGlass)
                        Text("클래식").tag(HUDStyle.classic)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!Settings.isLiquidGlassAvailable)

                    if style == .liquidGlass && Settings.isLiquidGlassAvailable {
                        Picker("유리 질감", selection: $glassStyle) {
                            Text("반투명").tag(GlassStyle.regular)
                            Text("맑은 유리").tag(GlassStyle.clear)
                        }
                        .pickerStyle(.segmented)

                        sliderRow("리퀴드 강도", value: $liquidStrength, in: Settings.liquidStrengthRange, step: 0.05,
                                  label: "\(Int((liquidStrength * 100).rounded()))%")
                    }

                    HStack {
                        Spacer()
                        Button("팝업 미리보기", action: preview)
                    }
                }
                .disabled(!showHUD)
            } header: {
                Text("전환 팝업")
            } footer: {
                Text(footerText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("메뉴 막대") {
                Picker("아이콘", selection: $menuBarIcon) {
                    Text("한 / 영").tag(MenuBarIconStyle.hanYeong)
                    Text("한 / A").tag(MenuBarIconStyle.hanA)
                    Text("키보드").tag(MenuBarIconStyle.keyboard)
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $hideSystemInputMenu) {
                    Text("macOS 기본 입력 메뉴 숨기기")
                    Text("메뉴 막대의 기본 한/A 아이콘을 숨겨요. 입력 소스는 CapsHan 아이콘 메뉴에서도 고를 수 있고, CapsHan을 종료하면 다시 보여요.")
                }
            }

            Section("키보드") {
                Toggle(isOn: $capsLockSwitch) {
                    Text("Caps Lock으로 한/영 전환")
                    Text("끄면 Caps Lock과 '이전 입력 소스 선택' 단축키가 원래대로 돌아가요.")
                }
            }

            Section("일반") {
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { launchAtLogin },
                    set: { LoginItem.setEnabled($0); launchAtLogin = LoginItem.isEnabled }
                ))
            }

            Section {
                HStack {
                    Text("버전 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("CapsHan 종료") { quitCapsHan() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: height)
        .onChange(of: theme) { _ in preview() }
        .onChange(of: style) { _ in preview() }
        .onChange(of: glassStyle) { _ in preview() }
        .onChange(of: fade) { _ in preview() }
        // Live preview while dragging: the popup stays up and follows the slider.
        .onChange(of: liquidStrength) { _ in preview() }
        .onChange(of: hudScale) { _ in preview() }
        .onChange(of: capsLockSwitch) { enabled in
            enabled ? CapsLockSwitch.enable() : CapsLockSwitch.disable()
        }
        .onChange(of: hideSystemInputMenu) { hide in
            SystemInputMenu.setVisible(!hide)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // The user may have changed the login item in System Settings meanwhile.
            launchAtLogin = LoginItem.isEnabled
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                           step: Double, label: String,
                           onEditingChanged: @escaping (Bool) -> Void = { _ in }) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: step, onEditingChanged: onEditingChanged)
                    .frame(width: 180)
                Text(label)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private var footerText: String {
        var text = "테마를 '시스템 설정'으로 두면 다크 모드를 켜고 끌 때 팝업도 함께 바뀌어요."
        if Settings.isLiquidGlassAvailable {
            text += " 리퀴드 느낌은 '맑은 유리'에 강도를 높일수록, 팝업이 클수록 진해져요. 강도를 낮추면 유리가 뿌옇게 돼요."
        } else {
            text += " 리퀴드 글래스는 macOS 26 이상에서 쓸 수 있어요."
        }
        return text
    }
}
