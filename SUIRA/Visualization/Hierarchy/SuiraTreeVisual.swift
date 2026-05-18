import SwiftUI

/// Вертикальные «хвосты» для детей узла после ├/└.
enum SuiraTreeGutter {
    static func childContinuation(parentGutter: String, parentIsLastSibling: Bool, parentIsRoot: Bool) -> String {
        if parentIsRoot { return "" }
        return parentGutter + (parentIsLastSibling ? "    " : "│   ")
    }
}

private extension Font {
    static var suiraTreeMono: Font {
        .system(.caption, design: .monospaced)
    }
}

/// Строка дерева: моноширинный префикс + произвольный контент + опциональный текст справа.
struct SuiraMonospaceTreeRow<Content: View>: View {
    let gutterPrefix: String
    let isLastSibling: Bool
    let isRoot: Bool
    var trailing: String?
    @ViewBuilder var content: () -> Content

    private var branch: String {
        guard !isRoot else { return "" }
        return gutterPrefix + (isLastSibling ? "└── " : "├── ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(branch)
                .font(.suiraTreeMono)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.leading)
            content()
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
