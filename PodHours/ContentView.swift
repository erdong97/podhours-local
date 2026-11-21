import SwiftUI

struct ContentView: View {
    @State private var devices: [DeviceStats] = []
    @State private var combined: DeviceStats? = nil
    @State private var library: LibraryStats? = nil
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var errorText: String? = nil
    @State private var lastUpdated: Date? = nil
    @Environment(\.scenePhase) private var scenePhase

    private let reader = HealthKitReader()
    static let bg = Color(red: 0.027, green: 0.039, blue: 0.078)
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.04)

    var body: some View {
        TabView {
            devicesTab
                .tabItem { Label("设备", systemImage: "headphones") }
            trendsTab
                .tabItem { Label("趋势", systemImage: "chart.bar.fill") }
            recordsTab
                .tabItem { Label("记录", systemImage: "trophy.fill") }
        }
        .accentColor(Self.accent)
        .task { await load() }
        .onChange(of: scenePhase) { phase in
            if phase == .active && hasLoaded {
                Task { await load() }
            }
        }
    }

    // MARK: - Devices tab

    private var devicesTab: some View {
        ZStack {
            Self.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PodHours").font(.largeTitle).bold().foregroundColor(.white)
                        Text("耳机聆听时长 · 数据只在手机本地读取，不联网")
                            .font(.footnote).foregroundColor(.gray)
                    }
                    if let errorText { errorBanner(errorText) }
                    if loading && !hasLoaded {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("正在读取健康数据…").foregroundColor(.gray)
                        }.padding(.vertical, 24)
                    } else if let combined {
                        totalHeader(combined)
                        ForEach(devices, id: \.displayName) { d in
                            deviceCard(d, total: combined.totalSeconds)
                        }
                        footerNote
                    } else if !loading {
                        Text("首次打开会弹出健康授权，把「耳机音频暴露」打开即可；之后每次打开 App 都会自动更新。")
                            .foregroundColor(.gray).font(.footnote)
                        readButton
                    }
                }
                .padding(16)
            }
            .refreshable { await load() }
        }
    }

    private func totalHeader(_ c: DeviceStats) -> some View {
        VStack(spacing: 4) {
            Text("全部耳机累计").font(.footnote).foregroundColor(.gray)
            Text(Self.fmtHM(c.totalSeconds))
                .font(.system(size: 34, weight: .bold)).foregroundColor(.white)
            if let f = c.first, let l = c.last {
                Text("\(Self.dateFmt.string(from: f)) 至今 · 日均 \(Self.fmtDur(c.dailyAvgSeconds))")
                    .font(.caption).foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func deviceCard(_ d: DeviceStats, total: Double) -> some View {
        let share = total > 0 ? d.totalSeconds / total * 100 : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.displayName).font(.headline).foregroundColor(.white)
                    if !d.subtitle.isEmpty {
                        Text(d.subtitle).font(.caption).foregroundColor(.gray)
                    }
                }
                Spacer()
                Text(String(format: "%.0f%%", share))
                    .font(.headline).foregroundColor(Self.accent)
            }
            Text(Self.fmtHM(d.totalSeconds)).font(.title3).bold().foregroundColor(.white)
            ProgressView(value: max(0.01, share / 100))
                .tint(Self.accent)
                .background(Color.white.opacity(0.12))
            HStack(spacing: 14) {
                miniMetric("日均", Self.fmtDur(d.dailyAvgSeconds))
                miniMetric("次数", "\(d.sessionCount)")
                miniMetric("平均音量", String(format: "%.1f dB", d.avgDb))
                miniMetric("活跃", "\(d.activeDayCount) 天")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
    }

    // MARK: - Trends tab

    private var trendsTab: some View {
        ZStack {
            Self.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("趋势").font(.largeTitle).bold().foregroundColor(.white)
                    if let library, let combined {
                        TrendsView(library: library, combined: combined)
                    } else {
                        Text("还没有数据").foregroundColor(.gray)
                    }
                }
                .padding(16)
            }
            .refreshable { await load() }
        }
    }

    // MARK: - Records tab

    private var recordsTab: some View {
        ZStack {
            Self.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("个人记录").font(.largeTitle).bold().foregroundColor(.white)
                    if let library, let combined {
                        recordsContent(library, combined)
                    } else {
                        Text("还没有数据").foregroundColor(.gray)
                    }
                }
                .padding(16)
            }
            .refreshable { await load() }
        }
    }

    private func recordsContent(_ lib: LibraryStats, _ c: DeviceStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                if let d = lib.longestDay {
                    recordRow("单日最长", Self.fmtDur(d.seconds), sub: Self.prettyDay(d.day))
                    divider
                }
                if let s = lib.longestSession {
                    recordRow("单次最长", Self.fmtDur(s.duration),
                              sub: "\(Self.dateFmt.string(from: s.start)) · \(s.deviceName)")
                    divider
                }
                if let st = lib.longestStreak {
                    recordRow("最长连续使用", "\(st.days) 天",
                              sub: "\(Self.prettyDay(st.from)) ～ \(Self.prettyDay(st.to))")
                    divider
                }
                if let m = lib.bestMonth {
                    recordRow("单月最高", Self.fmtDur(m.seconds), sub: Self.prettyMonth(m.month))
                    divider
                }
                if let top = devices.first {
                    recordRow("最常用耳机", top.displayName, sub: Self.fmtHM(top.totalSeconds))
                }
            }
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .cornerRadius(16)

            VStack(alignment: .leading, spacing: 10) {
                Text("聆听总览").font(.headline).foregroundColor(.white)
                HStack(spacing: 14) {
                    miniMetric("总次数", "\(c.sessionCount)")
                    miniMetric("平均每次", Self.fmtDur(c.avgSessionSeconds))
                    miniMetric("最长一次", Self.fmtDur(c.longestSession))
                }
                HStack(spacing: 8) {
                    Text("平均音量 \(String(format: "%.1f", c.avgDb)) dB")
                        .font(.subheadline).bold().foregroundColor(.white)
                    Text(c.avgDb < 80 ? "健康音量" : "注意音量")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(c.avgDb < 80 ? Color.green.opacity(0.25) : Color.red.opacity(0.3))
                        .foregroundColor(c.avgDb < 80 ? .green : .red)
                        .cornerRadius(8)
                }
                Text("长时间佩戴时，音量低于 80 dB 更安全。")
                    .font(.caption2).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white.opacity(0.06))
            .cornerRadius(16)

            volumeCard(lib)
            hourlyCard(lib)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 16)
    }

    private func recordRow(_ title: String, _ value: String, sub: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundColor(.white)
                Text(sub).font(.caption).foregroundColor(.gray)
            }
            Spacer()
            Text(value).font(.headline).foregroundColor(Self.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func volumeCard(_ lib: LibraryStats) -> some View {
        let maxSec = lib.volumeBuckets.map(\.seconds).max() ?? 1
        let total = lib.volumeBuckets.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 10) {
            Text("音量分布").font(.headline).foregroundColor(.white)
            ForEach(lib.volumeBuckets, id: \.label) { b in
                HStack(spacing: 8) {
                    Text(b.label).font(.caption).foregroundColor(.gray).frame(width: 52, alignment: .leading)
                    ProgressView(value: maxSec > 0 ? b.seconds / maxSec : 0)
                        .tint(Self.accent).background(Color.white.opacity(0.12))
                    Text(total > 0 ? String(format: "%.0f%%", b.seconds / total * 100) : "0%")
                        .font(.caption).foregroundColor(.gray).frame(width: 36, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
    }

    private func hourlyCard(_ lib: LibraryStats) -> some View {
        let hours = (0..<24).map { (hour: $0, seconds: lib.hourlyTotals[$0] ?? 0) }
        let maxSec = hours.map(\.seconds).max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Text("24 小时分布").font(.headline).foregroundColor(.white)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(hours, id: \.hour) { h in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Self.accent.opacity(h.seconds > 0 ? 1 : 0.25))
                            .frame(height: max(3, 64 * h.seconds / maxSec))
                        if h.hour % 6 == 0 {
                            Text("\(h.hour)").font(.system(size: 8)).foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("你一天里各时段的累计聆听时长").font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
    }

    // MARK: - Shared

    private var readButton: some View {
        Button {
            Task { await load() }
        } label: {
            Text(loading ? "正在读取…" : "读取健康数据")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Self.accent)
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

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lastUpdated {
                Text("更新于 \(Self.timeFmt.string(from: lastUpdated)) · 下拉或切回 App 会自动刷新")
                    .font(.caption).foregroundColor(.gray)
            }
            Text("统计口径：样本去重、重叠合并计长；同名同型号的蓝牙标识合并为一副耳机；间隔 ≤3 分钟算同一次使用，不足 1 分钟不计次；平均音量按实际时长能量加权；日均 = 累计 ÷ 首末自然天数。")
                .font(.caption2).foregroundColor(Color(white: 0.45))
        }
    }

    private func miniMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline).bold().foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.gray)
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
                errorText = "查询完成，但没有读到耳机音频记录（可能是还没授权，或这台手机上还没有耳机聆听记录）。"
            } else {
                errorText = nil
            }
            let result = StatsEngine().compute(samples: rows)
            devices = result.devices
            combined = result.combined
            library = result.library
        } catch {
            hasLoaded = true
            errorText = error.localizedDescription
        }
    }

    // MARK: - Formatting

    static func fmtHM(_ s: Double) -> String {
        let totalMinutes = Int((s / 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return "\(h) 小时 \(m) 分钟" }
        return "\(m) 分钟"
    }

    static func fmtDur(_ s: Double) -> String {
        fmtHM(s)
    }

    static func prettyDay(_ key: String) -> String {
        // "2024-01-05" -> "2024年1月5日"
        let p = key.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return key }
        return "\(y)年\(m)月\(d)日"
    }

    static func prettyMonth(_ key: String) -> String {
        let p = key.split(separator: "-")
        guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]) else { return key }
        return "\(y)年\(m)月"
    }

    static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()
}

