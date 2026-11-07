import SwiftUI
import UIKit

struct DigitalFontSettingsView: View {
    @EnvironmentObject private var style: CanvasStyle
    @State private var search = ""
    private var names: [String] {
        UIFont.familyNames.sorted().flatMap { UIFont.fontNames(forFamilyName: $0) }
            .filter { search.isEmpty || $0.localizedStandardContains(search) }
    }

    var body: some View {
        List {
            Section {
                MobileDigitalDial(time: "25:00").frame(height: 110)
                    .background { CanvasBackdrop() }.clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("字号", value: "\(Int(style.preferences.digitalFontSize)) 点")
                    Slider(value: $style.preferences.digitalFontSize, in: 32...160, step: 1)
                        .accessibilityLabel("数字表盘字号")
                }.padding(.vertical, 6)
                Button("恢复默认字体") {
                    style.preferences.digitalFontName = "HelveticaNeue"
                    style.preferences.digitalFontSize = 96
                }
            }
            Section("可用字体") {
                ForEach(names, id: \.self) { name in
                    Button { style.preferences.digitalFontName = name } label: {
                        HStack(spacing: 12) {
                            Text("25:00").font(.custom(name, size: 25)).foregroundStyle(AppPalette.ink)
                                .frame(width: 110, alignment: .leading).lineLimit(1).minimumScaleFactor(0.6)
                            Text(name).font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if style.preferences.digitalFontName == name { Image(systemName: "checkmark") }
                        }.frame(minHeight: 44)
                    }
                    .accessibilityAddTraits(style.preferences.digitalFontName == name ? .isSelected : [])
                }
            }
        }
        .navigationTitle("数字字体与字号").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "搜索字体")
    }
}
