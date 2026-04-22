import Foundation

final class ChartSettingsStorage {
    static let defaultKey = "com.cryptory.chart.settings.v1"

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = ChartSettingsStorage.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> ChartSettingsState {
        guard let data = defaults.data(forKey: key) else {
            return .default
        }

        do {
            return try decoder.decode(ChartSettingsState.self, from: data).normalized
        } catch {
            AppLogger.debug(.lifecycle, "[ChartSettings] restore_failed key=\(key) error=\(error.localizedDescription)")
            return .default
        }
    }

    func save(_ state: ChartSettingsState) {
        do {
            let data = try encoder.encode(state.normalized)
            defaults.set(data, forKey: key)
        } catch {
            AppLogger.debug(.lifecycle, "[ChartSettings] save_failed key=\(key) error=\(error.localizedDescription)")
        }
    }
}
