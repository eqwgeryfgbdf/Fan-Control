import Foundation

/// Hardware keys are model-specific, not an Apple-stable API.
/// Mapping adapted from exelban/Stats (MIT); see THIRD_PARTY_NOTICES.md.
public enum SensorMap {
    public static func keys(chip: String) -> (cpu: [String], gpu: [String]) {
        if chip.contains("Apple M4") {
            let gpuFirst = chip.contains("Pro") || chip.contains("Max") ? ["Tg1U", "Tg1k"] : ["Tg0G", "Tg0H"]
            return (["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"],
                    gpuFirst + ["Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"])
        }
        if chip.contains("Apple M1") {
            return (["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"],
                    ["Tg05", "Tg0D", "Tg0L", "Tg0T"])
        }
        if chip.contains("Apple M2") {
            return (["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"], ["Tg0f", "Tg0j"])
        }
        if chip.contains("Apple M3") {
            return (["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"],
                    ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"])
        }
        // Additional generations are added only with a documented mapping.
        // Unknown keys must not be relabelled as CPU/GPU temperatures.
        if !chip.contains("Apple") { return (["TC0P", "TCAD"], ["TG0D", "TGDD"]) }
        return ([], [])
    }
}
