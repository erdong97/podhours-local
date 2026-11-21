import Foundation

// Standalone check of the stats engine against the same synthetic
// vectors the web/Python versions were verified with. Run in CI with:
//   swiftc -O PodsStats/Stats.swift Tests/StatsCheck/main.swift -o statscheck

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL") \(name) \(detail)")
    if !ok { failures += 1 }
}
func approx(_ a: Double, _ b: Double, tol: Double = 0.5) -> Bool { abs(a - b) <= tol }

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
func ts(_ d: Int, _ h: Int, _ mi: Int = 0, _ s: Int = 0) -> TimeInterval {
    var c = DateComponents()
    c.year = 2024; c.month = 1; c.day = d; c.hour = h; c.minute = mi; c.second = s
    return cal.date(from: c)!.timeIntervalSince1970
}
func sample(_ s: TimeInterval, _ e: TimeInterval, _ db: Double,
            name: String, model: String, lid: String) -> RawSample {
    RawSample(start: s, end: e, db: db, name: name, mfr: "Apple Inc.", model: model, lid: lid)
}

let A = "AirPods Pro", AM = "0x2014"
let samples: [RawSample] = [
    sample(ts(1, 10), ts(1, 11), 70, name: A, model: AM, lid: "AAAA"),
    sample(ts(1, 10), ts(1, 11), 70, name: A, model: AM, lid: "AAAA"), // duplicate
    sample(ts(1, 10, 30), ts(1, 11, 30), 80, name: A, model: AM, lid: "AAAA"),
    sample(ts(1, 11, 30, 30), ts(1, 12), 60, name: A, model: AM, lid: "AAAA"),
    sample(ts(3, 9), ts(3, 9, 0, 30), 90, name: A, model: AM, lid: "AAAA"), // burst
    sample(ts(2, 20), ts(2, 21), 75, name: A, model: AM, lid: "CCCC"),      // same device, other lid
    sample(ts(5, 8), ts(5, 8, 20), 65, name: "EarPods", model: "0x2002", lid: "DDDD"),
]

let engine = StatsEngine(timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
let computed = engine.compute(samples: samples)
let devices = computed.devices
let combined = computed.combined
let library = combined.library

check("device count == 2", devices.count == 2, "got \(devices.count)")
let airpods = devices.first { $0.displayName == "AirPods Pro" }
check("AirPods found", airpods != nil)
if let a = airpods {
    check("AirPods total 10800s", approx(a.totalSeconds, 10800), "got \(a.totalSeconds)")
    check("AirPods sessions == 2", a.sessionCount == 2, "got \(a.sessionCount)")
    check("AirPods longest 7170s", approx(a.longestSession, 7170), "got \(a.longestSession)")
    check("AirPods avg 75.2 dB", approx(a.avgDb, 75.2, tol: 0.06), "got \(a.avgDb)")
    check("AirPods >=80 1830s", approx(a.ge80Seconds, 1830), "got \(a.ge80Seconds)")
    check("AirPods active days == 3", a.activeDayCount == 3, "got \(a.activeDayCount)")
    check("AirPods daily avg 3600s", approx(a.dailyAvgSeconds, 3600), "got \(a.dailyAvgSeconds)")
}
let earpods = devices.first { $0.displayName == "EarPods" }
check("EarPods total 1200s", earpods.map { approx($0.totalSeconds, 1200) } ?? false,
      "got \(earpods?.totalSeconds ?? -1)")
check("EarPods avg 65.0 dB", earpods.map { approx($0.avgDb, 65.0, tol: 0.06) } ?? false,
      "got \(earpods?.avgDb ?? -1)")
check("Combined total 12000s", approx(combined.totalSeconds, 12000), "got \(combined.totalSeconds)")
check("Combined avg 74.8 dB", approx(combined.avgDb, 74.8, tol: 0.06), "got \(combined.avgDb)")
check("Combined sessions == 3", combined.sessionCount == 3, "got \(combined.sessionCount)")
check("Combined active days == 4", combined.activeDayCount == 4, "got \(combined.activeDayCount)")
check("Combined daily avg 2400s", approx(combined.dailyAvgSeconds, 2400), "got \(combined.dailyAvgSeconds)")

// Library aggregates (trends & records)
let dailySum = library.dailyTotals.values.reduce(0, +)
check("Daily totals sum 12000s", approx(dailySum, 12000), "got \(dailySum)")
check("Longest day 2024-01-01 / 7170s",
      library.longestDay?.day == "2024-01-01" && approx(library.longestDay?.seconds ?? -1, 7170),
      "got \(String(describing: library.longestDay))")
check("Longest session 7170s on AirPods",
      approx(library.longestSession?.duration ?? -1, 7170) && library.longestSession?.deviceName == "AirPods Pro",
      "got \(String(describing: library.longestSession?.duration))")
check("Longest streak 3 days", library.longestStreak?.days == 3, "got \(String(describing: library.longestStreak?.days))")
check("Best month 2024-01 / 12000s",
      library.bestMonth?.month == "2024-01" && approx(library.bestMonth?.seconds ?? -1, 12000),
      "got \(String(describing: library.bestMonth))")
let hourlySum = library.hourlyTotals.values.reduce(0, +)
check("Hourly totals sum 12000s", approx(hourlySum, 12000), "got \(hourlySum)")
check("Hour 10 == 3600s", approx(library.hourlyTotals[10] ?? -1, 3600), "got \(library.hourlyTotals[10] ?? -1)")
check("Hour 11 == 3570s", approx(library.hourlyTotals[11] ?? -1, 3570), "got \(library.hourlyTotals[11] ?? -1)")
let bucketSum = library.volumeBuckets.reduce(0) { $0 + $1.seconds }
check("Volume buckets sum 12000s", approx(bucketSum, 12000), "got \(bucketSum)")
check("Bucket 60-70 == 2970s", approx(library.volumeBuckets[1].seconds, 2970), "got \(library.volumeBuckets[1].seconds)")
check("Bucket 70-80 == 7200s", approx(library.volumeBuckets[2].seconds, 7200), "got \(library.volumeBuckets[2].seconds)")
check("Combined avg session 3990s", approx(combined.avgSessionSeconds, 3990), "got \(combined.avgSessionSeconds)")

// Per-device library + day detail (new app structure)
if let a = airpods {
    let al = a.library
    check("AirPods daily sum 10800s", approx(al.dailyTotals.values.reduce(0, +), 10800),
          "got \(al.dailyTotals.values.reduce(0, +))")
    check("AirPods longest day 2024-01-01 / 7170s",
          al.longestDay?.day == "2024-01-01" && approx(al.longestDay?.seconds ?? -1, 7170),
          "got \(String(describing: al.longestDay))")
    check("AirPods streak 3 days", al.longestStreak?.days == 3, "got \(String(describing: al.longestStreak?.days))")
    check("AirPods Jan1 sessions == 1", (al.dailySessions["2024-01-01"] ?? []).count == 1,
          "got \((al.dailySessions["2024-01-01"] ?? []).count)")
    check("AirPods hour 20 == 3600s", approx(al.hourlyTotals[20] ?? -1, 3600), "got \(al.hourlyTotals[20] ?? -1)")
}
check("Jan1 combined avg dB 74.8", approx(library.avgDb(onDay: "2024-01-01") ?? -1, 74.8, tol: 0.15),
      "got \(library.avgDb(onDay: "2024-01-01") ?? -1)")
let allDaySessions = library.dailySessions.values.reduce(0) { $0 + $1.count }
check("Sessions across days == 3", allDaySessions == 3, "got \(allDaySessions)")

print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
