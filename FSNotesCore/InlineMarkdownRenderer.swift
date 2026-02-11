//
//  InlineMarkdownRenderer.swift
//  FSNotes Inline Markdown Renderer
//
//  A portable, single-file markdown inline renderer for macOS NSTextStorage/NSTextView.
//  Provides live, Bear-like markdown styling without HTML/export functionality.
//
//  ## Purpose
//  This renderer applies real-time markdown styling directly to NSTextStorage as users type,
//  highlighting headers, bold, italic, code spans, fenced code blocks, links, tags, and more.
//  It operates incrementally on edited paragraphs for performance and supports pluggable
//  syntax highlighting for code blocks.
//
//  ## Portability
//  Drop this single file into any macOS project. No FSNotes-specific dependencies.
//  - No references to Note, ViewController, UserDefaultsManagement, etc.
//  - Only requires Foundation and AppKit (NSTextStorage/NSTextView)
//  - Optional external syntax highlighters via CodeHighlighter protocol
//
//  ## Features
//  - **Incremental rendering**: Only processes edited paragraphs for efficiency
//  - **Headers**: ATX (`# Header`) and Setext (`Header\n====`) with scaled fonts
//  - **Bold/Italic**: CommonMark-style `**bold**`, `*italic*`, `__bold__`, `_italic_`
//  - **Code**: Inline `` `code` `` spans and fenced ```code blocks```
//  - **Links**: Autolinks, `[text](url)` inline links
//  - **Tags**: `#hashtag` style tags (optional)
//  - **Lists & Quotes**: Basic styling support
//  - **Strikethrough**: `~~text~~` 
//  - **hideSyntax**: Optional hiding of markdown delimiters (backticks, asterisks, etc.)
//  - **Pluggable highlighter**: Attach external syntax highlighters (e.g., SyntaxKit, Highlightr)
//
//  ## Optional External Highlighters
//  To use a sophisticated highlighter like Highlightr or SyntaxKit:
//  1. Import the library in your project
//  2. Implement the `CodeHighlighter` protocol
//  3. Call `renderer.setHighlighter(yourHighlighter)`
//
//  Example with Highlightr:
//  ```swift
//  import Highlightr
//  
//  class HighlightrAdapter: CodeHighlighter {
//      private let highlightr = Highlightr()!
//      
//      func highlight(code: String, language: String?) -> NSAttributedString {
//          let lang = language ?? "plaintext"
//          return highlightr.highlight(code, as: lang) ?? NSAttributedString(string: code)
//      }
//  }
//  
//  let renderer = InlineMarkdownRenderer()
//  renderer.setHighlighter(HighlightrAdapter())
//  ```
//
//  ## Design Notes
//  - Uses regex patterns for detection (not a full CommonMark parser)
//  - Intentionally pragmatic: focuses on common cases over 100% spec compliance
//  - All UI updates happen on main thread
//  - Thread-safe for single-threaded usage (typical NSTextView scenario)
//
//  Created for FSNotes extraction - 2026
//

#if os(macOS)
import Cocoa
import Foundation

// MARK: - Public API

/// Protocol for pluggable code syntax highlighting.
/// Implement this to provide custom syntax highlighting for fenced code blocks.
public protocol CodeHighlighter {
    /// Highlight the given code with optional language hint.
    /// - Parameters:
    ///   - code: The raw code string to highlight
    ///   - language: Optional language identifier (e.g., "swift", "python")
    /// - Returns: Attributed string with syntax highlighting applied
    func highlight(code: String, language: String?) -> NSAttributedString
}

/// Main inline markdown renderer class.
/// Set this as the delegate of your NSTextStorage to enable live markdown rendering.
public final class InlineMarkdownRenderer: NSObject, NSTextStorageDelegate {
    
    // MARK: - Configuration
    
    /// Rendering options configuration
    public struct Options {
        /// Font for regular text
        public var noteFont: NSFont
        
        /// Font for code spans and blocks
        public var codeFont: NSFont
        
        /// Whether to hide markdown syntax characters (make them nearly invisible)
        public var hideSyntax: Bool
        
        /// Whether to convert #hashtags to clickable links
        public var inlineTags: Bool
        
        /// Default options with system fonts
        public static let `default` = Options(
            noteFont: NSFont.systemFont(ofSize: 14),
            codeFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            hideSyntax: false,
            inlineTags: true
        )
    }
    
