import SwiftUI

/// Local mood log, one entry per day, stored on-device only.
final class MoodStore: ObservableObject {
    static let moods: [(emoji: String, label: String)] = [
        ("😄", "开心"), ("😌", "平静"), ("🎧", "沉浸"), ("😫", "疲惫"), ("😴", "困倦"),
    ]
    @Published var entries: [String: Int] = [:]
    private let key = "mood.entries.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            entries = decoded
        }
    }

    func setMood(_ index: Int, forDay day: String) {
        if entries[day] == index {
            entries[day] = nil
        } else {
            entries[day] = index
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct TodayView: View {
    let combined: DeviceStats?
    let devices: [DeviceStats]
    let loading: Bool
    let hasLoaded: Bool
    let errorText: String?
    let lastUpdated: Date?
    let onRefresh: () async -> Void
    @StateObject private var mood = MoodStore()

    private var cal: Calendar { Calendar(identifier: .gregorian) }

    var body: some View {
        ZStack {
            Fmt.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("今天").font(.largeTitle).bold().foregroundColor(.white)
                    if let errorText {
                        errorBanner(errorText)
                    }
                    if loading && !hasLoaded {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("正在读取健康数据…").foregroundColor(.gray)
                        }.padding(.vertical, 24)
                    } else if let combined {
                        content(combined)
                    } else if !loading {
                        Text("首次打开会弹出健康授权，把「耳机音频暴露」打开即可；之后每次打开 App 都会自动更新。")
                            .foregroundColor(.gray).font(.footnote)
                    }
                    if let lastUpdated {
                        Text("更新于 \(Fmt.updatedFmt.string(from: lastUpdated)) · 数据只在手机本地读取，不联网")
                            .font(.caption).foregroundColor(.gray)
                    }
                }
                .padding(16)
            }
            .refreshable { await onRefresh() }
        }
    }

    private func content(_ c: DeviceStats) -> some View {
        let today = Fmt.dayKey(Date())
        let yesterdayDate = cal.date(byAdding: .day, value: -1, to: Date())!
        let yesterday = Fmt.dayKey(yesterdayDate)
        let todaySec = c.library.dailyTotals[today] ?? 0
        let yestSec = c.library.dailyTotals[yesterday] ?? 0
        let todaySessions = c.library.dailySessions[today] ?? []
        return VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 6) {
                Text("今日聆听").font(.footnote).foregroundColor(.gray)
                Text(Fmt.hm(todaySec))
                    .font(.system(size: 36, weight: .bold)).foregroundColor(.white)
                if yestSec > 0 || todaySec > 0 {
                    let diff = todaySec - yestSec
                    Text(diff >= 0 ? "比昨天多 \(Fmt.hm(diff))" : "比昨天少 \(Fmt.hm(-diff))")
                        .font(.caption)
                        .foregroundColor(diff >= 0 ? .green : .orange)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Fmt.card)
            .cornerRadius(16)

            HStack(spacing: 14) {
                statBox("今日次数", "\(todaySessions.count)")
                if let db = c.library.avgDb(onDay: today) {
                    statBox("今日均量", String(format: "%.1f dB", db))
                }
                statBox("昨日总计", Fmt.hm(yestSec))
            }

            let usedToday = devices.filter { ($0.library.dailyTotals[today] ?? 0) > 0 }
            if !usedToday.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("今日设备").font(.headline).foregroundColor(.white)
                    ForEach(usedToday, id: \.displayName) { d in
                        HStack(spacing: 10) {
                            Image(systemName: Fmt.symbol(for: d.displayName))
                                .font(.title3).foregroundColor(Fmt.accent)
                            Text(d.displayName).foregroundColor(.white)
                            Spacer()
                            Text(Fmt.hm(d.library.dailyTotals[today] ?? 0))
                                .bold().foregroundColor(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Fmt.card)
                .cornerRadius(16)
            }

            moodCard(today: today)
            weekCard(c)
        }
    }

    private func moodCard(today: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日心情").font(.headline).foregroundColor(.white)
            HStack(spacing: 10) {
                ForEach(Array(MoodStore.moods.enumerated()), id: \.offset) { idx, m in
                    Button {
                        mood.setMood(idx, forDay: today)
                    } label: {
                        VStack(spacing: 3) {
                            Text(m.emoji).font(.title2)
                            Text(m.label).font(.caption2)
                                .foregroundColor(mood.entries[today] == idx ? .white : .gray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(mood.entries[today] == idx
                            ? Fmt.accent.opacity(0.35) : Color.white.opacity(0.05))
                        .cornerRadius(10)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach((0..<7).reversed(), id: \.self) { offset in
                    let d = cal.date(byAdding: .day, value: -offset, to: Date())!
                    let key = Fmt.dayKey(d)
                    VStack(spacing: 2) {
                        Text(mood.entries[key].map { MoodStore.moods[$0].emoji } ?? "·")
                            .font(.caption)
                        Text(offset == 0 ? "今" : "\(cal.component(.day, from: d))")
                            .font(.system(size: 8)).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Fmt.card)
        .cornerRadius(16)
    }

    private func weekCard(_ c: DeviceStats) -> some View {
        let days: [(label: String, seconds: Double)] = (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i - 6, to: Date())!
            let labels = ["日", "一", "二", "三", "四", "五", "六"]
            return (labels[cal.component(.weekday, from: d) - 1],
                    c.library.dailyTotals[Fmt.dayKey(d)] ?? 0)
        }
        let maxSec = max(days.map(\.seconds).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("近 7 天").font(.headline).foregroundColor(.white)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Fmt.accent.opacity(item.seconds > 0 ? 1 : 0.25))
                            .frame(height: max(3, 56 * item.seconds / maxSec))
                        Text(item.label).font(.system(size: 9)).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Fmt.card)
        .cornerRadius(16)
    }

    private func statBox(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline).bold().foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Fmt.card)
        .cornerRadius(10)
    }

    private func errorBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("读取没成功").font(.headline).foregroundColor(.white)
            Text(text).font(.footnote).foregroundColor(Color(red: 1, green: 0.85, blue: 0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(red: 0.55, green: 0.15, blue: 0.12))
        .cornerRadius(12)
    }
}
