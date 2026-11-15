import Foundation
import Testing
@testable import Clefwise

/// A piece's own progress in Progress (2026-11-15): each bar's time, and day by day how fast a bar
/// is read on arrival against the rest of it. The contract the analyzer and the Pieces card build on.
@Suite struct PieceProgressContractTests {
    @Test func theSampleMinuetHasTimesByBarAndDays() throws {
        let minuet = try #require(ProgressReport.sample().pieces.first)
        #expect(minuet.bars.allSatisfy { $0.medianResponseMs != nil })
        // Bar 12 has too few right answers to judge.
        #expect(minuet.bars.first { $0.bar == 12 }?.rightSingleNotes ?? 99 < MethodDay.minimumForTrend)
        #expect(minuet.days.count == 12)
        #expect(minuet.days.map(\.day) == minuet.days.map(\.day).sorted())
        // Reading a bar on arrival gets quicker, and closer to the rest of the bar.
        let first = try #require(minuet.days.first), last = try #require(minuet.days.last)
        #expect(try #require(last.barStartMs) < #require(first.barStartMs))
        #expect(try #require(last.barStartMs) - #require(last.restOfBarMs) < #require(first.barStartMs) - #require(first.restOfBarMs))
        #expect(first.methods == [.keyboard] && last.methods == [.realPiano])
    }

    @Test func aDaysAccuracyIsItsShareRight() {
        let day = PieceDay(day: Date(), answers: 40, correct: 30, barStartMs: 3000, barStarts: 5, restOfBarMs: 900, restOfBar: 25)
        #expect(day.accuracy == 0.75)
        #expect(PieceDay(day: Date(), answers: 0, correct: 0, barStartMs: nil, restOfBarMs: nil).accuracy == nil)
    }
}
