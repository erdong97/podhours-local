import Foundation

/// One raw headphone audio exposure sample (epoch seconds + dB(A)).
struct RawSample {
    var start: TimeInterval
    var end: TimeInterval
    var db: Double
    var name: String
    var mfr: String
    var model: String
    var lid: String
}

struct DeviceStats {
    var displayName: String
    var subtitle: String
    var totalSeconds: Double = 0
    var avgDb: Double = 0
    var ge80Seconds: Double = 0
    var sessionCount: Int = 0
    var longestSession: Double = 0
    var activeDayCount: Int = 0
    var dailyAvgSeconds: Double = 0
    var first: Date? = nil
    var last: Date? = nil
    var monthly: [(month: String, seconds: Double)] = []
    // Internal aggregates carried for building the combined card.
    var _days: Set<String> = []
    var _energy: Double = 0
    var _monthlyMap: [String: Double] = [:]

    var ge80Percent: Double {
        totalSeconds > 0 ? ge80Seconds / totalSeconds * 100 : 0
    }
}

/// Listening-statistics engine. Pure Foundation so it can be compiled
/// and unit-checked on its own (see Tests/StatsCheck). Semantics match
/// the verified web/Python versions exactly:
/// - group samples by Bluetooth id, then merge groups that share
///   name+manufacturer+model into one headphone
/// - sort, drop exact (start,end) duplicates, sweep once: each sample
///   contributes only its not-yet-covered portion, with its own dB
///   (first sample wins on overlaps) for duration, energy-weighted
///   average dB and the >=80 dB share
/// - sessions: portions separated by <=180 s join one session; a
///   session counts when >=60 s (unless every session is shorter)
/// - daily average = total / calendar days from first to last day
struct StatsEngine {
    var calendar: Calendar