// MARK: - Trends

private struct TrendsView: View {
    enum Window: String, CaseIterable, Identifiable {
        case week = "周"
        case month = "月"
        case year = "年"
        case all = "总共"
        var id: String { rawValue }
    }

    let library: LibraryStats
    let combined: DeviceStats
    @State private var window: Window = .week

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("周期", selection: $window) {
                ForEach(Window.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            let data = series()
            let total = data.reduce(0) { $0 + $1.seconds }
            let prev = previousTotal()
            VStack(spacing: 4) {
                Text(ContentView.fmtHM(total))
                    .font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                if let prev, window != .all {
                    let diff = total - prev
                    Text("\(diff >= 0 ? "比上一周期多" : "比上一周期少") \(ContentView.fmtHM(abs(diff)))")
                        .font(.caption)
                        .foregroundColor(diff >= 0 ? .green : .orange)
                }
            }
            .frame(maxWidth: .infinity)

            bars(data)

            HStack(spacing: 14) {
                if window == .year || window == .all {
                    statBox("月均", ContentView.fmtDur(total / Double(max(data.count, 1))))
                    statBox("最长一个月", ContentView.fmtDur(data.map(\.seconds).max() ?? 0))
                    statBox("有记录月份", "\(data.filter { $0.seconds > 0 }.count)")
                } else {
                    statBox("日均", ContentView.fmtDur(total / Double(max(data.count, 1))))
                    statBox("最长一天", ContentView.fmtDur(data.map(\.seconds).max() ?? 0))
                    statBox("有记录天数", "\(data.filter { $0.seconds > 0 }.count)")
                }
            }
        }
    }

