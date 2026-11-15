import Foundation
import SwiftUI
import Testing
@testable import Clefwise

/// The charts by answer method: "What you practised" (stacked columns) and "Over time" (a line per
/// method): their periods, each method's points and gaps, and the columns' parts.
@Suite struct MethodChartTests {
    private let calendar = Calendar.current

    /// The start of a week, so tests know which days share one whatever the first weekday.
    private var weekStart: Date {
        calendar.dateInterval(of: .weekOfYear, for: calendar.date(from: DateComponents(year: 2026, month: 11, day: 4))!)!.start
    }

    private func date(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: weekStart)! }

    private func part(_ method: AnswerMethod, _ answers: Int, correct: Int? = nil, medianMs: Int? = 1000,
                      quartiles: (Int, Int)? = (800, 1300), singles: Int? = nil) -> MethodDay {
        let correct = correct ?? answers
        return MethodDay(method: method, answers: answers, correct: correct, medianResponseMs: medianMs,
                         lowerQuartileMs: quartiles?.0, upperQuartileMs: quartiles?.1, rightSingleNotes: singles ?? correct)
    }

    /// A day whose totals are its methods' (plus `other` answers in no method).
    private func day(_ offset: Int, _ parts: [MethodDay], other: Int = 0, practiceSeconds: Double = 60) -> DayProgress {
        DayProgress(day: date(offset), answers: parts.map(\.answers).reduce(0, +) + other,
                    correct: parts.map(\.correct).reduce(0, +), practiceSeconds: parts.isEmpty && other == 0 ? 0 : practiceSeconds,
                    medianResponseMs: parts.first?.medianResponseMs, methods: parts)
    }

    // MARK: - Periods

    @Test func bothChartsGoByWeekPastFortyFiveDays() {
        let days = (0..<46).map { day($0, [part(.keyboard, 10)]) }
        #expect(!TrendPeriod.isWeekly(Array(days.prefix(45))))
        #expect(TrendPeriod.periods(for: Array(days.prefix(45))).count == 45)
        #expect(TrendPeriod.isWeekly(days))
        let weeks = TrendPeriod.periods(for: days)
        #expect(weeks.allSatisfy { $0.isWeek })
        // Calendar weeks from the first day: 46 days from a week's start make six full and a part week.
        #expect(weeks.count == 7)
        #expect(weeks.map(\.answers).reduce(0, +) == 460)
        #expect(weeks.allSatisfy { $0.part(.keyboard)?.answers == $0.answers })
        #expect(weeks.first?.label.hasPrefix("Week of") == true)
    }

    @Test func aWeekAddsUpEachMethodAsTheWholeDoes() throws {
        let days = [day(0, [part(.keyboard, 10, correct: 9, medianMs: 1000, quartiles: (800, 1200)),
                            part(.realPiano, 20, medianMs: 5000, quartiles: (4000, 6500))]),
                    day(1, []),
                    day(2, [part(.keyboard, 20, correct: 18, medianMs: 1400, quartiles: (1000, 1900), singles: 15)],
                        practiceSeconds: 90),
                    day(3, [part(.keyboard, 30, correct: 30, medianMs: 1200, quartiles: (1000, 1300)),
                            part(.realPiano, 10, medianMs: 4000, quartiles: (3500, 4500))])]
        let week = try #require(TrendPeriod.weeks(of: days).first)
        #expect(TrendPeriod.weeks(of: days).count == 1)
        #expect(week.answers == 90 && week.practiceSeconds == 210)
        #expect(week.methods.map(\.method) == [.keyboard, .realPiano])

        let keyboard = try #require(week.part(.keyboard))
        #expect(keyboard.answers == 60 && keyboard.correct == 57 && keyboard.rightSingleNotes == 54)
        // The middle of its daily medians and spreads (400, 900, 300 ms), as the whole's.
        #expect(keyboard.medianResponseMs == 1200)
        #expect(keyboard.spreadMs == 400)
        #expect(keyboard.lowerQuartileMs == nil && keyboard.upperQuartileMs == nil)

        let piano = try #require(week.part(.realPiano))
        #expect(piano.answers == 30)
        // Two days: the upper middle, as the whole takes it.
        #expect(piano.medianResponseMs == 5000 && piano.spreadMs == 2500)
        #expect(week.part(.guitar) == nil)
    }

    @Test func aDayKeepsItsMethodsQuartiles() throws {
        let period = TrendPeriod(day: day(0, [part(.guitar, 12, medianMs: 16_000, quartiles: (12_000, 20_000))]))
        let guitar = try #require(period.part(.guitar))
        #expect(guitar.lowerQuartileMs == 12_000 && guitar.upperQuartileMs == 20_000 && guitar.spreadMs == 8000)
    }

    @Test func methodsInTheRangeComeInTheFixedOrder() {
        let days = [day(0, [part(.guitar, 30)]), day(1, []), day(2, [part(.keyboard, 10), part(.realPiano, 5)])]
        #expect(TrendPeriod.methods(in: days) == [.keyboard, .realPiano, .guitar])
        #expect(TrendPeriod.methods(in: [day(0, [])]).isEmpty)
    }

    // MARK: - Points and gaps

    @Test func aPointNeedsFiveOfWhatItMeasures() {
        #expect(MethodDay.minimumForTrend == 5)
        // Four answers: no accuracy, nor anything else.
        let four = MethodPeriod(day: part(.keyboard, 4))
        #expect(TrendMeasure.accuracy.value(four) == nil && TrendMeasure.accuracy.readout(four) == nil)
        // Five answers but four right: an accuracy, no typical time.
        let fourRight = MethodPeriod(day: part(.keyboard, 5, correct: 4, medianMs: 1500))
        #expect(abs((TrendMeasure.accuracy.value(fourRight) ?? 0) - 80) < 1e-9)
        #expect(TrendMeasure.accuracy.readout(fourRight) == "80%")
        #expect(TrendMeasure.responseTime.value(fourRight) == nil)
        // Five right, but only four of them single notes: a time, no spread.
        let chords = MethodPeriod(day: part(.keyboard, 6, correct: 5, medianMs: 1500, singles: 4))
        #expect(TrendMeasure.responseTime.value(chords) == 1.5)
        #expect(TrendMeasure.spread.value(chords) == nil)
        let enough = MethodPeriod(day: part(.keyboard, 6, correct: 5, medianMs: 1500, quartiles: (1000, 2250), singles: 5))
        #expect(TrendMeasure.spread.value(enough) == 1.25)
    }

    @Test func eachMethodsLineBreaksAtItsOwnGaps() {
        let periods = [day(0, [part(.keyboard, 10), part(.realPiano, 10)]),
                       day(1, [part(.keyboard, 10)]),
                       day(2, []),
                       day(3, [part(.keyboard, 10), part(.realPiano, 3)]),
                       day(4, [part(.realPiano, 8)])].map(TrendPeriod.init(day:))
        let points = TrendMeasure.accuracy.points(in: periods)
        #expect(points.map(\.method) == [.keyboard, .keyboard, .keyboard, .realPiano, .realPiano])

        let keyboard = points.filter { $0.method == .keyboard }
        #expect(keyboard.map(\.start) == [date(0), date(1), date(3)])
        // Day 2 breaks the line; day 3 stands alone, so it gets a marker.
        #expect(keyboard[0].series == keyboard[1].series && keyboard[1].series != keyboard[2].series)
        #expect(keyboard.map(\.isAlone) == [false, false, true])

        // The real piano's three answers on day 3 are a gap in its line alone.
        let piano = points.filter { $0.method == .realPiano }
        #expect(piano.map(\.start) == [date(0), date(4)])
        #expect(piano.allSatisfy { $0.isAlone })
        #expect(Set(points.map(\.series)).count == 4 && Set(points.map(\.id)).count == 5)
        #expect(keyboard[0].x == periods[0].middle)
    }

    @Test func theSamplesPointsAllMeetTheMinimum() {
        let periods = TrendPeriod.periods(for: ProgressReport.sample().days)
        for measure in [TrendMeasure.accuracy, .responseTime, .spread] {
            let points = measure.points(in: periods)
            #expect(!points.isEmpty)
            for point in points {
                let part = periods.first { $0.start == point.start }?.part(point.method)
                #expect(part.map(measure.evidence) ?? 0 >= MethodDay.minimumForTrend)
            }
        }
    }

    // MARK: - Columns

    @Test func columnsStackInMethodOrderWithAnythingElseOnTop() {
        let period = TrendPeriod(day: day(0, [part(.keyboard, 30), part(.buttons, 0), part(.realPiano, 20), part(.guitar, 10)],
                                          other: 5))
        let segments = MixColumn.segments(of: period)
        #expect(segments.map(\.method) == [.keyboard, .realPiano, .guitar, nil])
        #expect(segments.map(\.lower) == [0, 30, 50, 60])
        #expect(segments.map(\.upper) == [30, 50, 60, 65])
        #expect(segments.map(\.isTop) == [false, false, false, true])
        #expect(segments.last?.name == "Other")
        #expect(period.otherAnswers == 5)
        // No practice, no column.
        #expect(MixColumn.segments(of: TrendPeriod(day: day(1, []))).isEmpty)
    }

    @Test func partsStandAGapApartFromTheBaselineToTheTop() {
        let period = TrendPeriod(day: day(0, [part(.keyboard, 30), part(.realPiano, 20), part(.guitar, 10)]))
        let drawn = MixColumn.segments(of: period).map { $0.drawn(gap: 2, minimum: 1) }
        // The foot on the baseline, the top at the total, 2 apart between.
        #expect(drawn == [0...29, 31...49, 51...60])

        // A part smaller than the gaps still shows, the minimum tall.
        let thin = TrendPeriod(day: day(0, [part(.keyboard, 30), part(.realPiano, 1), part(.guitar, 1)]))
        #expect(MixColumn.segments(of: thin).map { $0.drawn(gap: 2, minimum: 1) } == [0...29, 30...31, 31...32])
    }

    @Test func columnsAreAtMostTwentyFourWide() {
        let month = (0..<30).map { TrendPeriod(day: day($0, [part(.keyboard, 10)])) }
        #expect(MixColumn.width(for: month, plotWidth: 900) == 24)
        // 300 pt for 30 days: 10 a day, less the gap (a day longer for a clock change aside).
        #expect(abs(MixColumn.width(for: month, plotWidth: 300) - 8) < 0.05)
        #expect(MixColumn.width(for: Array(month.prefix(1)), plotWidth: 300) == 24)
        #expect(MixColumn.width(for: month, plotWidth: 20) == 1)
    }

    @Test func dateLabelsByTheEdgesHangInwards() {
        let month = (0..<30).map { TrendPeriod(day: day($0, [part(.keyboard, 10)])) }
        #expect(TrendPeriod.axisAnchor(month[29].middle, in: month) == .topTrailing)
        // The second day's middle is 1.5 days in: 14 pt of 280, too close for a centred label.
        #expect(TrendPeriod.axisAnchor(month[1].middle, in: month) == .topLeading)
        // In a wide plot it's 45 pt in: room enough.
        #expect(TrendPeriod.axisAnchor(month[1].middle, in: month, plotWidth: 900) == .top)
        #expect(TrendPeriod.axisAnchor(month[15].middle, in: month) == .top)
        #expect(TrendPeriod.axisAnchor(nil, in: month) == .top)
    }
}
