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

struct SessionInfo {
    var start: Date
    var duration: Double
    var deviceName: String
}

struct DeviceStats {
    var displayName: String
    var subtitle: String
    var totalSeconds: Double = 0
    var avgDb: Double = 0
    var ge80Seconds: Double = 0
    var sessionCount: Int = 0
    var sessionTotalSeconds: Double = 0
    var longestSession: Double = 0
    var activeDayCount: Int = 0
    var dailyAvgSeconds: Double = 0
    var first: Date? = nil
    var last: Date? = nil
    var monthly: [(month: String, seconds: Double)] = []
    // Internal aggregates carried for building the combined view.
    var _days: Set<String> = []
    var _energy: Double = 0
    var _monthlyMap: [String: Double] = [:]

    var ge80Percent: Double {
        totalSeconds > 0 ? ge80Seconds / totalSeconds * 100 : 0
    }
    var avgSessionSeconds: Double {
        sessionCount > 0 ? sessionTotalSeconds / Double(sessionCount) : 0
    }
}

/// Cross-device aggregates used by the Trends and Records tabs.
struct LibraryStats {
    /// Local day ("yyyy-MM-dd") -> listening seconds (all devices summed).
    var dailyTotals: [String: Double] = [:]
    /// Hour of day 0...23 -> listening seconds.
    var hourlyTotals: [Int: Double] = [:]
    /// Volume bucket label -> listening seconds, in display order.
    var volumeBuckets: [(label: String, seconds: Double)] = []
    var longestDay: (day: String, seconds: Double)? = nil
    var longestSession: SessionInfo? = nil
    var longestStreak: (days: Int, from: String, to: String)? = nil
    var bestMonth: (month: String, seconds: Double)? = nil
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

    struct Portion {
        var start: TimeInterval
        var end: TimeInterval
        var db: Double
        var duration: Double { end - start }
    }

    struct Computed {
        var devices: [DeviceStats]
        var combined: DeviceStats
        var library: LibraryStats
        var portionsByDevice: [String: [Portion]]
    }