    // MARK: - Properties
    
    private let options: Options
    private var highlighter: CodeHighlighter?
    private let codeBlockDetector = CodeBlockDetector()
    
    // MARK: - Initialization
    
    /// Initialize with rendering options
    /// - Parameter options: Configuration options (defaults to Options.default)
    public init(options: Options = .default) {
        self.options = options
        super.init()
        
        // Use built-in default highlighter
        self.highlighter = DefaultInlineHighlighter(codeFont: options.codeFont)
    }
    
    // MARK: - Public Methods
    
    /// Set a custom code highlighter (replaces the default)
    /// - Parameter highlighter: Custom highlighter, or nil to use default
    public func setHighlighter(_ highlighter: CodeHighlighter?) {
        self.highlighter = highlighter ?? DefaultInlineHighlighter(codeFont: options.codeFont)
    }
    
    /// Process entire text storage for initial render
    /// - Parameter textStorage: The text storage to process
    public func processInitial(textStorage: NSTextStorage) {
        guard textStorage.length > 0 else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            textStorage.beginEditing()
            defer { textStorage.endEditing() }
            
            let fullRange = NSRange(location: 0, length: textStorage.length)
            
            // Set base attributes
            self.resetFont(attributedString: textStorage, paragraphRange: fullRange)
            
            // Apply markdown highlighting
            let codeBlockRanges = self.codeBlockDetector.findCodeBlocks(in: textStorage)
            self.highlightMarkdown(
                attributedString: textStorage,
                paragraphRange: fullRange,
                codeBlockRanges: codeBlockRanges
            )
            
            // Highlight code blocks
            for range in codeBlockRanges {
                self.highlightCodeBlock(in: textStorage, range: range)
            }
        }
    }
    
    /// Force a full re-render of the text storage
    /// - Parameter textStorage: The text storage to re-render
    public func forceFullRender(_ textStorage: NSTextStorage) {
        processInitial(textStorage: textStorage)
    }
    
    // MARK: - NSTextStorageDelegate
    
    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // Only process character changes, not attribute-only changes
        guard editedMask.contains(.editedCharacters) else { return }
        guard textStorage.length > 0 else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.processEditing(
                textStorage: textStorage,
                editedRange: editedRange,
                delta: delta
            )
        }
    }
    
    // MARK: - Private Processing Methods
    
    private func processEditing(textStorage: NSTextStorage, editedRange: NSRange, delta: Int) {
        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        
        // Detect code blocks in entire document
        let codeBlockRanges = codeBlockDetector.findCodeBlocks(in: textStorage)
        
        // Get the paragraph range containing the edit
        let paragraphRange = (textStorage.string as NSString).paragraphRange(for: editedRange)
        
        // Apply markdown highlighting to the edited paragraph
        highlightMarkdown(
            attributedString: textStorage,
            paragraphRange: paragraphRange,
            codeBlockRanges: codeBlockRanges
        )
        
        // Re-highlight any code blocks that intersect with the paragraph
        for codeRange in codeBlockRanges {
            if NSIntersectionRange(codeRange, paragraphRange).length > 0 {
                highlightCodeBlock(in: textStorage, range: codeRange)
            }
        }
    }
    
    private func resetFont(attributedString: NSMutableAttributedString, paragraphRange: NSRange) {
        attributedString.addAttribute(.font, value: options.noteFont, range: paragraphRange)
        attributedString.fixAttributes(in: paragraphRange)
    }
    
    private func removeFontTraits(
        _ traitsToRemove: NSFontDescriptor.SymbolicTraits,
        range: NSRange,
        attributedString: NSMutableAttributedString
    ) {
        let baseFont = options.noteFont
        let pointSize = baseFont.pointSize
        
        attributedString.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            
            let currentTraits = font.fontDescriptor.symbolicTraits
            guard !currentTraits.isDisjoint(with: traitsToRemove) else { return }
            
            let newTraits = currentTraits.subtracting(traitsToRemove)
            let newDesc = font.fontDescriptor.withSymbolicTraits(newTraits)
            
            guard let newFont = NSFont(descriptor: newDesc, size: pointSize) else { return }
            attributedString.addAttribute(.font, value: newFont, range: subrange)
        }
    }
    
    private func addFontTraits(
        _ traitsToAdd: NSFontDescriptor.SymbolicTraits,
        range: NSRange,
        attributedString: NSMutableAttributedString
    ) {
        attributedString.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            
            let currentTraits = font.fontDescriptor.symbolicTraits
            let newTraits = currentTraits.union(traitsToAdd)
            let newDesc = font.fontDescriptor.withSymbolicTraits(newTraits)
            
            guard let newFont = NSFont(descriptor: newDesc, size: font.pointSize) else { return }
            attributedString.addAttribute(.font, value: newFont, range: subrange)
        }
    }
    
    private func getHeaderFont(level: Int, baseFont: NSFont, baseFontSize: CGFloat) -> NSFont {
        let headerSize: CGFloat
        
        switch level {
        case 1: headerSize = baseFontSize * 2.0    // #
        case 2: headerSize = baseFontSize * 1.7    // ##
        case 3: headerSize = baseFontSize * 1.4    // ###
        case 4: headerSize = baseFontSize * 1.2    // ####
        case 5: headerSize = baseFontSize * 1.1    // #####
        case 6: headerSize = baseFontSize * 1.05   // ######
        default: headerSize = baseFontSize
        }
        
        let boldTraits: NSFontDescriptor.SymbolicTraits = [.bold]
        let fontDescriptor = baseFont.fontDescriptor
            .withSymbolicTraits(boldTraits)
            .withSize(headerSize)
        
        return NSFont(descriptor: fontDescriptor, size: headerSize) ?? baseFont
    }
    
    private func highlightCodeBlock(in textStorage: NSMutableAttributedString, range: NSRange) {
        guard let highlighter = self.highlighter else { return }
        
        let codeString = textStorage.attributedSubstring(from: range).string
        
        // Extract language from opening fence (e.g., ```swift)
        var language: String? = nil
        if let firstLine = codeString.components(separatedBy: "\n").first {
            let langString = firstLine.replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespaces)
            if !langString.isEmpty {
                language = langString
            }
        }
        
        // Get code content (strip fence markers)
        let lines = codeString.components(separatedBy: "\n")
        let codeContent = lines.dropFirst().dropLast().joined(separator: "\n")
        
        // Get highlighted attributed string
        let highlighted = highlighter.highlight(code: codeContent, language: language)
        
        // Apply attributes from highlighted string to our text storage
        // We keep the original text but apply the highlighting attributes
        highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) { attrs, subrange, _ in
            // Calculate offset (skip first line with fence)
            let firstLineLength = (lines.first?.count ?? 0) + 1 // +1 for newline
            let targetRange = NSRange(
                location: range.location + firstLineLength + subrange.location,
                length: subrange.length
            )
            
            // Only apply if within bounds
            if NSMaxRange(targetRange) <= NSMaxRange(range) && targetRange.location >= range.location {
                textStorage.addAttributes(attrs, range: targetRange)
            }
        }
    }
    
    // MARK: - Core Markdown Highlighting
    
    private func highlightMarkdown(
        attributedString: NSMutableAttributedString,
        paragraphRange: NSRange,
        codeBlockRanges: [NSRange]?
    ) {
        let string = attributedString.string
        let pointSize = options.noteFont.pointSize
        let codeFont = options.codeFont
        
        // Hidden attributes for syntax hiding
        let hiddenFont = NSFont.systemFont(ofSize: 0.1)
        let hiddenColor = NSColor.clear
        let hiddenAttributes: [NSAttributedString.Key: Any] = [
            .font: hiddenFont,
            .foregroundColor: hiddenColor
        ]
        
        func hideSyntaxIfNecessary(range: @autoclosure () -> NSRange) {
            guard options.hideSyntax else { return }
            attributedString.addAttributes(hiddenAttributes, range: range())
        }
        
        // Remove font traits for incremental updates
        if paragraphRange.length != attributedString.length {
            removeFontTraits([.bold, .italic], range: paragraphRange, attributedString: attributedString)
        }
        
        // Clear existing links and strikethrough in paragraph
        attributedString.enumerateAttribute(.link, in: paragraphRange, options: []) { value, range, _ in
            if value != nil {
                attributedString.removeAttribute(.link, range: range)
            }
        }
        
        attributedString.enumerateAttribute(.strikethroughStyle, in: paragraphRange, options: []) { value, range, _ in
            if value != nil {
                attributedString.removeAttribute(.strikethroughStyle, range: range)
            }
        }
        
        // Set base foreground color
        attributedString.addAttribute(.foregroundColor, value: NSColor.textColor, range: paragraphRange)
        
        // MARK: Headers (Setext style: underlined)
        RegexHelper.headersSetextRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            
            attributedString.enumerateAttribute(.font, in: range) { value, subrange, _ in
                guard let font = value as? NSFont else { return }
                let headerFont = self.getHeaderFont(level: 1, baseFont: font, baseFontSize: pointSize)
                attributedString.addAttribute(.font, value: headerFont, range: subrange)
            }
            
            RegexHelper.headersSetextUnderlineRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
        }
        
        // MARK: Headers (ATX style: # prefix)
        RegexHelper.headersAtxRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                  let headerMarksRange = result?.range(at: 1) else { return }
            
            let headerLevel = headerMarksRange.length
            attributedString.enumerateAttribute(.font, in: range) { value, subrange, _ in
                guard let font = value as? NSFont else { return }
                let headerFont = self.getHeaderFont(level: headerLevel, baseFont: font, baseFontSize: pointSize)
                attributedString.addAttribute(.font, value: headerFont, range: subrange)
            }
            
            RegexHelper.headersAtxOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: innerRange)
                let syntaxRange = NSMakeRange(innerRange.location, innerRange.length)
                hideSyntaxIfNecessary(range: syntaxRange)
            }
            
            RegexHelper.headersAtxClosingRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
        }
        
        // MARK: Lists
        RegexHelper.listRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            RegexHelper.listOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: innerRange)
            }
        }
        
        // MARK: Block quotes
        RegexHelper.blockQuoteRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.addAttribute(.foregroundColor, value: NSColor.darkGray, range: range)
            RegexHelper.blockQuoteOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
        }
        
        // MARK: Autolinks
        RegexHelper.autolinkRegex.matches(string, range: paragraphRange) { result in
            guard var range = result?.range else { return }
            var substring = attributedString.mutableString.substring(with: range)
            
            guard !substring.isEmpty else { return }
            
            // Clean up punctuation at end
            if ["!", "?", ";", ":", ".", ",", "_"].contains(substring.last) {
                range = NSRange(location: range.location, length: range.length - 1)
                substring = String(substring.dropLast())
            }
            
            if substring.first == "(" {
                range = NSRange(location: range.location + 1, length: range.length - 1)
                substring = String(substring.dropFirst())
            }
            
            if substring.last == ")" {
                range = NSRange(location: range.location, length: range.length - 1)
                substring = String(substring.dropLast())
            }
            
            if let url = URL(string: substring) {
                attributedString.addAttribute(.link, value: url, range: range)
            } else if let encoded = substring.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
                attributedString.addAttribute(.link, value: encoded, range: range)
            }
        }
        
        // MARK: Inline links [text](url)
        RegexHelper.anchorInlineRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            
            var destinationLink: String?
            
            // Find URL in parentheses
            RegexHelper.coupleRoundRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: innerRange)
                
                if let linkRange = result?.range(at: 3), linkRange.length > 0 {
                    let substring = attributedString.mutableString.substring(with: linkRange)
                    guard !substring.isEmpty else { return }
                    destinationLink = substring
                    attributedString.addAttribute(.link, value: substring, range: linkRange)
                }
                
                hideSyntaxIfNecessary(range: innerRange)
            }
            
            // Hide opening [
            RegexHelper.openingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
            
            // Hide closing ]
            RegexHelper.closingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
            
            // Apply link to [text] part
            guard let destinationLinkString = destinationLink else { return }
            RegexHelper.coupleSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                var _range = innerRange
                _range.location = _range.location + 1
                _range.length = _range.length - 2
                
                let substring = attributedString.mutableString.substring(with: _range)
                guard !substring.isEmpty else { return }
                
                attributedString.addAttribute(.link, value: destinationLinkString, range: _range)
            }
        }
        
        // MARK: Italic
        RegexHelper.strictItalicRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range(at: 3) else { return }
            
            self.addFontTraits([.italic], range: range, attributedString: attributedString)
            
            let preRange = NSMakeRange(range.location - 1, 1)
            attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: preRange)
            hideSyntaxIfNecessary(range: preRange)
            
            let postRange = NSMakeRange(range.location + range.length, 1)
            attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: postRange)
            hideSyntaxIfNecessary(range: postRange)
        }
        
        // MARK: Bold
        RegexHelper.strictBoldRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range(at: 3) else { return }
            
            let boldString = attributedString.attributedSubstring(from: range)
            guard !boldString.string.contains("__") && boldString.string != "_" else { return }
            
            self.addFontTraits([.bold], range: range, attributedString: attributedString)
            
            let preRange = NSMakeRange(range.location - 2, 2)
            attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: preRange)
            hideSyntaxIfNecessary(range: preRange)
            
            let postRange = NSMakeRange(range.location + range.length, 2)
            attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: postRange)
            hideSyntaxIfNecessary(range: postRange)
        }
        
        // MARK: Strikethrough
        RegexHelper.strikeRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            
            let contentRange = NSRange(location: range.location + 2, length: range.length - 4)
            attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            
            let preRange = NSMakeRange(range.location, 2)
            attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: preRange)
            hideSyntaxIfNecessary(range: preRange)
            
            let postRange = NSMakeRange(range.location + range.length - 2, 2)
            attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: postRange)
            hideSyntaxIfNecessary(range: postRange)
        }
        
        // MARK: Inline tags (#hashtag)
        if options.inlineTags {
            RegexHelper.tagsInlineRegex.matches(string, range: paragraphRange) { result in
                guard var range = result?.range(at: 1) else { return }
                
                var substring = attributedString.mutableString.substring(with: range)
                guard !substring.isNumber else { return }
                
                range = NSRange(location: range.location - 1, length: range.length + 1)
                substring = attributedString.mutableString.substring(with: range)
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                    .trimmingCharacters(in: .whitespaces)
                
                guard let tag = substring.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
                
                attributedString.addAttribute(.link, value: "tag://\(tag)", range: range)
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
            }
        }
        
        // MARK: Inline code spans
        RegexHelper.codeSpanRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            
            // Skip if it's a code fence marker
            if attributedString.mutableString.substring(with: range).starts(with: "```") {
                return
            }
            
            attributedString.addAttribute(.font, value: codeFont, range: range)
            attributedString.fixAttributes(in: range)
            
            let codeBackground = NSColor(white: 0.95, alpha: 1.0)
            attributedString.addAttribute(.backgroundColor, value: codeBackground, range: range)
            
            RegexHelper.codeSpanOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
            
            RegexHelper.codeSpanClosingRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NSColor.systemGray, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
        }
    }
}

