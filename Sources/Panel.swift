import SwiftUI

private let lilac = Color(red: 0.49, green: 0.40, blue: 0.78)
private let mint = Color(red: 0.23, green: 0.53, blue: 0.43)

struct LockMascot: View {
    var awake = true
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(lilac.opacity(0.10))
                .frame(width: 78, height: 78)
            RoundedRectangle(cornerRadius: 15)
                .stroke(lilac, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 30, height: 35).offset(y: -14)
            RoundedRectangle(cornerRadius: 13)
                .fill(LinearGradient(colors: [Color(red: 0.73, green: 0.65, blue: 0.95), lilac],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 51, height: 40).offset(y: 12)
            HStack(spacing: 13) {
                ForEach(0..<2) { _ in
                    if awake { Capsule().fill(.white).frame(width: 3.5, height: 6) }
                    else { Capsule().fill(.white).frame(width: 7, height: 2.5) }
                }
            }.offset(y: 9)
            Path { path in
                path.move(to: CGPoint(x: 34, y: 57))
                path.addQuadCurve(to: CGPoint(x: 44, y: 57), control: CGPoint(x: 39, y: 63))
            }.stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
            Image(systemName: "sparkle").font(.system(size: 13, weight: .medium))
                .foregroundStyle(lilac).offset(x: 34, y: -28)
        }.frame(width: 78, height: 78).accessibilityHidden(true)
    }
}

struct TimerChip: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity).frame(height: 34)
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
            .background(selected ? lilac : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.045),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? lilac : Color.primary.opacity(0.06)))
    }
}

struct AwakePanel: View {
    @ObservedObject var state: PanelState
    var toggle: () -> Void
    var start: (Double) -> Void
    var custom: () -> Void
    var lid: () -> Void
    var lock: () -> Void
    var login: () -> Void
    var about: () -> Void
    var quit: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var background: Color {
        scheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.15) : Color(red: 0.985, green: 0.977, blue: 0.963)
    }
    private var card: Color { scheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.85) }
    private var lidDetail: String {
        if state.installing { return "Setting up secure helper…" }
        if !state.helperInstalled { return "One-time administrator setup" }
        if state.helperActive { return "Active · charger connected" }
        if state.closedLid && !state.ac { return "Ready · waiting for your charger" }
        if state.closedLid && state.active { return "Waiting for helper confirmation" }
        return "Available while plugged into power"
    }

    var body: some View {
        VStack(spacing: 17) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Awake Lock").font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("A little guard for big ideas.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("About Awake Lock", action: about)
                    Divider()
                    Button("Quit Awake Lock", action: quit)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, height: 28)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("More options")
            }

            HStack(spacing: 17) {
                LockMascot(awake: state.active)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 5) {
                        Circle().fill(state.active ? mint : Color.secondary).frame(width: 5, height: 5)
                        Text(state.active ? "ON DUTY" : "OFF DUTY")
                            .font(.system(size: 9, weight: .bold)).tracking(1.5)
                            .foregroundStyle(state.active ? mint : .secondary)
                    }
                    Text(state.active ? "Your Mac is awake." : "Rest when you’re ready.")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    if state.active, let deadline = state.deadline {
                        HStack(spacing: 5) {
                            Image(systemName: "timer")
                            Text(deadline, style: .timer).monospacedDigit()
                            Text("left").foregroundStyle(.secondary)
                        }.font(.system(size: 12, weight: .medium)).foregroundStyle(lilac)
                    } else {
                        Text(state.active ? "Until you say goodnight." : "Normal sleep is allowed.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(lilac.opacity(scheme == .dark ? 0.10 : 0.055), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(lilac.opacity(0.12)))

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "sun.max").font(.system(size: 17)).foregroundStyle(lilac).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keep Mac awake").font(.system(size: 13, weight: .semibold))
                        Text("Screen off. Ideas still on.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Keep Mac awake", isOn: Binding(get: { state.enabled }, set: { _ in toggle() }))
                        .labelsHidden().toggleStyle(.switch).tint(lilac).controlSize(.small)
                }.padding(14)
                Divider().padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("SESSION LENGTH").font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundStyle(.secondary)
                        Spacer()
                        Text("Starts immediately").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 6) {
                        chip("30 min", 30)
                        chip("1 hour", 60)
                        chip("2 hours", 120)
                        chip("4 hours", 240)
                    }
                    HStack(spacing: 6) {
                        Button { start(0) } label: {
                            Label("Until turned off", systemImage: "infinity")
                        }.buttonStyle(TimerChip(selected: state.active && state.deadline == nil))
                        Button(action: custom) { Label("Custom", systemImage: "slider.horizontal.3") }
                            .buttonStyle(TimerChip(selected: false))
                    }
                }.padding(14)
            }.background(card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.065)))

            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer").font(.system(size: 18)).foregroundStyle(lilac).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Closed-lid mode").font(.system(size: 12.5, weight: .semibold))
                        Text("AC ONLY").font(.system(size: 7.5, weight: .bold)).tracking(0.5)
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(lilac.opacity(0.10), in: Capsule()).foregroundStyle(lilac)
                    }
                    Text(lidDetail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Toggle("Closed-lid mode", isOn: Binding(get: { state.closedLid }, set: { _ in lid() }))
                    .labelsHidden().toggleStyle(.switch).tint(lilac).controlSize(.small).disabled(state.installing)
            }.padding(14).background(card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.065)))

            Button(action: lock) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text("Lock screen").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                }.font(.system(size: 13)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 43)
                    .background(lilac, in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain).help("Lock your screen while this session continues")

            HStack {
                Label(state.ac ? "Plugged in" : "On battery", systemImage: state.ac ? "powerplug" : "battery.50")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                Spacer()
                Toggle("Launch at login", isOn: Binding(get: { state.login }, set: { _ in login() }))
                    .toggleStyle(.checkbox).font(.system(size: 10.5)).controlSize(.small).foregroundStyle(.secondary)
            }
            Text("Let your screen rest. Let your work flow.")
                .font(.system(size: 10, design: .rounded)).foregroundStyle(.tertiary)
        }.padding(22).frame(width: 368).background(background)
    }

    private func chip(_ title: String, _ minutes: Double) -> some View {
        Button { start(minutes) } label: { Text(title) }
            .buttonStyle(TimerChip(selected: state.active && state.deadline != nil && state.durationMinutes == minutes))
    }
}