    func compute(samples: [RawSample]) -> Computed {
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
        var portionsByDevice: [String: [Portion]] = [:]
        var allSessions: [SessionInfo] = []
        for (_, g) in merged {
            let parts = portions(for: g.samples)
            let displayName = !g.name.isEmpty ? g.name : (!g.model.isEmpty ? g.model : "未知耳机")
            portionsByDevice[displayName] = parts
            var st = DeviceStats(
                displayName: displayName,
                subtitle: [g.mfr, g.model].filter { !$0.isEmpty }.joined(separator: " · ")
            )
            let sessions = fill(&st, from: parts)
            devices.append(st)
            allSessions.append(contentsOf: sessions.map {
                SessionInfo(start: $0.start, duration: $0.duration, deviceName: displayName)
            })
        }
        devices.sort { $0.totalSeconds > $1.totalSeconds }
        let combined = combine(devices)
        let library = libraryStats(portionsByDevice: portionsByDevice,
                                   sessions: allSessions,
                                   monthlyMap: combined._monthlyMap)
        return Computed(devices: devices, combined: combined,
                        library: library, portionsByDevice: portionsByDevice)
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

    /// Fills a DeviceStats from its portions; returns the counted sessions.
    private func fill(_ st: inout DeviceStats, from parts: [Portion]) -> [SessionInfo] {
        guard let firstPart = parts.first else { return [] }
        var energy = 0.0
        var days = Set<String>()
        var monthly: [String: Double] = [:]
        var rawSessions: [(start: TimeInterval, duration: Double)] = []
        var current: Double = 0
        var currentStart: TimeInterval = firstPart.start
        var prevEnd: TimeInterval? = nil
        for p in parts {
            st.totalSeconds += p.duration
            energy += p.duration * pow(10.0, p.db / 10.0)
            if p.db >= 80 { st.ge80Seconds += p.duration }
            if let pe = prevEnd, p.start - pe > 180 {
                rawSessions.append((currentStart, current))
                current = 0
                currentStart = p.start
            }
            if current == 0 && (prevEnd == nil || p.start - prevEnd! > 180) {
                currentStart = p.start
            }
            current += p.duration
            prevEnd = p.end
            var d = calendar.startOfDay(for: Date(timeIntervalSince1970: p.start))
            let lastDay = calendar.startOfDay(for: Date(timeIntervalSince1970: p.end - 0.001))
            while d <= lastDay {
                days.insert(dayKey(d))
                d = calendar.date(byAdding: .day, value: 1, to: d)!
            }
            monthly[monthKey(Date(timeIntervalSince1970: p.start)), default: 0] += p.duration
        }
        if current > 0 { rawSessions.append((currentStart, current)) }
        let counted = rawSessions.filter { $0.duration >= 60 }
        let effective = counted.isEmpty ? rawSessions : counted
        st.sessionCount = effective.count
        st.sessionTotalSeconds = effective.reduce(0) { $0 + $1.duration }
        st.longestSession = effective.map(\.duration).max() ?? 0
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
        return effective.map { SessionInfo(start: Date(timeIntervalSince1970: $0.start),
                                           duration: $0.duration, deviceName: st.displayName) }
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
            st.sessionTotalSeconds += d.sessionTotalSeconds
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
        st._monthlyMap = monthly
        return st
    }

    // MARK: - Library aggregates (trends & records)

    private func libraryStats(portionsByDevice: [String: [Portion]],
                              sessions: [SessionInfo],
                              monthlyMap: [String: Double]) -> LibraryStats {
        var lib = LibraryStats()
        var buckets: [(label: String, seconds: Double)] = [
            ("<60 dB", 0), ("60–70", 0), ("70–80", 0),
            ("80–85", 0), ("85–90", 0), ("≥90 dB", 0),
        ]
        for (_, parts) in portionsByDevice {
            for p in parts {
                // daily totals: split at midnights
                var t = p.start
                while t < p.end {
                    let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: t))
                    let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dayStart)!.timeIntervalSince1970
                    let segEnd = min(p.end, nextMidnight)
                    lib.dailyTotals[dayKey(Date(timeIntervalSince1970: t)), default: 0] += segEnd - t
                    t = segEnd
                }
                // hourly totals: split at hour boundaries
                t = p.start
                while t < p.end {
                    let d = Date(timeIntervalSince1970: t)
                    let hour = calendar.component(.hour, from: d)
                    let hourStart = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: d))!
                    let nextHour = hourStart.addingTimeInterval(3600).timeIntervalSince1970
                    let segEnd = min(p.end, nextHour)
                    lib.hourlyTotals[hour, default: 0] += segEnd - t
                    t = segEnd
                }
                // volume buckets by the portion's dB
                let idx: Int
                switch p.db {
                case ..<60: idx = 0
                case ..<70: idx = 1
                case ..<80: idx = 2
                case ..<85: idx = 3
                case ..<90: idx = 4
                default: idx = 5
                }
                buckets[idx].seconds += p.duration
            }
        }
        lib.volumeBuckets = buckets
        if let best = lib.dailyTotals.max(by: { $0.value < $1.value }) {
            lib.longestDay = (best.key, best.value)
        }
        lib.longestSession = sessions.max(by: { $0.duration < $1.duration })
        if let best = monthlyMap.max(by: { $0.value < $1.value }) {
            lib.bestMonth = (best.key, best.value)
        }
        // longest streak of consecutive days with any listening
        let days = lib.dailyTotals.keys.sorted()
        var bestRun = 0, run = 0
        var bestFrom = "", bestTo = "", runFrom = ""
        var prev: Date? = nil
        for key in days {
            let date = dayDate(key)
            if let pv = prev, let dt = date,
               calendar.dateComponents([.day], from: pv, to: dt).day == 1 {
                run += 1
            } else {
                run = 1
                runFrom = key
            }
            if run > bestRun {
                bestRun = run
                bestFrom = runFrom
                bestTo = key
            }
            prev = date
        }
        if bestRun > 0 { lib.longestStreak = (bestRun, bestFrom, bestTo) }
        return lib
    }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func dayDate(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return calendar.date(from: c)
    }

    private func monthKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}