// MARK: - Code Block Detection

/// Detects fenced code blocks in text storage
private class CodeBlockDetector {
    private let pattern = "(?<=\\n|\\A)```[a-zA-Z0-9]*\\n([\\s\\S]*?)\\n```(?=\\n|\\Z)"
    private let regex: NSRegularExpression
    
    init() {
        do {
            self.regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            fatalError("Invalid code block regex pattern: \(error)")
        }
    }
    
    func findCodeBlocks(in textStorage: NSAttributedString, range searchRange: NSRange? = nil) -> [NSRange] {
        let rangeToSearch = searchRange ?? NSRange(location: 0, length: textStorage.length)
        return regex.matches(in: textStorage.string, options: [], range: rangeToSearch)
            .map { $0.range }
    }
}

// MARK: - Default Code Highlighter

/// Simple built-in code highlighter that applies monospaced font and background
private class DefaultInlineHighlighter: CodeHighlighter {
    private let codeFont: NSFont
    private let backgroundColor: NSColor
    
    init(codeFont: NSFont) {
        self.codeFont = codeFont
        self.backgroundColor = NSColor(white: 0.95, alpha: 1.0)
    }
    
    func highlight(code: String, language: String?) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .backgroundColor: backgroundColor,
            .foregroundColor: NSColor.textColor
        ]
        return NSAttributedString(string: code, attributes: attributes)
    }
}

