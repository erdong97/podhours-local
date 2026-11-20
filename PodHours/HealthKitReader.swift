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
        let readTypes: Set<HKObjectType> = [type]
        let shareTypes: Set<HKSampleType> = []
        store.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] _, _ in
            // Whether the user allowed or denied is intentionally not
            // visible to apps for reads; a denied read just returns
            // zero samples from the query below.
            self?.runQuery(type: type, completion: completion)
        }
    }

    private func runQuery(type: HKQuantityType,
                          completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let query = HKSampleQuery(sampleType: type,
                                  predicate: nil,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: sort) { _, samples, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let quantitySamples = samples as? [HKQuantitySample] ?? []
            let rows = quantitySamples.map { self.row(for: $0) }
            completion(.success(rows))
        }
        store.execute(query)
    }

    private func row(for sample: HKQuantitySample) -> [String: Any] {
        let unit = HKUnit.decibelAWeightedSoundPressureLevel()
        let db = (sample.quantity.doubleValue(for: unit) * 10).rounded() / 10
        let device = sample.device
        return [
            "s": sample.startDate.timeIntervalSince1970,
            "e": sample.endDate.timeIntervalSince1970,
            "db": db,
            "name": device?.name ?? "",
            "mfr": device?.manufacturer ?? "",
            "model": device?.model ?? "",
            "lid": device?.localIdentifier ?? "",
        ]
    }
}