    private func statBox(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline).bold().foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }

    private func bars(_ data: [(label: String, seconds: Double)]) -> some View {
        let maxSec = data.map(\.seconds).max() ?? 1
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ContentView.accent.opacity(item.seconds > 0 ? 1 : 0.25))
                        .frame(height: max(3, 90 * item.seconds / maxSec))
                    Text(item.label).font(.system(size: 8)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
    }

    /// Bars for the selected window, anchored at the last recorded day.
    private func series() -> [(label: String, seconds: Double)] {
        guard let lastKey = library.dailyTotals.keys.max() else { return [] }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd"
        guard let lastDay = df.date(from: lastKey) else { return [] }
        switch window {
        case .week:
            return (0..<7).map { i in
                let d = cal.date(byAdding: .day, value: i - 6, to: lastDay)!
                return (label: weekdayLabel(d), seconds: library.dailyTotals[df.string(from: d)] ?? 0)
            }
        case .month:
            return (0..<30).map { i in
                let d = cal.date(byAdding: .day, value: i - 29, to: lastDay)!
                let day = cal.component(.day, from: d)
                return (label: day % 5 == 1 || i == 29 ? "\(day)" : "",
                        seconds: library.dailyTotals[df.string(from: d)] ?? 0)
            }
        case .year, .all:
            let months = combined.monthly
            let slice = window == .year ? Array(months.suffix(12)) : months
            return slice.map { (label: String($0.month.dropFirst(2)), seconds: $0.seconds) }
        }
    }

    private func previousTotal() -> Double? {
        guard let lastKey = library.dailyTotals.keys.max() else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy-MM-dd"
        guard let lastDay = df.date(from: lastKey) else { return nil }
        let days: Int
        switch window {
        case .week: days = 7
        case .month: days = 30
        case .year: days = 365
        case .all: return nil
        }
        var sum = 0.0
        for i in 0..<days {
            let d = cal.date(byAdding: .day, value: -(days + i), to: lastDay)!
            sum += library.dailyTotals[df.string(from: d)] ?? 0
        }
        return sum
    }

    private func weekdayLabel(_ d: Date) -> String {
        let labels = ["日", "一", "二", "三", "四", "五", "六"]
        return labels[cal.component(.weekday, from: d) - 1]
    }
}
