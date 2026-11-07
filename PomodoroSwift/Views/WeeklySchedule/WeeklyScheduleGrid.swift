import SwiftUI

struct WeeklyScheduleGrid: View {
    let events: [WeeklyScheduleEvent]
    let calendarEvents: [ScheduleCalendarEvent]
    let dates: [Date]
    let startMinute: Int
    let endMinute: Int
    let minimumFontSize: Double
    let now: Date
    let textColor: Color
    @Binding var selectedDay: ScheduleWeekday
    let onEdit: (WeeklyScheduleEvent) -> Void
    let onAdd: (ScheduleWeekday, Int) -> Void

    @State private var selectedCalendarEvent: ScheduleCalendarEvent?
    private let gutter: CGFloat = 52
    private let headerHeight: CGFloat = 26
    private let verticalInset: CGFloat = 8
    private var ticks: [Int] {
        Array(Set([startMinute, endMinute] + stride(from: (startMinute / 60 + 1) * 60,
                                                  to: endMinute, by: 60))).sorted()
    }
    private func y(_ minute: Int, height: CGFloat) -> CGFloat {
        CGFloat(minute - startMinute) / CGFloat(max(1, endMinute - startMinute)) * height
    }

    // Keep boundary labels visible without overlapping hour labels in compact, full-day views.
    private func labelTicks(height: CGFloat) -> [Int] {
        var result = [startMinute]
        for tick in ticks where tick > startMinute && tick < endMinute {
            guard let previous = result.last else { break }
            if y(tick, height: height) - y(previous, height: height) >= 16,
               y(endMinute, height: height) - y(tick, height: height) >= 16 {
                result.append(tick)
            }
        }
        result.append(endMinute)
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = max(1, (geometry.size.width - gutter) / CGFloat(max(dates.count, 1)))
            let gridHeight = max(1, geometry.size.height - headerHeight - 1 - verticalInset * 2)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("时间").font(.caption2)
                        .frame(width: gutter, height: headerHeight)
                    ForEach(dates, id: \.self) { date in
                        dayHeader(date, width: columnWidth)
                    }
                }
                .foregroundStyle(textColor)
                Rectangle().fill(textColor.opacity(0.12)).frame(height: 1)
                HStack(alignment: .top, spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        ForEach(labelTicks(height: gridHeight), id: \.self) { minute in
                            Text(WeeklyScheduleMath.timeLabel(minute))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(textColor.opacity(0.6))
                                .padding(.trailing, 7)
                                .offset(y: y(minute, height: gridHeight) - 6)
                        }
                    }
                    .frame(width: gutter, height: gridHeight, alignment: .topTrailing)
                    ForEach(dates, id: \.self) { date in
                        dayColumn(date, width: columnWidth, height: gridHeight)
                    }
                }
                .padding(.vertical, verticalInset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .clipped()
        .popover(item: $selectedCalendarEvent) { ScheduleCalendarEventDetails(event: $0) }
    }

    private func dayHeader(_ date: Date, width: CGFloat) -> some View {
        let weekday = ScheduleWeekday.from(date)
        let isToday = Calendar.current.isDate(date, inSameDayAs: now)
        return Button { selectedDay = weekday } label: {
            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    Text(weekday.title).fontWeight(.semibold)
                    if isToday { Circle().fill(Color.accentColor).frame(width: 5, height: 5) }
                }
                .font(.system(size: 12))
            }
            .frame(width: width, height: headerHeight)
            .background(selectedDay == weekday ? textColor.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weekday.title + (isToday ? "，今天" : ""))
    }

    private func dayColumn(_ date: Date, width: CGFloat, height gridHeight: CGFloat) -> some View {
        let weekday = ScheduleWeekday.from(date)
        let external = calendarEvents.compactMap { ScheduleCalendarProjection.event($0, on: date) }
        let placements = WeeklyScheduleMath.placements(
            events: events + external, weekday: weekday, start: startMinute, end: endMinute
        )
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(textColor.opacity(weekday.rawValue > 5 ? 0.04 : 0.015))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    let minute = startMinute + Int(location.y / gridHeight * CGFloat(endMinute - startMinute))
                    onAdd(weekday, min(max(minute / 15 * 15, startMinute), endMinute - 15))
                }
                .onTapGesture { selectedDay = weekday }
                .accessibilityLabel("\(weekday.title)时间网格，双击添加日程")

            ForEach(ticks, id: \.self) { minute in
                Rectangle().fill(textColor.opacity(minute % 60 == 0 ? 0.12 : 0.06))
                    .frame(height: 0.5)
                    .offset(y: y(minute, height: gridHeight))
                    .allowsHitTesting(false)
            }
            Rectangle().fill(textColor.opacity(0.1)).frame(width: 0.5)
                .allowsHitTesting(false)

            ForEach(placements) { placement in
                eventBlock(placement, columnWidth: width, gridHeight: gridHeight)
            }

            if Calendar.current.isDate(date, inSameDayAs: now) {
                let minute = WeeklyScheduleMath.minuteOfDay(now)
                if minute >= startMinute && minute <= endMinute {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.red).frame(height: 1)
                        Circle().fill(.red).frame(width: 5, height: 5)
                    }
                    .offset(y: y(minute, height: gridHeight) - 2)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: width, height: gridHeight)
        .clipped()
    }

    private func eventBlock(_ placement: ScheduleEventPlacement, columnWidth: CGFloat, gridHeight: CGFloat) -> some View {
        let event = placement.event
        let width = (columnWidth - 8) / CGFloat(placement.columnCount)
        let height = max(3, y(placement.range.end, height: gridHeight) - y(placement.range.start, height: gridHeight) - 2)
        let external = calendarEvents.first { $0.id == event.id }
        let tint = external?.color.tint ?? event.color.tint
        return Button {
            if let external { selectedCalendarEvent = external }
            else { onEdit(event) }
        } label: {
            HStack(alignment: .top, spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
                ScheduleEventText(
                    title: event.title,
                    time: "\(WeeklyScheduleMath.timeLabel(event.startMinute))—\(WeeklyScheduleMath.timeLabel(event.endMinute))",
                    isCalendarEvent: external != nil, textColor: textColor,
                    minimumFontSize: minimumFontSize,
                    width: max(1, width - 15), height: max(1, height - 6)
                )
                .padding(.vertical, 3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .frame(width: max(1, width - 2), height: height, alignment: .topLeading)
            .foregroundStyle(textColor)
            .background(tint.opacity(0.24), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(tint.opacity(0.4), lineWidth: 0.5))
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 6 + CGFloat(placement.column) * width, y: y(placement.range.start, height: gridHeight) + 1)
        .help(external.map { "\($0.title)\n日历：\($0.calendarTitle)\n\(WeeklyScheduleMath.timeLabel(event.startMinute))—\(WeeklyScheduleMath.timeLabel(event.endMinute))\n点击查看，修改请前往系统日历" }
              ?? "\(event.title)\n每周\(event.weekdays.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: "、"))\n\(WeeklyScheduleMath.timeLabel(event.startMinute))—\(WeeklyScheduleMath.timeLabel(event.endMinute))\n点击编辑")
        .accessibilityLabel("\(event.title)，\(WeeklyScheduleMath.timeLabel(event.startMinute))至\(WeeklyScheduleMath.timeLabel(event.endMinute))，\(external == nil ? "点击编辑" : "来自日历，点击查看")")
    }
}
