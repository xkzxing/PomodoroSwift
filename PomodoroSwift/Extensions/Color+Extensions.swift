import SwiftUI

extension Color {
    /// Returns a Boolean value indicating whether the color is considered "dark".
    /// This is used to determine contrasting text color.
    var isDark: Bool {
        // Try getting components from cgColor
        // This works for custom colors created with RGB values and most system colors in newer OS versions
        if let components = self.cgColor?.components, components.count >= 2 {
            let r = components[0]
            let g = components[1] // If grayscale, g and b = r
            let b = components.count >= 3 ? components[2] : r
            
            // Luminance formula: 0.2126 R + 0.7152 G + 0.0722 B
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return luminance < 0.5
        }
        
        // Fallback: Assume light (return false) so text is black
        return false
    }
    
    /// Returns a contrasting text color (black or white) based on the color's luminance.
    var contrastingTextColor: Color {
        return isDark ? .white : .black
    }
}
