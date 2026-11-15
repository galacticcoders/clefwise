import Foundation
import Testing
@testable import Clefwise

/// The Pieces card (2026-11-15): each bar's time on the speed map's classes, its tip, and the day
/// chart "Reading a new bar" (points, gaps, date labels, tooltip text).
@Suite struct PieceSectionTests {
    private func bar(_ number: Int, attempts: Int = 10, correct: Int = 9, medianMs: Int? = 1200, singles: Int = 9) -> BarProgress {
        BarProgress(bar: number, attempts: attempts, correct: correct, medianResponseMs: medianMs, rightSingleNotes: singles)
    }

    private func day(_ offset: Int, starts: Int = 8, startMs: Int? = 3000, rest: Int = 40, restMs: Int? = 1000,
                     methods: [AnswerMethod] = [.keyboard]) -> PieceDay {
        PieceDay(day: Date(timeIntervalSinceReferenceDate: Double(offset) * 86_400), answers: 50, correct: 45,
                 barStartMs: startMs, barStarts: starts, restOfBarMs: restMs, restOfBar: rest, methods: methods)
    }

    // MARK: - Bars

    @Test func aBarsTimeTakesTheSpeedMapsClassesAndIsHollowUnderFiveRightAnswers() {
        #expect(PieceSection.timeLevel(of: bar(1, medianMs: 3400)) == 0)
        #expect(PieceSection.timeLevel(of: bar(1, medianMs: 2600)) == 1)
        #expect(PieceSection.timeLevel(of: bar(1, medianMs: 1700)) == 2)
        #expect(PieceSection.timeLevel(of: bar(1, medianMs: 1200)) == 3)
        #expect(PieceSection.timeLevel(of: bar(1, medianMs: 800)) == 4)
        // Too few right answers to single notes, however many answers: hollow.
        #expect(PieceSection.timeLevel(of: bar(1, singles: MethodDay.minimumForTrend - 1)) == nil)
        #expect(PieceSection.timeLevel(of: bar(1, singles: MethodDay.minimumForTrend)) == 3)
        #expect(PieceSection.timeLevel(of: bar(1, medianMs: nil)) == nil)
        #expect(PieceSection.timeLevel(of: nil) == nil)
    }

    @Test func theSampleMinuetsBarTwelveIsTooFewToJudge() throws {
        let minuet = try #require(ProgressReport.sample().pieces.first)
        let twelve = try #require(minuet.bars.first { $0.bar == 12 })
        #expect(PieceSection.timeLevel(of: twelve) == nil)
        #expect(PieceSection.judgedTime(of: twelve) == nil)
        // The slower passage, bars 5–8, is never in the fastest class.
        #expect(minuet.bars.filter { (5...8).contains($0.bar) }.allSatisfy { PieceSection.timeLevel(of: $0) ?? 0 < 4 })
    }

    @Test func aBarsTipSaysItsAccuracyAndTimeOrThatThereAreTooFew() {
        let rows = PieceSection.tipRows(of: bar(3, attempts: 15, correct: 13, medianMs: 2800, singles: 13))
        #expect(rows.map(\.label) == ["Accuracy", "Median time"])
        #expect(rows[0].value == ReportFormat.percent(13, of: 15))
        #expect(rows[0].detail == "13 of 15 answers right")
        #expect(rows[1].value == SpeedScale.seconds(2800))
        #expect(rows[1].detail == "from 13 right answers")

        let few = PieceSection.tipRows(of: bar(4, attempts: 4, correct: 3, medianMs: 2000, singles: 3))
        #expect(few[0].value == nil && few[0].detail == "3 of 4 answers right")
        #expect(few[1].value == nil && few[1].detail == "3 right answers")
        #expect(PieceSection.tipRows(of: bar(5, attempts: 6, correct: 0, medianMs: nil, singles: 0))[1].detail == "No right answers")

        #expect(PieceSection.tipRows(of: nil).isEmpty)
        #expect(PieceSection.tipRows(of: bar(6, attempts: 0, correct: 0)).isEmpty)
    }

    @Test func voiceOverHearsBothMeasures() {
        let value = PieceSection.accessibilityValue(of: bar(1, attempts: 10, correct: 9, medianMs: 1200, singles: 9))
        #expect(value == "\(ReportFormat.percent(9, of: 10)) of 10 answers right; median time \(SpeedScale.seconds(1200))")
        #expect(PieceSection.accessibilityValue(of: bar(1, singles: 2)).hasSuffix("too few right answers to judge its time"))
        #expect(PieceSection.accessibilityValue(of: nil) == "No answers yet")
    }

    @Test func theDayChartSitsBesideTheBarsAtAboutHalfTheCard() {
        #expect(PieceSection.chartWidth(beside: PieceSection.sideBySideWidth) == 364)
        #expect(PieceSection.chartWidth(beside: 1016) == 460)
        #expect(PieceSection.chartWidth(beside: 600) == 340)
        // Beside the bars, the bars keep at least as much room as the chart.
        let width = PieceSection.sideBySideWidth
        #expect(width - PieceSection.columnGap - PieceSection.chartWidth(beside: width) >= PieceSection.chartWidth(beside: width))
    }

    // MARK: - Reading a new bar

