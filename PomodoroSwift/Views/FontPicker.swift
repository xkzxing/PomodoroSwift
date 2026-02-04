//
//  FontPicker.swift
//  PomodoroSwift
//

import SwiftUI
import AppKit

struct FontPicker: NSViewRepresentable {
    @Binding var selectedFont: NSFont
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Not needed - font panel is global
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(selectedFont: $selectedFont)
    }
    
    class Coordinator: NSObject {
        @Binding var selectedFont: NSFont
        
        init(selectedFont: Binding<NSFont>) {
            _selectedFont = selectedFont
            super.init()
        }
        
        func showFontPanel() {
            let fontManager = NSFontManager.shared
            let fontPanel = NSFontPanel.shared
            
            // Set current font
            fontManager.setSelectedFont(selectedFont, isMultiple: false)
            
            // Set target to receive font changes
            fontManager.target = self
            fontManager.action = #selector(changeFont(_:))
            
            // Show panel
            fontPanel.orderFront(nil)
        }
        
        @objc func changeFont(_ sender: Any?) {
            guard let fontManager = sender as? NSFontManager else { return }
            let newFont = fontManager.convert(selectedFont)
            selectedFont = newFont
        }
    }
    
    static func showPanel(for font: Binding<NSFont>) {
        let coordinator = Coordinator(selectedFont: font)
        coordinator.showFontPanel()
    }
}

// Button to trigger font panel
struct FontPickerButton: View {
    @Binding var selectedFont: NSFont
    @State private var coordinator: FontPicker.Coordinator?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font")
                .font(.headline)
            
            Button(action: {
                if coordinator == nil {
                    coordinator = FontPicker.Coordinator(selectedFont: $selectedFont)
                }
                coordinator?.showFontPanel()
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedFont.displayName ?? selectedFont.fontName)
                            .font(.system(size: 13))
                        Text("\(selectedFont.pointSize, specifier: "%.0f") pt · \(fontWeightDescription)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var fontWeightDescription: String {
        let traits = selectedFont.fontDescriptor.symbolicTraits
        var parts: [String] = []
        
        if traits.contains(.bold) {
            parts.append("Bold")
        }
        if traits.contains(.italic) {
            parts.append("Italic")
        }
        if traits.contains(.condensed) {
            parts.append("Condensed")
        }
        if traits.contains(.expanded) {
            parts.append("Expanded")
        }
        
        if parts.isEmpty {
            return "Regular"
        }
        return parts.joined(separator: ", ")
    }
}
