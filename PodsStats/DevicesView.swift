import SwiftUI

struct DevicesView: View {
    let combined: DeviceStats?
    let devices: [DeviceStats]
    let onRefresh: () async -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Fmt.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let combined {
                            header(combined)
                            ForEach(devices, id: \.displayName) { d in
                                NavigationLink {
                                    DeviceDetailView(device: d,
                                                     total: combined.totalSeconds)
                                } label: {
                                    deviceCard(d, total: combined.totalSeconds)
                                }
                                .buttonStyle(.plain)
                            }
                            Text("统计口径：样本去重、重叠合并计长；同名同型号的蓝牙标识合并为一副耳机；间隔 ≤3 分钟算同一次使用，不足 1 分钟不计次；平均音量按实际时长能量加权。")
                                .font(.caption2).foregroundColor(Color(white: 0.45))
                        } else {
                            Text("还没有数据").foregroundColor(.gray)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await onRefresh() }
            }
            .navigationTitle("设备")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func header(_ c: DeviceStats) -> some View {
        VStack(spacing: 6) {
            Text("全部耳机累计佩戴").font(.footnote).foregroundColor(.white.opacity(0.75))
            Text(Fmt.hm(c.totalSeconds))
                .font(.system(size: 38, weight: .bold)).foregroundColor(.white)
            Text("\(devices.count) 副耳机 · 日均 \(Fmt.hm(c.dailyAvgSeconds))")
                .font(.caption).foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            LinearGradient(colors: [Color(red: 0.10, green: 0.35, blue: 0.25),
                                    Color(red: 0.05, green: 0.18, blue: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(20)
    }

    private func deviceCard(_ d: DeviceStats, total: Double) -> some View {
        let share = total > 0 ? d.totalSeconds / total * 100 : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Fmt.accent.opacity(0.5), Fmt.accent.opacity(0.15)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                    Image(systemName: Fmt.symbol(for: d.displayName))
                        .font(.system(size: 26)).foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.displayName).font(.headline).foregroundColor(.white)
                    if !d.subtitle.isEmpty {
                        Text(d.subtitle).font(.caption).foregroundColor(.gray)
                    }
                }
                Spacer()
                Text(String(format: "%.0f%%", share))
                    .font(.title3).bold().foregroundColor(Fmt.accent)
            }
            Text(Fmt.hm(d.totalSeconds)).font(.title3).bold().foregroundColor(.white)
            ProgressView(value: max(0.01, share / 100))
                .tint(Fmt.accent)
                .background(Color.white.opacity(0.12))
            HStack(spacing: 14) {
                MiniMetric(label: "日均", value: Fmt.hm(d.dailyAvgSeconds))
                MiniMetric(label: "次数", value: "\(d.sessionCount)")
                MiniMetric(label: "平均音量", value: String(format: "%.1f dB", d.avgDb))
                MiniMetric(label: "活跃", value: "\(d.activeDayCount) 天")
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Fmt.card)
        .cornerRadius(16)
    }
}

// MARK: - Device detail

struct DeviceDetailView: View {
    let device: DeviceStats
    let total: Double

    var body: some View {
        ZStack {
            Fmt.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    statsGrid
                    if let f = device.first, let l = device.last {
                        Text("使用期间：\(Fmt.date(f)) ～ \(Fmt.date(l))")
                            .font(.caption).foregroundColor(.gray)
                    }
                    recordsCard
                    monthlyCard
                    hourlyCard
                }
                .padding(16)
            }
        }
        .navigationTitle(device.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        let share = total > 0 ? device.totalSeconds / total * 100 : 0
        return VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [Fmt.accent.opacity(0.5), Fmt.accent.opacity(0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Image(systemName: Fmt.symbol(for: device.displayName))
                    .font(.system(size: 40)).foregroundColor(.white)
            }
            Text(Fmt.hm(device.totalSeconds))
                .font(.system(size: 32, weight: .bold)).foregroundColor(.white)
            Text(String(format: "占全部佩戴 %.0f%%", share))
                .font(.caption).foregroundColor(.gray)
            VolumeBadge(avgDb: device.avgDb)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var statsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                box("佩戴次数", "\(device.sessionCount)")
                box("平均每次", Fmt.hm(device.avgSessionSeconds))
                box("最长一次", Fmt.hm(device.longestSession))
            }
            HStack(spacing: 14) {
                box("日均", Fmt.hm(device.dailyAvgSeconds))
                box("活跃天数", "\(device.activeDayCount) 天")
                box("≥80 dB", String(format: "%.0f%%", device.ge80Percent))
            }
        }
    }

    private func box(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline).bold().foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Fmt.card)
        .cornerRadius(10)
    }

    private var recordsCard: some View {
        let lib = device.library
        return VStack(alignment: .leading, spacing: 4) {
            Text("这副耳机的记录").font(.headline).foregroundColor(.white).padding(.bottom, 4)
            if let d = lib.longestDay {
                row("单日最长", Fmt.hm(d.seconds), sub: Fmt.prettyDay(d.day))
            }
            if let s = lib.longestSession {
                row("单次最长", Fmt.hm(s.duration), sub: Fmt.date(s.start))
            }
            if let st = lib.longestStreak {
                row("最长连续使用", "\(st.days) 天",
                    sub: "\(Fmt.prettyDay(st.from)) ～ \(Fmt.prettyDay(st.to))")
            }
            if let m = lib.bestMonth {
                row("单月最高", Fmt.hm(m.seconds), sub: Fmt.prettyMonth(m.month))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Fmt.card)
        .cornerRadius(16)
    }

    private func row(_ title: String, _ value: String, sub: String) -> some View {
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

    private var monthlyCard: some View {
        let months = device.monthly
        let maxSec = max(months.map(\.seconds).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("每月时长").font(.headline).foregroundColor(.white)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(months.enumerated()), id: \.offset) { idx, m in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Fmt.accent.opacity(m.seconds > 0 ? 1 : 0.25))
                            .frame(height: max(3, 70 * m.seconds / maxSec))
                        if idx % 3 == 0 || idx == months.count - 1 {
                            Text(String(m.month.dropFirst(2))).font(.system(size: 8))
                                .foregroundColor(.gray)
                        }
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

    private var hourlyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("24 小时分布").font(.headline).foregroundColor(.white)
            HourlyBars(hourly: device.library.hourlyTotals, height: 48)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Fmt.card)
        .cornerRadius(16)
    }
}