// MARK: - Regex Helpers

/// Wrapper around NSRegularExpression for convenient matching
private struct RegexHelper {
    let regularExpression: NSRegularExpression
    
    init(pattern: String, options: NSRegularExpression.Options = []) {
        do {
            self.regularExpression = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            print("Regular expression error: \(error)")
            fatalError("Invalid regex pattern")
        }
    }
    
    func matches(_ input: String, range: NSRange, completion: @escaping (NSTextCheckingResult?) -> Void) {
        regularExpression.enumerateMatches(
            in: input,
            options: [],
            range: range
        ) { result, _, _ in
            completion(result)
        }
    }
    
    // MARK: - Regex Pattern Definitions
    
    // Headers (Setext style)
    static let headersSetextRegex = RegexHelper(
        pattern: """
        ^(.+?)
        \\p{Z}*
        \\n
        (==+)
        \\p{Z}*
        \\n|\\Z
        """,
        options: [.allowCommentsAndWhitespace, .anchorsMatchLines]
    )
    
    static let headersSetextUnderlineRegex = RegexHelper(
        pattern: """
        (==+|--+)
        \\p{Z}*$
        """,
        options: [.allowCommentsAndWhitespace]
    )
    
    // Headers (ATX style)
    static let headersAtxRegex = RegexHelper(
        pattern: """
        ^(\\#{1,6}\\ )
        \\p{Z}*
        (.+?)
        \\p{Z}*
        \\#*
        (?:\\n|\\Z)
        """,
        options: [.allowCommentsAndWhitespace, .anchorsMatchLines]
    )
    
