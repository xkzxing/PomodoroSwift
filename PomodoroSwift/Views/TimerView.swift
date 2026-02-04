//
//  TimerView.swift
//  PomodoroSwift
//

import SwiftUI

struct TimerView: View {
    let time: String
    let isCompleted: Bool
    let nsFont: NSFont
    
    var body: some View {
        Text(time)
            .font(Font(nsFont as CTFont))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 0)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.1)
    }
}

#Preview {
    ZStack {
        Color.black
        TimerView(
            time: "25:00",
            isCompleted: false,
            nsFont: NSFont(name: "Helvetica Neue", size: 120) ?? NSFont.systemFont(ofSize: 120)
        )
    }
}
