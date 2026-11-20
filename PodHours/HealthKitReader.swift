import Foundation
import HealthKit

/// Reads headphone audio exposure samples straight from HealthKit —
/// the same records the Health export XML contains, no export needed.
/// Read-only: the app never writes anything to HealthKit.
final class HealthKitReader {
    private let store = HKHealthStore()

    enum ReadError: Error {
        case unavailable
        case queryFailed
    }

    /// Requests read authorization (first run shows the system prompt),
    /// then returns every headphone audio exposure sample as plain
    /// dictionaries: s/e = epoch seconds, db = dB(A), plus device fields.
    func readHeadphoneSamples(completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure) else {
            completion(.failure(ReadError.unavailable))
            return
        }
        store.requestAuthorization(toShare: [], read: [type]) { _, _ in
            // Whether the user allowed or denied is intentionally not
            // visible to apps for reads; a denied read just returns
            // zero samples from the query below.
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            let query = HKSampleQuery(sampleType: type,
                                      predicate: nil,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: sort) { _, samples, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let unit = HKUnit.decibelAWeightedSoundPressureLevel()
                let rows: [[String: Any]] = (samples as? [HKQuantitySample] ?? []).map { s in
                    [
                        "s": s.startDate.timeIntervalSince1970,
                        "e": s.endDate.timeIntervalSince1970,
                        "db": (s.quantity.doubleValue(for: unit) * 10).rounded() / 10,
                        "name": s.device?.name ?? "",
                        "mfr": s.device?.manufacturer ?? "",
                        "model": s.device?.model ?? "",
                        "lid": s.device?.localIdentifier ?? "",
                    ]
                }
                completion(.success(rows))
            }
            self.store.execute(query)
        }
    }
}