    static let headersAtxOpeningRegex = RegexHelper(
        pattern: "^(\\#{1,6}\\ )",
        options: [.allowCommentsAndWhitespace, .anchorsMatchLines]
    )
    
    static let headersAtxClosingRegex = RegexHelper(
        pattern: "\\#{1,6}\\ \\n+",
        options: [.allowCommentsAndWhitespace, .anchorsMatchLines]
    )
    
    // Lists
    static let listRegex = RegexHelper(
        pattern: """
        ^[ ]{0,3}([*+-]|\\d+[.])[ ]+
        """,
        options: [.allowCommentsAndWhitespace, .anchorsMatchLines]
    )
    
    static let listOpeningRegex = RegexHelper(
        pattern: "^[ ]{0,3}([*+-]|\\d+[.])[ ]+",
        options: [.allowCommentsAndWhitespace]
    )
    
    // Block quotes
    static let blockQuoteRegex = RegexHelper(
        pattern: """
        (^[ \\t]*>[ \\t]?.+\\n)
        (.+\\n)*
        \\n*
        """,
        options: [.allowCommentsAndWhitespace, .anchorsMatchLines]
    )
    
    static let blockQuoteOpeningRegex = RegexHelper(
        pattern: "^[ \\t]*>[ \\t]?",
        options: [.anchorsMatchLines]
    )
    
