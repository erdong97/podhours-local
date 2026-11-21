import SwiftUI

/// Shared formatting helpers, PodsStats style ("4298 h 31 min").
enum Fmt {
    static func hm(_ s: Double) -> String {
        let totalMinutes = Int((s / 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return "\(h) h \(m) min" }
        if m > 0 { return "\(m) min" }
        return "\(Int(s.rounded())) s"
    }

    static func date(_ d: Date) -> String { dateFmt.string(from: d) }

    static func time(_ d: Date) -> String { timeFmt.string(from: d) }

    static func dayKey(_ d: Date) -> String { keyFmt.string(from: d) }

    static func prettyDay(_ key: String) -> String {
        let p = key.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return key }
        return "\(y)年\(m)月\(d)日"
    }

    static func prettyMonth(_ key: String) -> String {
        let p = key.split(separator: "-")
        guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]) else { return key }
        return "\(y)年\(m)月"
    }

    static func symbol(for deviceName: String) -> String {
        let n = deviceName.lowercased()
        if n.contains("max") { return "airpodsmax" }
        if n.contains("pro") { return "airpodspro" }
        if n.contains("airpods") || n.contains("beats") { return "airpods" }
        if n.contains("earpods") { return "earbuds" }
        return "headphones"
    }

    static let accent = Color(red: 0.45, green: 0.75, blue: 1.0)
    static let bg = Color(red: 0.027, green: 0.039, blue: 0.078)
    static let card = Color.white.opacity(0.06)

    static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let keyFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let updatedFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()
}

struct ContentView: View {
    @State private var devices: [DeviceStats] = []
    @State private var combined: DeviceStats? = nil
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var errorText: String? = nil
    @State private var lastUpdated: Date? = nil
    @Environment(\.scenePhase) private var scenePhase

    private let reader = HealthKitReader()

    var body: some View {
        TabView {
            TodayView(combined: combined, devices: devices,
                      loading: loading, hasLoaded: hasLoaded,
                      errorText: errorText, lastUpdated: lastUpdated,
                      onRefresh: { await load() })
                .tabItem { Label("今天", systemImage: "calendar") }
            StatsTabView(combined: combined, devices: devices,
                         onRefresh: { await load() })
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
            DevicesView(combined: combined, devices: devices,
                        onRefresh: { await load() })
                .tabItem { Label("设备", systemImage: "headphones") }
        }
        .accentColor(Fmt.accent)
        .task { await load() }
        .onChange(of: scenePhase) { phase in
            if phase == .active && hasLoaded {
                Task { await load() }
            }
        }
    }

    private func load() async {
        if loading { return }
        loading = true
        defer { loading = false }
        do {
            let rows = try await reader.fetch()
            hasLoaded = true
            lastUpdated = Date()
            if rows.isEmpty {
                errorText = "查询完成，但没有读到耳机音频记录（可能是还没授权，或这台手机上还没有耳机聆听记录）。首次授权请到「设置 → 隐私与安全性 → 健康 → PodsStats」确认已允许。"
            } else {
                errorText = nil
            }
            let result = StatsEngine().compute(samples: rows)
            devices = result.devices
            combined = result.combined
        } catch {
            hasLoaded = true
            errorText = error.localizedDescription
        }
    }
}

/// Small label/value pair used across cards.
struct MiniMetric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline).bold().foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.gray)
        }
    }
}

/// "平均音量 xx dB" + safe-range badge.
struct VolumeBadge: View {
    let avgDb: Double
    var body: some View {
        HStack(spacing: 8) {
            Text("平均音量 \(String(format: "%.1f", avgDb)) dB")
                .font(.subheadline).bold().foregroundColor(.white)
            Text(avgDb < 80 ? "安全范围" : "注意音量")
                .font(.caption).bold()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(avgDb < 80 ? Color.green.opacity(0.25) : Color.red.opacity(0.3))
                .foregroundColor(avgDb < 80 ? .green : .red)
                .cornerRadius(8)
        }
    }
}

/// 24 hourly bars.
struct HourlyBars: View {
    let hourly: [Int: Double]
    var height: CGFloat = 64
    var body: some View {
        let hours = (0..<24).map { (hour: $0, seconds: hourly[$0] ?? 0) }
        let maxSec = max(hours.map(\.seconds).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(hours, id: \.hour) { h in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Fmt.accent.opacity(h.seconds > 0 ? 1 : 0.25))
                        .frame(height: max(3, height * h.seconds / maxSec))
                    if h.hour % 6 == 0 {
                        Text("\(h.hour)").font(.system(size: 8)).foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// 24-hour ring: one arc segment per hour, opacity by listening share.
struct HourlyRing: View {
    let hourly: [Int: Double]
    var body: some View {
        let maxSec = max(hourly.values.max() ?? 1, 1)
        let peak = hourly.max(by: { $0.value < $1.value })
        ZStack {
            ForEach(0..<24, id: \.self) { h in
                let frac = (hourly[h] ?? 0) / maxSec
                Circle()
                    .trim(from: CGFloat(h) / 24 + 0.002, to: CGFloat(h + 1) / 24 - 0.002)
                    .stroke(Fmt.accent.opacity(0.12 + 0.88 * frac),
                            style: StrokeStyle(lineWidth: 15, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 2) {
                if let peak, peak.value > 0 {
                    Text("\(peak.key) 时").font(.headline).foregroundColor(.white)
                    Text("最常听的时段").font(.caption2).foregroundColor(.gray)
                } else {
                    Text("暂无").foregroundColor(.gray)
                }
            }
        }
        .frame(width: 168, height: 168)
    }
}
