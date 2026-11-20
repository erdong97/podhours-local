import Foundation

// Standalone check of the stats engine against the same synthetic
// vectors the web/Python versions were verified with. Run in CI with:
//   swiftc -O PodHours/Stats.swift Tests/StatsCheck/main.swift -o statscheck

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
let (devices, combined) = engine.compute(samples: samples)

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

print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