    // Autolinks
    static let autolinkRegex = RegexHelper(
        pattern: "((https?|ftp|file)://[-A-Z0-9+&@#/%?=~_|!:,.;]*[-A-Z0-9+&@#/%=~_|])",
        options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators, .caseInsensitive]
    )
    
    // Inline links
    static let anchorInlineRegex = RegexHelper(
        pattern: """
        (
          !?
          \\[
              ([^\\[\\]]+)
          \\]
          \\(
              \\p{Z}*
              ([^\\s\\)]+)
              \\p{Z}*
              (
              (['"])
              (.*?)
              \\5
              \\p{Z}*
              )?
          \\)
        )
        """,
        options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators]
    )
    
    static let openingSquareRegex = RegexHelper(
        pattern: "(\\[)",
        options: [.allowCommentsAndWhitespace]
    )
    
    static let closingSquareRegex = RegexHelper(
        pattern: "(\\])",
        options: [.allowCommentsAndWhitespace]
    )
    
    static let coupleSquareRegex = RegexHelper(
        pattern: "(\\[.*?\\])",
        options: []
    )
    
    static let coupleRoundRegex = RegexHelper(
        pattern: "(\\(.*?\\))",
        options: []
    )
    
    // Code spans
    static let codeSpanRegex = RegexHelper(
        pattern: """
        (?<![\\\\`])
        (`+)
        (?!`)
        (.+?)
        (?<!`)
        \\1
        (?!`)
        """,
        options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators]
    )
    
    static let codeSpanOpeningRegex = RegexHelper(
        pattern: "(?<![\\\\`])(`+)(?!`)",
        options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators]
    )
    
    static let codeSpanClosingRegex = RegexHelper(
        pattern: "(?<!`)(`+)(?!`)",
        options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators]
    )
    
    // Bold and Italic
    static let strictBoldRegex = RegexHelper(
        pattern: "(^|[\\W_])(?:(?!\\1)|(?=^))(\\*|_)\\2(?=\\S)(.*?\\S)\\2\\2(?!\\2)(?=[\\W_]|$)",
        options: [.anchorsMatchLines]
    )
    
    static let strictItalicRegex = RegexHelper(
        pattern: "(^|[\\W_])(?:(?!\\1)|(?=^))(\\*|_)(?=\\S)((?:(?!\\2).)*?\\S)\\2(?!\\2)(?=[\\W_]|$)",
        options: [.anchorsMatchLines]
    )
    
    // Strikethrough
    static let strikeRegex = RegexHelper(
        pattern: "(~~)(?=\\S)(.+?)(?<=\\S)(~~)",
        options: [.allowCommentsAndWhitespace, .anchorsMatchLines]
    )
    
    // Tags
    static let tagsInlineRegex = RegexHelper(
        pattern: """
        (?:\\A|\\s|[^\\]]\\()
        \\#(
            [^
                \\s
                \\#
                \\+
                ,?!\"`';:\\.
                \\\\
                (){}\\[\\]
            ]+
        )
        """,
        options: []
    )
}

