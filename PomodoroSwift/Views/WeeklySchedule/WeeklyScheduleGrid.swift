import SwiftUI

struct WeeklyScheduleGrid: View {
    let events: [WeeklyScheduleEvent]
    let dates: [Date]
    let startMinute: Int
    let endMinute: Int
    let now: Date
    let textColor: Color
    @Binding var selectedDay: ScheduleWeekday
    let onEdit: (WeeklyScheduleEvent) -> Void
    let onAdd: (ScheduleWeekday, Int) -> Void

    @State private var viewportHeight: CGFloat = 320
    private var hourHeight: CGFloat {
        max(20, min(64, (viewportHeight - 76) * 60 / CGFloat(max(15, endMinute - startMinute))))
    }
    private let gutter: CGFloat = 52
    private var gridHeight: CGFloat { CGFloat(endMinute - startMinute) / 60 * hourHeight }
    private var ticks: [Int] {
        Array(Set([startMinute, endMinute] + stride(from: (startMinute / 60 + 1) * 60,
                                                  to: endMinute, by: 60))).sorted()
    }
    private func y(_ minute: Int) -> CGFloat { CGFloat(minute - startMinute) / 60 * hourHeight }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = max(102, (geometry.size.width - gutter) / CGFloat(max(dates.count, 1)))
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("时间").font(.caption2)
                            .frame(width: gutter, height: 58)
                        ForEach(dates, id: \.self) { date in
                            dayHeader(date, width: columnWidth)
                        }
                    }
                    .foregroundStyle(textColor)
                    Divider().overlay(textColor.opacity(0.12))

                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            ZStack(alignment: .topTrailing) {
                                ForEach(ticks, id: \.self) { minute in
                                    Text(WeeklyScheduleMath.timeLabel(minute))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(textColor.opacity(0.6))
                                        .padding(.trailing, 7)
                                        .offset(y: y(minute) - 6)
                                }
                            }
                            .frame(width: gutter, height: gridHeight, alignment: .topTrailing)
                            ForEach(dates, id: \.self) { date in
                                dayColumn(date, width: columnWidth)
                            }
                        }
                        .padding(.vertical, 9)
                    }
                }
                .frame(width: gutter + columnWidth * CGFloat(dates.count))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
    }

    private func dayHeader(_ date: Date, width: CGFloat) -> some View {
        let weekday = ScheduleWeekday.from(date)
        let isToday = Calendar.current.isDate(date, inSameDayAs: now)
        let free = WeeklyScheduleMath.freeRanges(events: events, weekday: weekday, start: startMinute, end: endMinute)
            .reduce(0) { $0 + $1.duration }
        return Button { selectedDay = weekday } label: {
            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    Text(weekday.title).fontWeight(.semibold)
                    Text(date, format: .dateTime.day())
                    if isToday { Circle().fill(Color.accentColor).frame(width: 5, height: 5) }
                }
                .font(.system(size: 12))
                Text("空闲 \(WeeklyScheduleMath.durationLabel(free))")
                    .font(.system(size: 10))
                    .foregroundStyle(textColor.opacity(0.65))
            }
            .frame(width: width, height: 58)
            .background(selectedDay == weekday ? textColor.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(weekday.title)，全天空闲\(WeeklyScheduleMath.durationLabel(free))")
    }

    private func dayColumn(_ date: Date, width: CGFloat) -> some View {
        let weekday = ScheduleWeekday.from(date)
        let placements = WeeklyScheduleMath.placements(
            events: events, weekday: weekday, start: startMinute, end: endMinute
        )
        let freeRanges = WeeklyScheduleMath.freeRanges(
            events: events, weekday: weekday, start: startMinute, end: endMinute
        )
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(textColor.opacity(weekday.rawValue > 5 ? 0.04 : 0.015))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    let minute = startMinute + Int(location.y / hourHeight * 60)
                    onAdd(weekday, min(max(minute / 15 * 15, startMinute), endMinute - 15))
                }
                .onTapGesture { selectedDay = weekday }
                .accessibilityLabel("\(weekday.title)时间网格，双击添加日程")

            ForEach(freeRanges) { range in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.teal.opacity(0.5))
                    .frame(width: 3, height: max(1, y(range.end) - y(range.start) - 2))
                    .offset(x: 1, y: y(range.start) + 1)
                    .allowsHitTesting(false)
            }
            ForEach(ticks, id: \.self) { minute in
                Rectangle().fill(textColor.opacity(minute % 60 == 0 ? 0.12 : 0.06))
                    .frame(height: 0.5)
                    .offset(y: y(minute))
                    .allowsHitTesting(false)
            }
            Rectangle().fill(textColor.opacity(0.1)).frame(width: 0.5)
                .allowsHitTesting(false)

            ForEach(placements) { placement in
                eventBlock(placement, columnWidth: width)
            }

            if Calendar.current.isDate(date, inSameDayAs: now) {
                let minute = WeeklyScheduleMath.minuteOfDay(now)
                if minute >= startMinute && minute <= endMinute {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.red).frame(height: 1)
                        Circle().fill(.red).frame(width: 5, height: 5)
                    }
                    .offset(y: y(minute) - 2)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: width, height: gridHeight)
        .clipped()
    }

    private func eventBlock(_ placement: ScheduleEventPlacement, columnWidth: CGFloat) -> some View {
        let event = placement.event
        let width = (columnWidth - 8) / CGFloat(placement.columnCount)
        let height = max(3, y(placement.range.end) - y(placement.range.start) - 2)
        return Button { onEdit(event) } label: {
            HStack(alignment: .top, spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(event.color.tint).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(height >= 52 ? 2 : 1)
                    if height >= 40 {
                        Text("\(WeeklyScheduleMath.timeLabel(event.startMinute))—\(WeeklyScheduleMath.timeLabel(event.endMinute))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(textColor.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, height < 22 ? 0 : 4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
            .frame(width: max(1, width - 2), height: height, alignment: .topLeading)
            .foregroundStyle(textColor)
            .background(event.color.tint.opacity(0.24), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(event.color.tint.opacity(0.4), lineWidth: 0.5))
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 6 + CGFloat(placement.column) * width, y: y(placement.range.start) + 1)
        .help("\(event.title)\n每周\(event.weekdays.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: "、"))\n\(WeeklyScheduleMath.timeLabel(event.startMinute))—\(WeeklyScheduleMath.timeLabel(event.endMinute))\n点击编辑")
        .accessibilityLabel("\(event.title)，\(WeeklyScheduleMath.timeLabel(event.startMinute))至\(WeeklyScheduleMath.timeLabel(event.endMinute))，点击编辑")
    }
}
