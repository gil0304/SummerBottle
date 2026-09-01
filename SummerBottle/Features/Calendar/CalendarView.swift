//
//  CalendarView.swift
//  SummerBottle
//
//  カレンダータブ。月グリッドでボトル(思い出)を振り返る。
//  - 日曜始まりの月グリッド(前後月の日はうっすら表示)
//  - 月送り: < > ボタン + 左右スワイプ
//  - ボトルがある日: 小さな瓶アイコン + 複数なら件数バッジ
//  - 日付タップ → その日のボトル一覧シート → タップで 3D 鑑賞へ
//

import SwiftUI

// MARK: - カレンダー画面

struct CalendarView: View {
    @Environment(BottleStore.self) private var store
    @Environment(AppRouter.self) private var router

    /// 表示中の月(その月の1日 0:00)
    @State private var displayedMonth: Date
    /// シート表示対象の日
    @State private var selectedDay: CalendarDaySelection?

    private let calendar: Calendar

    init() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // 日曜始まり
        cal.locale = Locale(identifier: "ja_JP")
        self.calendar = cal
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        self._displayedMonth = State(initialValue: monthStart)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                monthHeader
                weekdayHeader
                monthGrid
                if monthBottleCount == 0 {
                    emptyMonthState
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle("カレンダー")
        .sheet(item: $selectedDay) { selection in
            CalendarDayBottleListSheet(
                day: selection.day,
                bottles: bottles(on: selection.day),
                onSelect: { bottleID in
                    selectedDay = nil
                    // シートが閉じ切ってからプッシュする
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        router.open(.viewer(bottleID))
                    }
                }
            )
        }
    }

    // MARK: 月ヘッダ

    private var isSummerMonth: Bool {
        (6...8).contains(calendar.component(.month, from: displayedMonth))
    }

    private var isDisplayingCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private var monthHeader: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("前の月")

                Spacer()

                HStack(spacing: 6) {
                    Text(displayedMonth.yearMonthString)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    if isSummerMonth {
                        Image(systemName: "sun.max.fill")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.sunset)
                            .accessibilityLabel("夏")
                    }
                }

                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("次の月")
            }
            .foregroundStyle(AppTheme.ocean)

            if !isDisplayingCurrentMonth {
                Button("今月へ戻る") {
                    goToCurrentMonth()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 曜日ヘッダ

    private static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(weekdayColor(for: index))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekdayColor(for index: Int) -> Color {
        switch index {
        case 0: AppTheme.coral          // 日曜
        case 6: AppTheme.ocean          // 土曜
        default: Color.secondary
        }
    }

    // MARK: 月グリッド

    private var monthGrid: some View {
        VStack(spacing: 4) {
            ForEach(weeks(in: displayedMonth), id: \.self) { week in
                HStack(spacing: 4) {
                    ForEach(week, id: \.self) { date in
                        dayCell(for: date)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    // 横方向のスワイプだけ月送りにする
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -40 {
                        changeMonth(by: 1)
                    } else if value.translation.width > 40 {
                        changeMonth(by: -1)
                    }
                }
        )
        .animation(.snappy, value: displayedMonth)
    }

    /// 表示月の週配列(日曜始まり、前後月の日を含む)
    private func weeks(in month: Date) -> [[Date]] {
        guard
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
            let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        let leading = calendar.component(.weekday, from: monthStart) - calendar.firstWeekday
        let leadingCount = (leading + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingCount, to: monthStart) else { return [] }

        let totalDays = leadingCount + dayRange.count
        let weekCount = (totalDays + 6) / 7

        var result: [[Date]] = []
        for weekIndex in 0..<weekCount {
            var week: [Date] = []
            for dayIndex in 0..<7 {
                if let date = calendar.date(byAdding: .day, value: weekIndex * 7 + dayIndex, to: gridStart) {
                    week.append(date)
                }
            }
            result.append(week)
        }
        return result
    }

    // MARK: 日セル

    private func dayCell(for date: Date) -> some View {
        let dayNumber = calendar.component(.day, from: date)
        let isInMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(date)
        let dayBottles = bottles(on: date)
        let weekdayIndex = (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7

        return VStack(spacing: 3) {
            Text("\(dayNumber)")
                .font(.footnote.weight(isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(dayNumberColor(weekdayIndex: weekdayIndex, isToday: isToday))

            ZStack {
                if dayBottles.isEmpty {
                    Color.clear
                } else {
                    // 複数なら奥にもう1本うっすら重ねる
                    if dayBottles.count > 1 {
                        CalendarBottleGlyph()
                            .fill(AppTheme.deepSea.opacity(0.45))
                            .frame(width: 10, height: 15)
                            .offset(x: 5)
                    }
                    CalendarBottleGlyph()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.ocean, AppTheme.deepSea],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 10, height: 15)
                        .offset(x: dayBottles.count > 1 ? -2 : 0)
                }
            }
            .frame(width: 22, height: 16)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(dayBottles.isEmpty ? Color.clear : AppTheme.ocean.opacity(0.10))
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.coral, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if dayBottles.count > 1 {
                Text("\(dayBottles.count)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(AppTheme.coral))
                    .padding(2)
            }
        }
        .opacity(isInMonth ? 1 : 0.3)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !dayBottles.isEmpty else { return }
            Haptics.tap()
            selectedDay = CalendarDaySelection(day: calendar.startOfDay(for: date))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(for: date, bottleCount: dayBottles.count, isToday: isToday))
    }

    private func dayNumberColor(weekdayIndex: Int, isToday: Bool) -> Color {
        if isToday { return AppTheme.coral }
        switch weekdayIndex {
        case 0: return AppTheme.coral.opacity(0.85)
        case 6: return AppTheme.ocean.opacity(0.9)
        default: return Color.primary
        }
    }

    private func accessibilityText(for date: Date, bottleCount: Int, isToday: Bool) -> String {
        var text = date.japaneseDateString
        if isToday { text += "、今日" }
        if bottleCount > 0 { text += "、ボトル\(bottleCount)本" }
        return text
    }

    // MARK: 空状態

    private var emptyMonthState: some View {
        VStack(spacing: 10) {
            CalendarBottleGlyph()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 22, height: 33)
            Text("この月のボトルはまだありません")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if isSummerMonth {
                Text("夏の一日を瓶に閉じ込めてみましょう")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: データ

    /// その日のボトル(表示順は memoryDate 昇順)
    private func bottles(on date: Date) -> [Bottle] {
        store.bottles
            .filter { calendar.isDate($0.memoryDate, inSameDayAs: date) }
            .sorted { $0.memoryDate < $1.memoryDate }
    }

    private var monthBottleCount: Int {
        store.bottles
            .filter { calendar.isDate($0.memoryDate, equalTo: displayedMonth, toGranularity: .month) }
            .count
    }

    // MARK: 月送り

    private func changeMonth(by delta: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        withAnimation(.snappy) {
            displayedMonth = newMonth
        }
        Haptics.tap()
    }

    private func goToCurrentMonth() {
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        withAnimation(.snappy) {
            displayedMonth = monthStart
        }
        Haptics.tap()
    }
}

// MARK: - シート表示対象の日

private struct CalendarDaySelection: Identifiable {
    let day: Date
    var id: Date { day }
}

// MARK: - その日のボトル一覧シート

private struct CalendarDayBottleListSheet: View {
    let day: Date
    let bottles: [Bottle]
    let onSelect: (Bottle.ID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if bottles.isEmpty {
                    Text("この日のボトルはありません")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(bottles) { bottle in
                        Button {
                            Haptics.tap()
                            onSelect(bottle.id)
                        } label: {
                            CalendarBottleRow(bottle: bottle)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(day.japaneseDateString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 一覧の1行

private struct CalendarBottleRow: View {
    let bottle: Bottle

    var body: some View {
        HStack(spacing: 12) {
            BottleThumbnailView(bottle: bottle, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(bottle.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if bottle.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.coral)
                    }
                }

                if let location = bottle.locationName, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let memoryType = bottle.memoryType {
                    Label(memoryType.displayName, systemImage: memoryType.symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("場所の記録なし")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - 小さな瓶シルエット(セル用グリフ)

private struct CalendarBottleGlyph: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        let capHeight = height * 0.12
        let neckHeight = height * 0.20
        let neckWidth = width * 0.36
        let capWidth = neckWidth * 1.5
        let bodyTop = rect.minY + capHeight + neckHeight
        let corner = width * 0.28

        // 栓(コルク)
        path.addRoundedRect(
            in: CGRect(
                x: rect.midX - capWidth / 2,
                y: rect.minY,
                width: capWidth,
                height: capHeight
            ),
            cornerSize: CGSize(width: capHeight * 0.4, height: capHeight * 0.4)
        )

        // 首(胴と隙間なくつなぐ)
        path.addRect(
            CGRect(
                x: rect.midX - neckWidth / 2,
                y: rect.minY + capHeight,
                width: neckWidth,
                height: neckHeight + corner * 0.5
            )
        )

        // 胴
        path.addRoundedRect(
            in: CGRect(
                x: rect.minX,
                y: bodyTop,
                width: width,
                height: rect.maxY - bodyTop
            ),
            cornerSize: CGSize(width: corner, height: corner)
        )

        return path
    }
}
