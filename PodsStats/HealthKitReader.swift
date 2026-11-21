import Foundation
import HealthKit

/// Reads headphone audio exposure samples straight from HealthKit —
/// the same records the Health export XML contains, no export needed.
/// Read-only: the app never writes anything to HealthKit.
final class HealthKitReader {
    private let store = HKHealthStore()

    enum ReadError: Error {
        case unavailable
    }

    /// Requests read authorization (first run shows the system prompt;
    /// later runs are silent), then returns every headphone audio
    /// exposure sample.
    func fetch() async throws -> [RawSample] {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) else {
            throw ReadError.unavailable
        }
        let readTypes: Set<HKObjectType> = [type]
        let shareTypes: Set<HKSampleType> = []
        // An error here is real (e.g. missing entitlement after a
        // re-sign stripped it) — surface it. A user *denial* is not an
        // error: it just makes the query return zero samples, by
        // HealthKit's privacy design.
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        return try await withCheckedThrowingContinuation { continuation in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            let query = HKSampleQuery(sampleType: type,
                                      predicate: nil,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: sort) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let unit = HKUnit.decibelAWeightedSoundPressureLevel()
                let rows: [RawSample] = (samples as? [HKQuantitySample] ?? []).map { s in
                    RawSample(
                        start: s.startDate.timeIntervalSince1970,
                        end: s.endDate.timeIntervalSince1970,
                        db: (s.quantity.doubleValue(for: unit) * 10).rounded() / 10,
                        name: s.device?.name ?? "",
                        mfr: s.device?.manufacturer ?? "",
                        model: s.device?.model ?? "",
                        lid: s.device?.localIdentifier ?? ""
                    )
                }
                continuation.resume(returning: rows)
            }
            store.execute(query)
        }
    }
}
