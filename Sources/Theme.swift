import SwiftUI

// The Android palette and building blocks (Page, Heading, Action, CardPanel, Hebrew).
// Like Android, the app keeps its light palette in system Dark Mode: every colour below is
// explicit and the root view prefers the light scheme, so text stays readable.

enum Palette {
    static let ink = hex(0x183A3E)
    static let teal = hex(0x126F68)
    static let sand = hex(0xFAF6EE)
    static let gold = hex(0xF1CB84)
    static let muted = hex(0x526567)
    static let mint = hex(0xE1F0EA)
    static let danger = hex(0x9F3030)
    static let retry = hex(0xFFEDCC)
    /// A checked practice answer (iOS): green when right, red (with the danger border) when wrong.
    static let correct = hex(0x2E7D4A)
    static let correctFill = hex(0xDCF2E1)
    static let wrongFill = hex(0xFBE3E1)

    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255.0,
              green: Double((value >> 8) & 0xFF) / 255.0,
              blue: Double(value & 0xFF) / 255.0)
    }
}

/// Android's countText: a left-to-right isolate keeps "3 / 5" and Latin pronunciation
/// guides in reading order inside right-to-left text.
func isolatedLTR(_ text: String) -> String {
    "\u{2066}" + text + "\u{2069}"
}

/// Android sizes in sp grow with the font scale; these sizes grow with Dynamic Type.
struct ScaledFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    @ScaledMetric(relativeTo: .largeTitle) private var largeScale: CGFloat = 100
    @ScaledMetric(relativeTo: .title) private var titleScale: CGFloat = 100
    @ScaledMetric(relativeTo: .body) private var bodyScale: CGFloat = 100
    @ScaledMetric(relativeTo: .footnote) private var smallScale: CGFloat = 100

    init(size: CGFloat, weight: Font.Weight) {
        self.size = size
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale / 100, weight: weight))
    }

    private var scale: CGFloat {
        if size >= 34 { return largeScale }
        if size >= 22 { return titleScale }
        if size >= 15 { return bodyScale }
        return smallScale
    }
}

extension View {
    @MainActor
    func appFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFont(size: size, weight: weight))
    }
}

/// The id of a page's whole content, for scrolling back to its top.
private let pageContentId = "page-content"

/// Android's Page: a scrolling column, at most 1100 points wide, 20 points of padding. When
/// `focus` changes to the id of a view on the page, the page scrolls just enough to show that
/// view whole (not at all if it is already on screen); when `start` changes, the page goes
/// back to its top.
struct Page<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let maxWidth: CGFloat
    private let focus: String?
    private let start: String?
    private let content: (CGFloat) -> Content

    init(maxWidth: CGFloat = 1100, focus: String? = nil, start: String? = nil,
         @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.maxWidth = maxWidth
        self.focus = focus
        self.start = start
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, min(proxy.size.width, maxWidth) - 40)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content(width)
                    }
                    .padding(20)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .id(pageContentId)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focus) { _, target in
                    guard let target = target else { return }
                    scroll(reader, to: target, anchor: nil, animated: true)
                }
                .onChange(of: start) { _, _ in
                    scroll(reader, to: pageContentId, anchor: .top, animated: false)
                }
            }
        }
    }

    /// Scrolls after this update, once new views have been laid out; never animated with
    /// Reduce Motion.
    private func scroll(_ reader: ScrollViewProxy, to id: String, anchor: UnitPoint?, animated: Bool) {
        let animation: Animation? = animated && !reduceMotion ? .easeOut(duration: 0.25) : nil
        Task { @MainActor in
            withAnimation(animation) {
                reader.scrollTo(id, anchor: anchor)
            }
        }
    }
}

struct Heading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appFont(30, .bold)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle = subtitle {
                Text(subtitle)
                    .appFont(18)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Android's Action: a full-width button, teal or (secondary) mint.
struct ActionStyle: ButtonStyle {
    var secondary = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        ActionStyleBody(configuration: configuration, secondary: secondary)
    }
}

private struct ActionStyleBody: View {
    let configuration: ButtonStyleConfiguration
    let secondary: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(labelColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fillColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private var labelColor: Color {
        if !isEnabled { return Palette.ink.opacity(0.42) }
        return secondary ? Palette.ink : Color.white
    }

    private var fillColor: Color {
        if !isEnabled { return Palette.ink.opacity(0.08) }
        return secondary ? Palette.mint : Palette.teal
    }
}

struct ActionButton: View {
    let title: String
    var identifier: String = ""
    var enabled: Bool = true
    var secondary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(18, .semibold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(ActionStyle(secondary: secondary))
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }
}

/// Android's CardPanel: rounded 26, padding 22, a hairline border.
struct CardPanel<Content: View>: View {
    private let color: Color
    private let content: Content

