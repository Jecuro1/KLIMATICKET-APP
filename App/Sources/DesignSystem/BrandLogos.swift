import SwiftUI

/// Google "G" drawn with vector arcs (brand colours), for the sign-in button.
struct GoogleLogo: View {
    var size: CGFloat = 18

    var body: some View {
        let line = size * 0.2
        ZStack {
            arc(from: 0.0, to: 0.125, color: Color(red: 0.259, green: 0.522, blue: 0.957))      // blue (right, upper)
            arc(from: 0.625, to: 0.875, color: Color(red: 0.918, green: 0.263, blue: 0.208))    // red (top)
            arc(from: 0.375, to: 0.625, color: Color(red: 0.984, green: 0.737, blue: 0.020))    // yellow (left)
            arc(from: 0.125, to: 0.375, color: Color(red: 0.204, green: 0.659, blue: 0.325))    // green (bottom)
            Rectangle()
                .fill(Color(red: 0.259, green: 0.522, blue: 0.957))
                .frame(width: size * 0.48, height: line)
                .offset(x: size * 0.24 - line * 0.1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func arc(from: CGFloat, to: CGFloat, color: Color) -> some View {
        Circle()
            .trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: size * 0.2, lineCap: .butt))
            .padding(size * 0.1)
    }
}

/// Microsoft four-square logo.
struct MicrosoftLogo: View {
    var size: CGFloat = 18

    var body: some View {
        let gap = size * 0.08
        let tile = (size - gap) / 2
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                Rectangle().fill(Color(red: 0.949, green: 0.314, blue: 0.133)).frame(width: tile, height: tile)
                Rectangle().fill(Color(red: 0.498, green: 0.729, blue: 0.0)).frame(width: tile, height: tile)
            }
            HStack(spacing: gap) {
                Rectangle().fill(Color(red: 0.0, green: 0.643, blue: 0.937)).frame(width: tile, height: tile)
                Rectangle().fill(Color(red: 1.0, green: 0.725, blue: 0.0)).frame(width: tile, height: tile)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
