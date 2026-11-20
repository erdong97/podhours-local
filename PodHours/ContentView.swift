import SwiftUI

struct ContentView: View {
    private enum RangeOption: String, CaseIterable, Identifiable {
        case all = "全部"
        case year = "近 1 年"
        case d90 = "近 90 天"
        case d30 = "近 30 天"
        case d7 = "近 7 天"
        var id: String { rawValue }
        var days: Double? {
            switch self {
            case .all: return nil
            case .year: return 365
            case .d90: return 90
            case .d30: return 30
            case .d7: return 7
            }
        }
    }

    @State private var allSamples: [RawSample] = []
    @State private var devices: [DeviceStats] = []
    @State private var combined: DeviceStats? = nil
    @State private var range: RangeOption = .all
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var errorText: String? = nil
    @State private var lastUpdated: Date? = nil
    @Environment(\.scenePhase) private var scenePhase

    private let reader = HealthKitReader()
    private let bg = Color(red: 0.027, green: 0.039, blue: 0.078)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let errorText {
                        errorBanner(errorText)
                    }
                    if loading && !hasLoaded {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("正在读取健康数据…").foregroundColor(.gray)
                        }
                        .padding(.vertical, 24)
                    } else if hasLoaded {
                        Picker("时间范围", selection: $range) {
                            ForEach(RangeOption.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: range) { _ in recompute() }

                        if let combined {
                            StatsCard(stats: combined, headline: true)
                        }
                        ForEach(devices, id: \.displayName) { d in
                            StatsCard(stats: d, headline: false)
                        }
                        footer
                    } else if !loading {
                        Text("点下方按钮读取你的耳机聆听记录。首次会弹出健康授权，把「耳机音频暴露」打开即可；之后每次打开 App 都会自动更新。")
                            .foregroundColor(.gray)
                            .font(.footnote)
                        readButton
                    }
                }
                .padding(16)
            }
            .refreshable { await load() }
        }
        .task { await load() }
        .onChange(of: scenePhase) { phase in
            if phase == .active && hasLoaded {
                Task { await load() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PodHours").font(.largeTitle).bold().foregroundColor(.white)
            Text("耳机聆听时长 · 数据只在手机本地读取，不联网")
                .font(.footnote).foregroundColor(.gray)
        }
    }

    private var readButton: some View {
        Button {
            Task { await load() }
        } label: {
            Text(loading ? "正在读取…" : "读取健康数据")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.96, green: 0.62, blue: 0.04))
                .foregroundColor(.black)
                .cornerRadius(12)
        }
        .disabled(loading)
    }

    private func errorBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("读取没成功").font(.headline).foregroundColor(.white)
            Text(text).font(.footnote).foregroundColor(Color(red: 1, green: 0.85, blue: 0.8))
            Text("若一直读不到：到「设置 → 隐私与安全性 → 健康 → PodHours」确认耳机音频数据已允许；或在健康 App → 头像 → 隐私 → App 里检查。")
                .font(.footnote).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(red: 0.55, green: 0.15, blue: 0.12))
        .cornerRadius(12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lastUpdated {
                Text("更新于 \(Self.timeFormatter.string(from: lastUpdated)) · 下拉或切回 App 会自动刷新")
                    .font(.caption).foregroundColor(.gray)
            }
            Text("统计口径：样本按开始时间排序、去重，重叠时段合并计长；名称、厂商、型号相同的蓝牙标识合并为一副耳机；相邻时段间隔不超过 3 分钟合并为一次使用，不足 1 分钟的使用不计次数；平均音量按去重叠后的实际时长做能量加权；日均 = 累计时长 ÷ 首次到最近使用的自然天数。")
                .font(.caption2).foregroundColor(Color(white: 0.45))
        }
    }

    private func load() async {
        if loading { return }
        loading = true
        defer { loading = false }
        do {
            let rows = try await reader.fetch()
            allSamples = rows
            hasLoaded = true
            lastUpdated = Date()
            if rows.isEmpty {
                errorText = "查询完成，但没有读到耳机音频记录（可能是还没授权，或这台手机上还没有耳机聆听记录）。"
            } else {
                errorText = nil
            }
            recompute()
        } catch {
            hasLoaded = true
            errorText = error.localizedDescription
        }
    }

    private func recompute() {
        var samples = allSamples
        if let days = range.days, let last = samples.map(\.end).max() {
            let cutoff = last - days * 86400
            samples = samples.filter { $0.end > cutoff }
        }
        let result = StatsEngine().compute(samples: samples)
        devices = result.devices
        combined = result.combined
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()
}

// MARK: - Card

private struct StatsCard: View {
    let stats: DeviceStats
    let headline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.displayName).font(.headline).foregroundColor(.white)
                if !stats.subtitle.isEmpty {
                    Text(stats.subtitle).font(.caption).foregroundColor(.gray)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", stats.totalSeconds / 3600))
                    .font(.system(size: 40, weight: .bold)).foregroundColor(.white)
                Text("小时累计聆听").foregroundColor(.gray).font(.footnote)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: 12) {
                metric("日均时长", Self.fmtDur(stats.dailyAvgSeconds))
                metric("活跃天数", "\(stats.activeDayCount) 天")
                metric("使用次数", "\(stats.sessionCount) 次")
                metric("最长一次", Self.fmtDur(stats.longestSession))
                metric("平均音量", String(format: "%.1f dB", stats.avgDb))
                metric("≥80 dB 占比", String(format: "%.0f%%", stats.ge80Percent))
            }
            if let f = stats.first, let l = stats.last {
                Text("首次记录 \(Self.dateFormatter.string(from: f)) · 最近记录 \(Self.dateFormatter.string(from: l))")
                    .font(.caption).foregroundColor(.gray)
            }
            if stats.monthly.count > 1 {
                monthlyBars
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(headline ? 0.10 : 0.06))
        .cornerRadius(16)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline).bold().foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.gray)
        }
    }

    private var monthlyBars: some View {
        let maxSec = stats.monthly.map(\.seconds).max() ?? 1
        return VStack(alignment: .leading, spacing: 6) {
            Text("每月聆听时长").font(.caption).foregroundColor(.gray)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(stats.monthly, id: \.month) { m in
                    VStack(spacing: 3) {
                        Text(String(format: "%.1f", m.seconds / 3600))
                            .font(.system(size: 8)).foregroundColor(.gray)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(red: 0.96, green: 0.62, blue: 0.04))
                            .frame(height: max(4, 56 * m.seconds / maxSec))
                        Text(String(m.month.dropFirst(2)))
                            .font(.system(size: 8)).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    static func fmtDur(_ s: Double) -> String {
        let totalMinutes = Int((s / 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 { return "\(h) 小时 \(m) 分钟" }
        if h > 0 { return "\(h) 小时" }
        return "\(m) 分钟"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()
}