    init(timeZone: TimeZone = .current) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        calendar = cal
    }

    private struct Portion {
        var start: TimeInterval
        var end: TimeInterval
        var db: Double
        var duration: Double { end - start }
    }

    func compute(samples: [RawSample]) -> (devices: [DeviceStats], combined: DeviceStats) {
        // 1) group by lid (fallback: identity fields), then merge by name|mfr|model
        var byLid: [String: [RawSample]] = [:]
        var meta: [String: (name: String, mfr: String, model: String)] = [:]
        for s in samples {
            let key = s.lid.isEmpty ? "id|\(s.name)|\(s.mfr)|\(s.model)" : "lid|\(s.lid)"
            byLid[key, default: []].append(s)
            meta[key] = (s.name, s.mfr, s.model)
        }
        var merged: [String: (name: String, mfr: String, model: String, samples: [RawSample])] = [:]
        for (key, group) in byLid {
            let m = meta[key]!
            let mergeKey = "dev|\(m.name)|\(m.mfr)|\(m.model)"
            if var existing = merged[mergeKey] {
                existing.samples.append(contentsOf: group)
                merged[mergeKey] = existing
            } else {
                merged[mergeKey] = (m.name, m.mfr, m.model, group)
            }
        }

        var devices: [DeviceStats] = []
        for (_, g) in merged {
            devices.append(deviceStats(name: g.name, mfr: g.mfr, model: g.model, samples: g.samples))
        }
        devices.sort { $0.totalSeconds > $1.totalSeconds }
        return (devices, combine(devices))
    }

    private func portions(for samples: [RawSample]) -> [Portion] {
        let sorted = samples.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var result: [Portion] = []
        var cursor = -Double.infinity
        var lastKey: String? = nil
        for s in sorted {
            if s.end <= s.start { continue }
            let key = "\(s.start)|\(s.end)"
            if key == lastKey { continue } // exact duplicate
            lastKey = key
            let from = max(s.start, cursor)
            if s.end > from {
                result.append(Portion(start: from, end: s.end, db: s.db))
                cursor = s.end
            }
        }
        return result
    }

    private func deviceStats(name: String, mfr: String, model: String, samples: [RawSample]) -> DeviceStats {
        let parts = portions(for: samples)
        var st = DeviceStats(
            displayName: !name.isEmpty ? name : (!model.isEmpty ? model : "未知耳机"),
            subtitle: [mfr, model].filter { !$0.isEmpty }.joined(separator: " · ")
        )
        fill(&st, from: parts)
        return st
    }

    private func fill(_ st: inout DeviceStats, from parts: [Portion]) {
        guard let firstPart = parts.first else { return }
        var energy = 0.0
        var days = Set<String>()
        var monthly: [String: Double] = [:]
        // sessions
        var sessions: [Double] = []
        var current: Double = 0
        var prevEnd: TimeInterval? = nil
        for p in parts {
            st.totalSeconds += p.duration
            energy += p.duration * pow(10.0, p.db / 10.0)
            if p.db >= 80 { st.ge80Seconds += p.duration }
            if let pe = prevEnd, p.start - pe > 180 {
                sessions.append(current)
                current = 0
            }
            current += p.duration
            prevEnd = p.end
            // active days: every local date this portion touches
            var d = calendar.startOfDay(for: Date(timeIntervalSince1970: p.start))
            let lastDay = calendar.startOfDay(for: Date(timeIntervalSince1970: p.end - 0.001))
            while d <= lastDay {
                days.insert(dayKey(d))
                d = calendar.date(byAdding: .day, value: 1, to: d)!
            }
            monthly[monthKey(Date(timeIntervalSince1970: p.start)), default: 0] += p.duration
        }
        if current > 0 { sessions.append(current) }
        let counted = sessions.filter { $0 >= 60 }
        let effective = counted.isEmpty ? sessions : counted
        st.sessionCount = effective.count
        st.longestSession = effective.max() ?? 0
        st.avgDb = st.totalSeconds > 0 ? 10 * log10(energy / st.totalSeconds) : 0
        st.activeDayCount = days.count
        st.first = Date(timeIntervalSince1970: firstPart.start)
        st.last = Date(timeIntervalSince1970: parts.last!.end)
        if let f = st.first, let l = st.last {
            let span = (calendar.dateComponents([.day],
                from: calendar.startOfDay(for: f),
                to: calendar.startOfDay(for: l)).day ?? 0) + 1
            st.dailyAvgSeconds = st.totalSeconds / Double(max(span, 1))
        }
        st.monthly = monthly.map { (month: $0.key, seconds: $0.value) }.sorted { $0.month < $1.month }
        st._days = days
        st._energy = energy
        st._monthlyMap = monthly
    }

    private func combine(_ devices: [DeviceStats]) -> DeviceStats {
        var st = DeviceStats(displayName: "全部耳机", subtitle: "所有耳机合计")
        var energy = 0.0
        var days = Set<String>()
        var monthly: [String: Double] = [:]
        for d in devices {
            st.totalSeconds += d.totalSeconds
            energy += d._energy
            st.ge80Seconds += d.ge80Seconds
            st.sessionCount += d.sessionCount
            st.longestSession = max(st.longestSession, d.longestSession)
            days.formUnion(d._days)
            for (k, v) in d._monthlyMap { monthly[k, default: 0] += v }
            if let f = d.first, st.first == nil || f < st.first! { st.first = f }
            if let l = d.last, st.last == nil || l > st.last! { st.last = l }
        }
        st.avgDb = st.totalSeconds > 0 ? 10 * log10(energy / st.totalSeconds) : 0
        st.activeDayCount = days.count
        if let f = st.first, let l = st.last {
            let span = (calendar.dateComponents([.day],
                from: calendar.startOfDay(for: f),
                to: calendar.startOfDay(for: l)).day ?? 0) + 1
            st.dailyAvgSeconds = st.totalSeconds / Double(max(span, 1))
        }
        st.monthly = monthly.map { (month: $0.key, seconds: $0.value) }.sorted { $0.month < $1.month }
        return st
    }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func monthKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}