// MARK: - String Extensions

private extension String {
    var isNumber: Bool {
        return !isEmpty && rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }
}

// MARK: - Example Usage & Tests

#if DEBUG
/// Example usage demonstrating how to integrate InlineMarkdownRenderer
public class InlineMarkdownRendererExample {
    
    /// Example: Basic setup with default options
    static func basicExample() {
        let textView = NSTextView()
        let textStorage = textView.textStorage!
        
        // Create renderer with default options
        let renderer = InlineMarkdownRenderer()
        
        // Set as text storage delegate
        textStorage.delegate = renderer
        
        // Process initial content
        let markdown = """
        # Header 1
        ## Header 2
        
        This is **bold** and this is *italic*.
        
        Here's some `inline code` and a [link](https://example.com).
        
        ```swift
        func example() {
            print("Code block")
        }
        ```
        """
        
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
    }
    
    /// Example: Custom options with syntax hiding
    static func customOptionsExample() {
        let textView = NSTextView()
        let textStorage = textView.textStorage!
        
        // Custom options
        let options = InlineMarkdownRenderer.Options(
            noteFont: NSFont.systemFont(ofSize: 16),
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            hideSyntax: true,  // Hide markdown markers
            inlineTags: true
        )
        
        let renderer = InlineMarkdownRenderer(options: options)
        textStorage.delegate = renderer
        
        // Process
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# Hello World")
        renderer.processInitial(textStorage: textStorage)
    }
    
    /// Self-test: Verify bold/italic styling
    static func testBoldItalicStyling() {
        let textStorage = NSTextStorage(string: "This is **bold** and *italic* text")
        let renderer = InlineMarkdownRenderer()
        textStorage.delegate = renderer
        renderer.processInitial(textStorage: textStorage)
        
        // Check bold
        let boldRange = (textStorage.string as NSString).range(of: "bold")
        if let font = textStorage.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont {
            assert(font.fontDescriptor.symbolicTraits.contains(.bold), "Bold not applied")
            print("✓ Bold styling test passed")
        }
        
        // Check italic
        let italicRange = (textStorage.string as NSString).range(of: "italic")
        if let font = textStorage.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont {
            assert(font.fontDescriptor.symbolicTraits.contains(.italic), "Italic not applied")
            print("✓ Italic styling test passed")
        }
    }
    
    /// Self-test: Verify code block triggers highlighter
    static func testCodeBlockHighlighting() {
        let markdown = """
        ```swift
        let x = 42
        ```
        """
        
        let textStorage = NSTextStorage(string: markdown)
        
        // Custom highlighter that records if it was called
        class TestHighlighter: CodeHighlighter {
            var wasCalled = false
            var capturedLanguage: String?
            
            func highlight(code: String, language: String?) -> NSAttributedString {
                wasCalled = true
                capturedLanguage = language
                return NSAttributedString(string: code)
            }
        }
        
        let testHighlighter = TestHighlighter()
        let renderer = InlineMarkdownRenderer()
        renderer.setHighlighter(testHighlighter)
        textStorage.delegate = renderer
        renderer.processInitial(textStorage: textStorage)
        
        assert(testHighlighter.wasCalled, "Highlighter was not called for code block")
        assert(testHighlighter.capturedLanguage == "swift", "Language not detected correctly")
        print("✓ Code block highlighting test passed")
    }
    
    /// Run all tests
    static func runTests() {
        print("Running InlineMarkdownRenderer tests...")
        testBoldItalicStyling()
        testCodeBlockHighlighting()
        print("All tests passed! ✓")
    }
}
#endif

#endif // os(macOS)
