//
//  TimeSelector.swift
//  PomodoroSwift
//
//

import SwiftUI

struct TimeSelector: View {
    @Binding var selectedTime: Int
    @State private var dragOffset: CGFloat = 0
    @State private var velocity: CGFloat = 0
    @State private var viewWidth: CGFloat = 800
    @State private var isDragging: Bool = false
    
    let times = Array(stride(from: 5, through: 120, by: 5))
    let itemWidth: CGFloat = 70
    
    var body: some View {
        VStack(spacing: 8) {
            // Center indicator dot
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .shadow(color: .white.opacity(0.8), radius: 8)
                .zIndex(2)
            
            // Custom Dragger
            ZStack(alignment: .center) {
                // The scrolling content
                HStack(spacing: 0) {
                    ForEach(times, id: \.self) { time in
                        TimeOptionView(
                            time: time,
                            isSelected: selectedTime == time
                        )
                        .frame(width: itemWidth)
                    }
                }
                .offset(x: currentOffset)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            isDragging = true
                            dragOffset = value.translation.width
                            velocity = value.velocity.width
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        let predictedEndOffset = value.translation.width + (value.velocity.width * 0.3)
                        finalizeSelection(with: predictedEndOffset)
                    }
            )
            .onScroll(perform: { deltaX in
                let speedMultiplier: CGFloat = 2.0
                let newOffset = dragOffset + deltaX * speedMultiplier
                
                // Clamp: don't allow scrolling past the first or last item
                let currentIndex = times.firstIndex(of: selectedTime) ?? 0
                let maxLeftOffset = CGFloat(currentIndex) * itemWidth  // can't go past first item
                let maxRightOffset = -CGFloat(times.count - 1 - currentIndex) * itemWidth  // can't go past last item
                dragOffset = min(maxLeftOffset, max(maxRightOffset, newOffset))
            }, onEnd: {
                finalizeSelection(with: dragOffset)
            })
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.2),
                        .init(color: .black, location: 0.8),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 80)
            .clipped()
            .contentShape(Rectangle()) 
        }
    }
    
    // Calculate the total offset to center the selected item
    private var currentOffset: CGFloat {
        let centerIndex = CGFloat(times.firstIndex(of: selectedTime) ?? 0)
        let middleIndex = CGFloat(times.count - 1) / 2.0
        return (middleIndex - centerIndex) * itemWidth + dragOffset
    }
    
    private func finalizeSelection(with predictedDragDistance: CGFloat) {
        // Current index
        let currentIndex = times.firstIndex(of: selectedTime) ?? 0
        
        // How many items did we drag past?
        // Dragging LEFT (negative) means moving to NEXT items (higher index)
        // Dragging RIGHT (positive) means moving to PREV items (lower index)
        
        // We invert the division because dragging left (negative x) moves forward in the list
        let itemsMoved = -Int(round(predictedDragDistance / itemWidth))
        
        // Calculate new valid index
        let newIndex = max(0, min(times.count - 1, currentIndex + itemsMoved))
        let newTime = times[newIndex]
        
        // Reset drag offset with animation while updating selected time
        // This creates the "snap to center" effect
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            selectedTime = newTime
            dragOffset = 0
            velocity = 0
        }
    }
}

struct TimeOptionView: View {
    let time: Int
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(time)")
                .font(.system(size: isSelected ? 40 : 24, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
            if isSelected {
                Text("min")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(width: 70, height: 80)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.3), value: isSelected)
    }
}

#Preview {
    ZStack {
        Color.black
        TimeSelector(selectedTime: .constant(25))
    }
}
