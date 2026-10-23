import Foundation
import FanCore

let args = CommandLine.arguments
let count = args.dropFirst().first.flatMap(Int.init) ?? 3
guard count >= 1, count <= 60 else { fputs("Usage: MacminiProbe [1...60 samples]\n", stderr); exit(2) }
let reader = SensorReader()
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.sortedKeys]
for i in 0..<count {
    let sample = reader.sample()
    print(String(data: try encoder.encode(sample), encoding: .utf8)!)
    if i+1 < count { Thread.sleep(forTimeInterval: 1) }
}