    @Test func eachLineHasAPointOnlyWithFiveRightAnswersAndGapsBreakIt() {
        let days = [day(0), day(1), day(2, starts: 4), day(3), day(4), day(5, starts: 2), day(6), day(7, rest: 3)]
        let points = PieceDayLine.points(in: days)
        let starts = points.filter { $0.line == .barStart }
        let rest = points.filter { $0.line == .restOfBar }
        #expect(starts.map(\.slot) == [0, 1, 3, 4, 6, 7])
        #expect(rest.map(\.slot) == [0, 1, 2, 3, 4, 5, 6])
        // Runs: a gap starts a new line; a point between two gaps stands alone.
        #expect(Set(starts.filter { $0.slot <= 1 }.map(\.series)).count == 1)
        #expect(starts.first { $0.slot == 1 }?.series != starts.first { $0.slot == 3 }?.series)
        #expect(starts.filter(\.isAlone).isEmpty)
        #expect(rest.filter(\.isAlone).isEmpty)
        // The rest of the bar is drawn first, under the start of a bar.
        #expect(points.first?.line == .restOfBar && points.last?.line == .barStart)
        #expect(starts.first?.seconds == 3)
        #expect(rest.first?.seconds == 1)
    }

    @Test func aPointWithNoNeighbourStandsAlone() {
        let days = [day(0, starts: 1), day(1), day(2, starts: 0, startMs: nil)]
        let starts = PieceDayLine.points(in: days).filter { $0.line == .barStart }
        #expect(starts.map(\.slot) == [1])
        #expect(starts.first?.isAlone == true)
        // A single day's points both stand alone: no lines, a marker each.
        let single = PieceDayLine.points(in: [day(0)])
        #expect(single.count == 2 && single.allSatisfy(\.isAlone))
        #expect(PieceDayLine.points(in: []).isEmpty)
    }

    @Test func theLatestDayIsAlwaysLabelledAndLabelsNeverTouch() {
        #expect(PieceDayLine.labelledSlots(count: 0, plotWidth: 400).isEmpty)
        #expect(PieceDayLine.labelledSlots(count: 1, plotWidth: 400) == [0])
        // Wide slots: every day.
        #expect(PieceDayLine.labelledSlots(count: 8, plotWidth: 580) == Array(0..<8))
        for (count, width) in [(12, 430.0), (34, 430.0), (60, 586.0), (12, 586.0), (3, 120.0)] as [(Int, CGFloat)] {
            let slots = PieceDayLine.labelledSlots(count: count, plotWidth: width)
            #expect(slots.last == count - 1)
            let padding = PieceDayLine.edgePadding(count: count, plotWidth: width)
            let slotWidth = (width - 2 * padding) / CGFloat(count)
            let gaps = zip(slots, slots.dropFirst()).map { CGFloat($1 - $0) * slotWidth }
            #expect(gaps.allSatisfy { $0 >= PieceDayLine.labelWidth + PieceDayLine.labelGap - 0.001 })
        }
    }

    @Test func narrowSlotsGetRoomAtTheEndsForTheFirstAndLastDates() {
        #expect(PieceDayLine.edgePadding(count: 1, plotWidth: 400) == 0)
        #expect(PieceDayLine.edgePadding(count: 8, plotWidth: 580) == 0)
        for (count, width) in [(34, 430.0), (60, 586.0), (12, 300.0)] as [(Int, CGFloat)] {
            let padding = PieceDayLine.edgePadding(count: count, plotWidth: width)
            #expect(padding > 0)
            // The first slot's middle is half a label in from the edge.
            let firstMiddle = padding + (width - 2 * padding) / CGFloat(count) / 2
            #expect(abs(firstMiddle - PieceDayLine.labelWidth / 2) < 0.001)
        }
    }

    @Test func thePointerPicksTheNearestDay() {
        #expect(PieceDayLine.slot(nearest: -0.4, count: 5) == 0)
        #expect(PieceDayLine.slot(nearest: 1.4, count: 5) == 1)
        #expect(PieceDayLine.slot(nearest: 1.6, count: 5) == 2)
        #expect(PieceDayLine.slot(nearest: 9, count: 5) == 4)
        #expect(PieceDayLine.slot(nearest: 0.3, count: 1) == 0)
    }

    @Test func aDaysTipSaysHowItWasAnsweredItsNotesAndAccuracy() {
        let piano = day(0, methods: [.realPiano])
        #expect(PieceDayLine.summary(of: piano) == "Real piano · 50 notes · \(ReportFormat.percent(45, of: 50)) right")
        #expect(PieceDayLine.methods(of: day(0, methods: [.keyboard, .realPiano])) == "Keyboard and Real piano")
        // Answers in a way this version doesn't know: no method to name.
        #expect(PieceDayLine.methods(of: day(0, methods: [])) == nil)
        #expect(PieceDayLine.summary(of: day(0, methods: [])) == "50 notes · \(ReportFormat.percent(45, of: 50)) right")
    }

    @Test func aTimeUnderFiveRightAnswersIsTooFewToJudge() {
        let thin = day(0, starts: 4, startMs: 2500, rest: 5, restMs: 900)
        #expect(PieceDayLine.barStart.seconds(of: thin) == nil)
        #expect(PieceDayLine.barStart.medianMs(of: thin) == 2500)
        #expect(PieceDayLine.barStart.count(of: thin) == 4)
        #expect(PieceDayLine.restOfBar.seconds(of: thin) == 0.9)
        #expect(PieceDayLine.legendOrder == [.barStart, .restOfBar])
        #expect(PieceDayLine.legendOrder.map(\.label) == ["Start of a bar", "Rest of the bar"])
    }
}