    init(color: Color = Color.white, @ViewBuilder content: () -> Content) {
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Palette.ink.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Android's Hebrew(): right-aligned, right-to-left, full width, generous line height.
struct HebrewText: View {
    let text: String
    var size: CGFloat = 32
    var color: Color = Palette.ink

    var body: some View {
        Text(text)
            .appFont(size)
            .lineSpacing(size * 0.2)
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
    }
}

/// A plain line of text in the interface colour that wraps instead of truncating.
struct BodyText: View {
    let text: String
    var size: CGFloat = 18
    var weight: Font.Weight = .regular
    var color: Color = Palette.ink

    var body: some View {
        Text(text)
            .appFont(size, weight)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Wraps its children into rows. Placement is explicit: right-to-left fills each row from
/// the right edge. The layout itself is always evaluated left-to-right, so SwiftUI does not
/// mirror the explicit placement a second time.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var rightToLeft: Bool = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews, maxWidth: maxWidth)
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for (index, row) in rows.enumerated() {
            height += row.height + (index > 0 ? lineSpacing : 0)
            widest = max(widest, row.width)
        }
        if maxWidth.isFinite {
            return CGSize(width: maxWidth, height: height)
        }
        return CGSize(width: widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = rightToLeft ? bounds.maxX : bounds.minX
            for item in row.items {
                let origin: CGPoint
                if rightToLeft {
                    x -= item.size.width
                    origin = CGPoint(x: x, y: y)
                    x -= spacing
                } else {
                    origin = CGPoint(x: x, y: y)
                    x += item.size.width + spacing
                }
                subviews[item.index].place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(item.size))
            }
            y += row.height + lineSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            if !row.items.isEmpty && row.width + spacing + size.width > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(Item(index: index, size: size))
        }
        if !row.items.isEmpty {
            rows.append(row)
        }
        return rows
    }
}

/// Android's FlowRow, in an explicit reading direction. FlowLayout places the rows itself and
/// is evaluated left-to-right; the items keep the surrounding direction, so in Arabic and
/// Hebrew a chip's check mark stays on its leading (right) side, as in Android's FlowRow.
struct FlowRow<Content: View>: View {
    @Environment(\.layoutDirection) private var direction
    private let rightToLeft: Bool
    private let spacing: CGFloat
    private let lineSpacing: CGFloat
    private let content: Content

    init(rightToLeft: Bool, spacing: CGFloat = 8, lineSpacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.rightToLeft = rightToLeft
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content()
    }

    var body: some View {
        // The layout is called as a value (Layout.callAsFunction), as Minik's
        // CardsPageFillLayout is, rather than with a trailing closure on its initializer.
        let layout = FlowLayout(spacing: spacing, lineSpacing: lineSpacing, rightToLeft: rightToLeft)
        let itemDirection = direction
        layout {
            content
                .environment(\.layoutDirection, itemDirection)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// Android's LinearProgressIndicator.
struct ProgressBar: View {
    let value: Double
    let track: Color

    private var fraction: Double { min(max(value, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(Palette.teal)
                    .frame(width: proxy.size.width * CGFloat(fraction))
            }
        }
        .frame(height: 6)
        .accessibilityRepresentation {
            ProgressView(value: fraction)
        }
    }
}

/// Android's FilterChip.
struct ChipButton: View {
    let title: String
    let selected: Bool
    var identifier: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark")
                        .appFont(15, .semibold)
                        .accessibilityHidden(true)
                }
                Text(title).appFont(18)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(selected ? Palette.mint : Color.white,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Palette.teal : Palette.ink.opacity(0.2), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

struct LanguageChoices: View {
    let selected: String
    let rightToLeft: Bool
    let onSelect: (String) -> Void

    var body: some View {
        FlowRow(rightToLeft: rightToLeft, spacing: 10, lineSpacing: 10) {
            ForEach(Language.all) { language in
                ChipButton(title: language.name,
                           selected: selected == language.code,
                           identifier: "lang-\(language.code)") {
                    onSelect(language.code)
                }
            }
        }
    }
}

/// The neighbourhood illustration, cropped to fill a rounded frame (decorative).
struct NeighborhoodImage: View {
    let height: CGFloat
    let radius: CGFloat

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                Image("Neighborhood")
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Rows of equal-width cells, like Android's chunked Rows with weight(1f) spacers.
struct GridRows<Item: Identifiable, Cell: View>: View {
    private let items: [Item]
    private let columns: Int
    private let spacing: CGFloat
    private let cell: (Item) -> Cell

    init(items: [Item], columns: Int, spacing: CGFloat = 14, @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.items = items
        self.columns = columns
        self.spacing = spacing
        self.cell = cell
    }

    private var rows: [[Item]] {
        let count = max(columns, 1)
        return stride(from: 0, to: items.count, by: count).map { start in
            Array(items[start..<min(start + count, items.count)])
        }
    }

    var body: some View {
        let count = max(columns, 1)
        let grouped = rows
        VStack(spacing: spacing) {
            ForEach(grouped.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(grouped[index]) { item in
                        cell(item).frame(maxWidth: .infinity)
                    }
                    ForEach(0..<(count - grouped[index].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }
}
