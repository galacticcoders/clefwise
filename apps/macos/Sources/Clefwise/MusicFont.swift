import CoreText
import Foundation

/// Bravura, the SMuFL font every staff is drawn with. It's loaded straight from its file (never
/// registered with the system), at four points to the em: SMuFL's em is four staff spaces, so its
/// outlines come out in staff spaces.
///
/// The file is looked for in the app bundle (`build-app.sh` copies it to `Contents/Resources`),
/// then at `CLEFWISE_MUSIC_FONT` (a path, for harnesses that build a copy of the sources), then
/// in `apps/macos/Resources/Fonts`, walking up from this source file (`swift run`, `swift test`).
enum MusicFont {
    /// Where the font was found; nil if it wasn't.
    static let url: URL? = locate()

    /// The font at size 4 (one em, four staff spaces, to the point); nil if it couldn't be loaded.
    static let font: CTFont? = {
        guard let url else {
            assertionFailure("Bravura.otf not found: not in the app bundle, at CLEFWISE_MUSIC_FONT, or in apps/macos/Resources/Fonts")
            return nil
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            assertionFailure("Couldn't read a font from \(url.path)")
            return nil
        }
        return CTFontCreateWithFontDescriptor(descriptor, 4, nil)
    }()

    /// The glyph's outline in staff spaces, y down, from its SMuFL origin. Empty if the font is missing.
    static func outline(_ glyph: SMuFL.Glyph) -> CGPath {
        outline(codePoint: glyph.rawValue)
    }

    /// Any SMuFL code point's outline, cached.
    static func outline(codePoint: UInt32) -> CGPath {
        cache.outline(codePoint) { makeOutline(codePoint) }
    }

    /// Where the glyph is inked, in staff spaces, y down from its origin.
    static func bounds(_ glyph: SMuFL.Glyph) -> CGRect {
        let box = outline(glyph).boundingBoxOfPath
        return box.isNull ? .zero : box
    }

    /// How far the glyph moves the pen, in staff spaces.
    static func advance(_ glyph: SMuFL.Glyph) -> CGFloat {
        guard let font, var cgGlyph = cgGlyph(glyph.rawValue, in: font) else { return 0 }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &cgGlyph, &advance, 1)
        return advance.width
    }

    /// Whether the font has a glyph for `glyph`.
    static func hasGlyph(_ glyph: SMuFL.Glyph) -> Bool {
        font.flatMap { cgGlyph(glyph.rawValue, in: $0) } != nil
    }

    // MARK: - Loading

    private static func locate() -> URL? {
        let files = FileManager.default
        if let url = Bundle.main.url(forResource: "Bravura", withExtension: "otf") { return url }
        if let path = ProcessInfo.processInfo.environment["CLEFWISE_MUSIC_FONT"], files.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.pathComponents.count > 1 {
            for relative in ["Resources/Fonts/Bravura.otf", "apps/macos/Resources/Fonts/Bravura.otf"] {
                let candidate = directory.appendingPathComponent(relative)
                if files.fileExists(atPath: candidate.path) { return candidate }
            }
            directory = directory.deletingLastPathComponent()
        }
        return nil
    }

    private static func cgGlyph(_ codePoint: UInt32, in font: CTFont) -> CGGlyph? {
        guard let scalar = Unicode.Scalar(codePoint) else { return nil }
        var utf16 = Array(String(Character(scalar)).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count), glyphs[0] != 0 else { return nil }
        return glyphs[0]
    }

    private static func makeOutline(_ codePoint: UInt32) -> CGPath {
        guard let font, let glyph = cgGlyph(codePoint, in: font) else { return CGMutablePath() }
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        return CTFontCreatePathForGlyph(font, glyph, &flip) ?? CGMutablePath()
    }

    private static let cache = OutlineCache()

    /// Outlines by code point, made once each; drawing can happen on any thread.
    private final class OutlineCache: @unchecked Sendable {
        private let lock = NSLock()
        private var outlines: [UInt32: CGPath] = [:]

        func outline(_ codePoint: UInt32, make: () -> CGPath) -> CGPath {
            lock.lock()
            defer { lock.unlock() }
            if let outline = outlines[codePoint] { return outline }
            let outline = make()
            outlines[codePoint] = outline
            return outline
        }
    }
}
