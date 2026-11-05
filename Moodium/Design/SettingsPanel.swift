import SwiftUI

/// Smoky purple glass panel from the visionOS settings design: each row is a segmented
/// switch, changes apply immediately, no save button.
struct SettingsPanel: View {
    @EnvironmentObject private var app: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(app.t("设置", "Settings")).font(.moodium(22, .bold))
                    Spacer()
                    GlassIconButton(symbol: "xmark", size: Panel.control) { close() }
                }
                row(app.t("语言", "Language")) {
                    GlassSegmented(options: [(Language.zh, "中文"), (Language.en, "English")], selection: $app.language)
                }
                row(app.t("感官袋灵敏度", "Bag sensitivity")) {
                    GlassSegmented(options: [(Sensitivity.gentle, app.t("灵敏", "High")),
                                             (Sensitivity.normal, app.t("适中", "Medium")),
                                             (Sensitivity.firm, app.t("稳重", "Low"))],
                                   selection: $app.sensitivity)
                }
            }
            .foregroundStyle(.white)
            .padding(Panel.padding)
            .frame(width: 460)
            .glass(Panel.shape, tint: Palette.smoke, amount: 0.6)
            .offCrease()
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.moodium(16, .medium)).foregroundStyle(Palette.labelUnselected)
                .lineLimit(1).fixedSize()
            Spacer(minLength: 16)
            content()
        }
    }

    private func close() { withAnimation(.easeOut(duration: 0.25)) { isPresented = false } }
}

/// White sliding thumb with dark text on the selected option.
struct GlassSegmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                let selected = value == selection
                Text(title)
                    .font(.moodium(15, .semibold))
                    .foregroundStyle(selected ? Palette.ink : Palette.labelUnselected)
                    .frame(minWidth: 70)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            Capsule().fill(.white)
                                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        guard !selected else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = value }
                    }
            }
        }
        .padding(4)
        .background(Capsule().fill(.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: Panel.hairline))
    }
}
