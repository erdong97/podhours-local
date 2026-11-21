import SwiftUI

struct DayRef: Identifiable {
    let key: String
    var id: String { key }
}

struct StatsTabView: View {
    enum Win: String, CaseIterable, Identifiable {
        case week = "周"
        case month = "月"
        case year = "年"
        case all = "总共"
        var id: String { rawValue }
    }

    let combined: DeviceStats?
    let devices: [DeviceStats]
    let onRefresh: () async -> Void
    @State private var win: Win = .week
    @State private var dayToShow: DayRef? = nil

    private var cal: Calendar { Calendar(identifier: .gregorian) }

    var body: some View {
        ZStack {
            Fmt.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("统计").font(.largeTitle).bold().foregroundColor(.white)
                    if let combined {
                        content(combined)
                    } else {
                        Text("还没有数据").foregroundColor(.gray)
                    }
                }
                .padding(16)
            }
            .refreshable { await onRefresh() }
        }
        .sheet(item: $dayToShow) { ref in
            if let combined {
                DayDetailView(library: combined.library, dayKey: ref.key)
            }
        }
    }

    // MARK: - Window plumbing

    private func windowDays(_ lib: LibraryStats) -> [String] {
        let allKeys = lib.dailyTotals.keys.sorted()
        guard let lastKey = allKeys.last,
              let lastDay = Fmt.keyFmt.date(from: lastKey) else { return [] }
        switch win {
        case .all:
            return allKeys
        case .week, .month, .year:
            let n = win == .week ? 7 : (win == .month ? 30 : 365)
            return (0..<n).map { i in
                Fmt.dayKey(cal.date(byAdding: .day, value: i - (n - 1), to: lastDay)!)
            }
        }
    }

    private struct Agg {
        var total = 0.0
        var energy = 0.0
        var sessions: [SessionInfo] = []
        var avgDb: Double? {
            total > 0 && energy > 0 ? 10 * log10(energy / total) : nil
        }
        var avgSession: Double {
            sessions.isEmpty ? 0 : sessions.reduce(0) { $0 + $1.duration } / Double(sessions.count)
        }
        var longest: SessionInfo? { sessions.max(by: { $0.duration < $1.duration }) }
    }

    private func aggregate(_ lib: LibraryStats, days: [String]) -> Agg {
        var agg = Agg()
        for k in days {
            agg.total += lib.dailyTotals[k] ?? 0
            agg.energy += lib.dailyEnergy[k] ?? 0
            agg.sessions += lib.dailySessions[k] ?? []
        }
        return agg
    }

    private func rangeLabel(_ days: [String]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        func md(_ key: String) -> String {
            let p = key.split(separator: "-")
            guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return key }
            return "\(m).\(d)"
        }
        if win == .year || win == .all {
            return "\(Fmt.prettyMonth(String(first.prefix(7)))) – \(Fmt.prettyMonth(String(last.prefix(7))))"
        }
        return "\(md(first)) – \(md(last))"
    }

    // MARK: - Content

    private func content(_ c: DeviceStats) -> some View {
        let days = windowDays(c.library)
        let agg = aggregate(c.library, days: days)
        return VStack(alignment: .leading, spacing: 16) {
            Picker("周期", selection: $win) {
                ForEach(Win.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(rangeLabel(days)).font(.caption).foregroundColor(.gray)

            heroCard(days: days)
            overviewCard(c, agg: agg, days: days)
            barsCard(c, days: days)
            if win == .week || win == .month {
                dayListCard(c, days: days)
            }
            recordsCard(c)
            chartsCard(c)
            volumeCard(c)
        }
    }

    private func heroCard(days: [String]) -> some View {
        let hero = devices
            .map { (device: $0, total: aggregate($0.library, days: days).total) }
            .max(by: { $0.total < $1.total })
        return VStack(spacing: 6) {
            Text("戴的最久的耳机").font(.footnote).foregroundColor(.gray)
            if let hero, hero.total > 0 {
                Image(systemName: Fmt.symbol(for: hero.device.displayName))
                    .font(.system(size: 44)).foregroundColor(Fmt.accent)
                Text(hero.device.displayName).font(.headline).foregroundColor(.white)
                Text(Fmt.hm(hero.total))
                    .font(.system(size: 32, weight: .bold)).foregroundColor(Fmt.accent)
            } else {
                Text("这个周期还没有记录").foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Fmt.card)
        .cornerRadius(16)
    }

    private func overviewCard(_ c: DeviceStats, agg: Agg, days: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.hm(agg.total)).font(.title3).bold().foregroundColor(.white)
                    Text("累计时长").font(.caption2).foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agg.sessions.count)").font(.title3).bold().foregroundColor(.white)
                    Text("佩戴次数").font(.caption2).foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.hm(agg.avgSession)).font(.title3).bold().foregroundColor(.white)
                    Text("平均每次").font(.caption2).foregroundColor(.gray)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agg.longest.map { Fmt.hm($0.duration) } ?? "—")
                        .font(.title3).bold().foregroundColor(.white)
                    Text("最长一次").font(.caption2).foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.hm(agg.total / Double(max(days.count, 1))))
                        .font(.title3).bold().foregroundColor(.white)
                    Text("日均").font(.caption2).foregroundColor(.gray)
                }
                Spacer()
                if let db = agg.avgDb {
                    VolumeBadge(avgDb: db)
                }
            }
            if let longest = agg.longest {
                Text("最长一次：\(Fmt.date(longest.start)) · \(longest.deviceName)")
                    .font(.caption2).foregroundColor(.gray)
            }
            Text("长时间佩戴时，音量低于 80 dB 更安全。")
                .font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Fmt.card)
        .cornerRadius(16)
    }

    private func barsCard(_ c: DeviceStats, days: [String]) -> some View {
        let data: [(label: String, seconds: Double)]
        if win == .year || win == .all {
            var byMonth: [String: Double] = [:]
            for k in days { byMonth[String(k.prefix(7)), default: 0] += c.library.dailyTotals[k] ?? 0 }
            data = byMonth.keys.sorted().map { (label: String($0.dropFirst(2)), seconds: byMonth[$0] ?? 0) }
        } else {
            data = days.map { k in
                let d = Fmt.keyFmt.date(from: k)
                let label: String
                if win == .week, let d {
                    label = ["日", "一", "二", "三", "四", "五", "六"][cal.component(.weekday, from: d) - 1]
                } else if let d {
                    let day = cal.component(.day, from: d)
                    label = day % 5 == 1 || k == days.last ? "\(day)" : ""
                } else {
                    label = ""
                }
                return (label: label, seconds: c.library.dailyTotals[k] ?? 0)
            }
        }
        let maxSec = max(data.map(\.seconds).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Fmt.accent.opacity(item.seconds > 0 ? 1 : 0.25))
                        .frame(height: max(3, 90 * item.seconds / maxSec))
                    Text(item.label).font(.system(size: 8)).foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(Fmt.card)
        .cornerRadius(16)
    }

    private func dayListCard(_ c: DeviceStats, days: [String]) -> some View {
        let rows = days.reversed().filter { (c.library.dailyTotals[$0] ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: 4) {
            Text("每日明细").font(.headline).foregroundColor(.white)
            if rows.isEmpty {
                Text("这个周期还没有记录").font(.footnote).foregroundColor(.gray)
            }
            ForEach(rows, id: \.self) { key in
                Button {
                    dayToShow = DayRef(key: key)
                } label: {
                    HStack {
                        Text(Fmt.prettyDay(key)).foregroundColor(.white).font(.subheadline)
                        Spacer()
                        Text("\(c.library.dailySessions[key]?.count ?? 0) 次")
                            .font(.caption).foregroundColor(.gray)
                        Text(Fmt.hm(c.library.dailyTotals[key] ?? 0))
                            .bold().foregroundColor(Fmt.accent)
                        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.gray)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Fmt.card)
        .cornerRadius(16)
    }

    private func recordsCard(_ c: DeviceStats) -> some View {
        let lib = c.library
        return VStack(alignment: .leading, spacing: 4) {
            Text("个人记录").font(.headline).foregroundColor(.white)
                .padding(.bottom, 4)
            if let d = lib.longestDay {
                recordRow("单日最长", Fmt.hm(d.seconds), sub: Fmt.prettyDay(d.day))
            }
            if let s = lib.longestSession {
                recordRow("单次最长", Fmt.hm(s.duration),
                          sub: "\(Fmt.date(s.start)) · \(s.deviceName)")
            }
            if let st = lib.longestStreak {
                recordRow("最长连续使用", "\(st.days) 天",
                          sub: "\(Fmt.prettyDay(st.from)) ～ \(Fmt.prettyDay(st.to))")
            }
            if let m = lib.bestMonth {
                recordRow("单月最高", Fmt.hm(m.seconds), sub: Fmt.prettyMonth(m.month))
            }
            if let top = devices.first {
                recordRow("最常用耳机", top.displayName, sub: Fmt.hm(top.totalSeconds))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Fmt.card)
        .cornerRadius(16)
    }

    private func recordRow(_ title: String, _ value: String, sub: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundColor(.white)
                Text(sub).font(.caption).foregroundColor(.gray)
            }
            Spacer()
            Text(value).font(.headline).foregroundColor(Fmt.accent)
        }
        .padding(.vertical, 6)
    }

    private func chartsCard(_ c: DeviceStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("24 小时分布").font(.headline).foregroundColor(.white)
            HStack {
                Spacer()
                HourlyRing(hourly: c.library.hourlyTotals)
                Spacer()
            }
            HourlyBars(hourly: c.library.hourlyTotals, height: 48)
            Text("你一天里各时段的累计聆听时长").font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Fmt.card)
        .cornerRadius(16)
    }

    private func volumeCard(_ c: DeviceStats) -> some View {
        let buckets = c.library.volumeBuckets
        let maxSec = max(buckets.map(\.seconds).max() ?? 1, 1)
        let total = buckets.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 10) {
            Text("音量分布").font(.headline).foregroundColor(.white)
            ForEach(buckets, id: \.label) { b in
                HStack(spacing: 8) {
                    Text(b.label).font(.caption).foregroundColor(.gray)
                        .frame(width: 52, alignment: .leading)
                    ProgressView(value: b.seconds / maxSec)
                        .tint(Fmt.accent).background(Color.white.opacity(0.12))
                    Text(total > 0 ? String(format: "%.0f%%", b.seconds / total * 100) : "0%")
                        .font(.caption).foregroundColor(.gray)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Fmt.card)
        .cornerRadius(16)
    }
}

// MARK: - Day detail

struct DayDetailView: View {
    let library: LibraryStats
    let dayKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Fmt.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(Fmt.prettyDay(dayKey)).font(.title2).bold().foregroundColor(.white)
                        Spacer()
                        Button("关闭") { dismiss() }.foregroundColor(Fmt.accent)
                    }
                    let total = library.dailyTotals[dayKey] ?? 0
                    let sessions = library.dailySessions[dayKey] ?? []
                    VStack(spacing: 4) {
                        Text(Fmt.hm(total))
                            .font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                        Text("共 \(sessions.count) 次佩戴")
                            .font(.caption).foregroundColor(.gray)
                        if let db = library.avgDb(onDay: dayKey) {
                            VolumeBadge(avgDb: db).padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("每次佩戴").font(.headline).foregroundColor(.white)
                        if sessions.isEmpty {
                            Text("这一天没有单次记录").font(.footnote).foregroundColor(.gray)
                        }
                        ForEach(Array(sessions.enumerated()), id: \.offset) { _, s in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(Fmt.time(s.start)) – \(Fmt.time(s.end))")
                                        .font(.subheadline).foregroundColor(.white)
                                    Text(s.deviceName).font(.caption2).foregroundColor(.gray)
                                }
                                Spacer()
                                Text(Fmt.hm(s.duration)).bold().foregroundColor(Fmt.accent)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Fmt.card)
                    .cornerRadius(16)
                }
                .padding(16)
            }
        }
    }
}
