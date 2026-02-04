# PomodoroSwift

A beautiful, native macOS Pomodoro timer application built with SwiftUI. It features a modern, aesthetic interface with glassmorphism effects and high customizability.

## Features

- **Timer Functionality**: 
  - Standard Pomodoro timer with customizable duration.
  - Quick restart actions (Same time, +5 min, +10 min) via notifications.
  - Visual circular timer display.

- **Aesthetic Design**:
  - **Glassmorphism**: Advanced "Liquid Glass" effect with customizable transparency, tint, and shimmer.
  - **Interactive Elements**: Buttons and panels react to hover and click states with smooth animations.
  - **Sidebar**: A sleek, collapsible sidebar for settings, featuring a frosted glass look.

- **Customization**:
  - **Background**: Set your own custom background image.
  - **Typography**: Choose any installed system font for the timer display.
  - **Appearance**: Adjust glass tint color and opacity to match your wallpaper.

## Requirements

- macOS 12.0+ (Estimated based on SwiftUI usage)
- Xcode 14.0+ for development

## Project Structure

- **Models**: Core logic for the Timer (`PomodoroTimer.swift`) and App Settings (`Settings.swift`).
- **Views**: SwiftUI views including the main `ContentView`, `TimerView`, and custom UI components like `GlassButton`.
- **Extensions**: Helper utilities for colors and other types.

## Usage

1. **Start Timer**: Click the "Start" button to begin the countdown.
2. **Settings**: Open the sidebar (icon in top-left) to access personalization options.
   - Change the font face.
   - Adjust the glass effect (clear vs. regular, tint color).
   - Upload a custom background image.
3. **Notifications**: The app will notify you when the timer completes, allowing you to restart or extend the session directly from the notification.
