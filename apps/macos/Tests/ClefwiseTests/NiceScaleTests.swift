import Testing
@testable import Clefwise

@Suite struct NiceScaleTests {
    private func accuracy(_ values: [Double]) -> [Double] {
        NiceScale.ticks(covering: values, minimumSpan: 10, within: 0...100)
    }

    @Test func accuracyNearTheTopIsFocused() {
        // The user's week, 2026-11-03: 93.8–98.2%.
        #expect(accuracy([93.8, 94.5, 98.2, 96.1, 96.9]) == [90, 95, 100])
        // One day, or all at 100%: still ten points tall, ending at 100%.
        #expect(accuracy([97]) == [90, 95, 100])
        #expect(accuracy([100, 100]) == [90, 95, 100])
    }

    @Test func aWiderRangeTakesBiggerSteps() {
        #expect(accuracy([62, 81, 95]) == [60, 70, 80, 90, 100])
        #expect(accuracy([12, 97]) == [0, 25, 50, 75, 100])
        #expect(accuracy([0, 4]) == [0, 5, 10])
    }

    @Test func noValuesShowTheWholeRange() {
        #expect(accuracy([]) == [0, 100])
    }

    @Test func ticksAlwaysCoverTheValues() {
        for values in [[93.8, 98.2], [50.5, 51], [0.4, 99.6], [71, 72, 88], [99.9]] {
            let ticks = accuracy(values)
            #expect(ticks.first! <= values.min()! && ticks.last! >= values.max()!, "\(values) → \(ticks)")
            #expect(ticks.last! - ticks.first! >= 10 && ticks.first! >= 0 && ticks.last! <= 100)
        }
    }
}
