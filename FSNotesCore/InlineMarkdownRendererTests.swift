//
//  InlineMarkdownRendererTests.swift
//  FSNotes Tests
//
//  Comprehensive tests for InlineMarkdownRenderer
//

#if os(macOS)
import XCTest
import Cocoa
@testable import FSNotesCore

class InlineMarkdownRendererTests: XCTestCase {
    
    var renderer: InlineMarkdownRenderer!
    var textStorage: NSTextStorage!
    
    override func setUp() {
        super.setUp()
        renderer = InlineMarkdownRenderer()
        textStorage = NSTextStorage()
        textStorage.delegate = renderer
    }
    
    override func tearDown() {
        textStorage = nil
        renderer = nil
        super.tearDown()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testRendererInitialization() {
        XCTAssertNotNil(renderer)
        XCTAssertEqual(renderer.options.hideSyntax, false)
        XCTAssertEqual(renderer.options.inlineTags, true)
    }
    
    func testCustomOptions() {
        let customOptions = InlineMarkdownRenderer.Options(
            noteFont: NSFont.systemFont(ofSize: 18),
            codeFont: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular),
            hideSyntax: true,
            inlineTags: false
        )
        
        let customRenderer = InlineMarkdownRenderer(options: customOptions)
        XCTAssertEqual(customRenderer.options.noteFont.pointSize, 18)
        XCTAssertEqual(customRenderer.options.hideSyntax, true)
        XCTAssertEqual(customRenderer.options.inlineTags, false)
    }
    
    // MARK: - Header Tests
    
    func testATXHeaders() {
        let markdown = "# Header 1\n## Header 2\n### Header 3"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        // Check H1
        let h1Range = (textStorage.string as NSString).range(of: "Header 1")
        if let font = textStorage.attribute(.font, at: h1Range.location, effectiveRange: nil) as? NSFont {
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
            XCTAssertGreaterThan(font.pointSize, renderer.options.noteFont.pointSize)
        } else {
            XCTFail("Header 1 should have font attribute")
        }
        
        // Check H2
        let h2Range = (textStorage.string as NSString).range(of: "Header 2")
        if let font = textStorage.attribute(.font, at: h2Range.location, effectiveRange: nil) as? NSFont {
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
        } else {
            XCTFail("Header 2 should have font attribute")
        }
    }
    
    func testSetextHeaders() {
        let markdown = "Header 1\n========"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        let headerRange = (textStorage.string as NSString).range(of: "Header 1")
        if let font = textStorage.attribute(.font, at: headerRange.location, effectiveRange: nil) as? NSFont {
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
            XCTAssertGreaterThan(font.pointSize, renderer.options.noteFont.pointSize)
        } else {
            XCTFail("Setext header should have font attribute")
        }
    }
    
    // MARK: - Bold and Italic Tests
    
    func testBoldText() {
        let markdown = "This is **bold** text"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        let boldRange = (textStorage.string as NSString).range(of: "bold")
        if let font = textStorage.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont {
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold), "Bold trait should be applied")
        } else {
            XCTFail("Bold text should have font attribute")
        }
    }
    
    func testItalicText() {
        let markdown = "This is *italic* text"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        let italicRange = (textStorage.string as NSString).range(of: "italic")
        if let font = textStorage.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont {
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.italic), "Italic trait should be applied")
        } else {
            XCTFail("Italic text should have font attribute")
        }
    }
    
    func testBoldWithUnderscores() {
        let markdown = "This is __bold__ text"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        let boldRange = (textStorage.string as NSString).range(of: "bold")
        if let font = textStorage.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont {
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
        }
    }
    
    func testItalicWithUnderscores() {
        let markdown = "This is _italic_ text"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        let italicRange = (textStorage.string as NSString).range(of: "italic")
        if let font = textStorage.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont {
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.italic))
        }
    }
    
    // MARK: - Code Tests
    
    func testInlineCode() {
        let markdown = "This is `inline code` here"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        let codeRange = (textStorage.string as NSString).range(of: "`inline code`")
        let backgroundColor = textStorage.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil)
        XCTAssertNotNil(backgroundColor, "Inline code should have background color")
    }
    
    func testFencedCodeBlock() {
        let markdown = """
        ```swift
        let x = 42
        ```
        """
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        
        // Track if highlighter was called
        class TestHighlighter: CodeHighlighter {
            var wasCalled = false
            var capturedLanguage: String?
            
            func highlight(code: String, language: String?) -> NSAttributedString {
                wasCalled = true
                capturedLanguage = language
                return NSAttributedString(
                    string: code,
                    attributes: [.foregroundColor: NSColor.red]
                )
            }
        }
        
        let testHighlighter = TestHighlighter()
        renderer.setHighlighter(testHighlighter)
        renderer.processInitial(textStorage: textStorage)
        
        XCTAssertTrue(testHighlighter.wasCalled, "Code highlighter should be called for fenced blocks")
        XCTAssertEqual(testHighlighter.capturedLanguage, "swift", "Language should be detected from fence")
    }
    
    // MARK: - Link Tests
    
    func testAutolink() {
        let markdown = "Visit https://example.com for info"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        let linkRange = (textStorage.string as NSString).range(of: "https://example.com")
        let link = textStorage.attribute(.link, at: linkRange.location, effectiveRange: nil)
        XCTAssertNotNil(link, "Autolink should have link attribute")
    }
    
    func testInlineLink() {
        let markdown = "Check [this link](https://example.com) out"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        let textRange = (textStorage.string as NSString).range(of: "this link")
        let link = textStorage.attribute(.link, at: textRange.location, effectiveRange: nil)
        XCTAssertNotNil(link, "Inline link should have link attribute")
    }
    
    // MARK: - Strikethrough Tests
    
    func testStrikethrough() {
        let markdown = "This is ~~crossed out~~ text"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        let strikeRange = (textStorage.string as NSString).range(of: "crossed out")
        let strikeStyle = textStorage.attribute(.strikethroughStyle, at: strikeRange.location, effectiveRange: nil)
        XCTAssertNotNil(strikeStyle, "Strikethrough should have strikethroughStyle attribute")
    }
    
    // MARK: - Tag Tests
    
    func testHashtags() {
        let markdown = "Here's a #tag and #another-tag"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        let tagRange = (textStorage.string as NSString).range(of: "#tag")
        let link = textStorage.attribute(.link, at: tagRange.location, effectiveRange: nil)
        
        if renderer.options.inlineTags {
            XCTAssertNotNil(link, "Tags should have link attribute when inlineTags is enabled")
        }
    }
    
    // MARK: - hideSyntax Tests
    
    func testHideSyntaxOption() {
        let options = InlineMarkdownRenderer.Options(
            noteFont: NSFont.systemFont(ofSize: 14),
            codeFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            hideSyntax: true,
            inlineTags: true
        )
        
        let hidingRenderer = InlineMarkdownRenderer(options: options)
        let storage = NSTextStorage(string: "This is **bold** text")
        storage.delegate = hidingRenderer
        hidingRenderer.processInitial(textStorage: storage)
        
        // Find the opening ** markers
        let markerLocation = storage.string.range(of: "**")!.lowerBound
        let markerNSRange = NSRange(markerLocation..<storage.string.index(markerLocation, offsetBy: 2), in: storage.string)
        
        if let font = storage.attribute(.font, at: markerNSRange.location, effectiveRange: nil) as? NSFont {
            // When hideSyntax is true, marker font should be very small
            XCTAssertLessThan(font.pointSize, 1.0, "Syntax markers should have tiny font when hideSyntax is enabled")
        }
    }
    
    // MARK: - Incremental Update Tests
    
    func testIncrementalUpdate() {
        // Initial content
        let markdown = "Line 1\nLine 2\nLine 3"
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        // Make an edit
        let editLocation = (textStorage.string as NSString).range(of: "Line 2").location
        textStorage.replaceCharacters(in: NSRange(location: editLocation, length: 6), with: "**Bold**")
        
        // Check bold was applied
        let boldRange = (textStorage.string as NSString).range(of: "Bold")
        if let font = textStorage.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont {
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
        }
    }
    
    // MARK: - Performance Tests
    
    func testLargeDocumentPerformance() {
        measure {
            var markdown = ""
            for i in 1...100 {
                markdown += "# Header \(i)\n\nThis is **bold** and *italic* text.\n\n"
            }
            
            let storage = NSTextStorage(string: markdown)
            let perfRenderer = InlineMarkdownRenderer()
            storage.delegate = perfRenderer
            perfRenderer.processInitial(textStorage: storage)
        }
    }
    
    // MARK: - Edge Cases
    
    func testEmptyDocument() {
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "")
        renderer.processInitial(textStorage: textStorage)
        // Should not crash
        XCTAssertEqual(textStorage.length, 0)
    }
    
    func testOnlyWhitespace() {
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "   \n\n   ")
        renderer.processInitial(textStorage: textStorage)
        // Should not crash
        XCTAssertGreaterThan(textStorage.length, 0)
    }
    
    func testMixedMarkdown() {
        let markdown = """
        # Title
        
        This is **bold** and *italic* text.
        
        Here's `code` and a [link](https://example.com).
        
        - List item 1
        - List item 2
        
        ```python
        print("Hello")
        ```
        
        > Quote here
        
        #tag #another
        """
        
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
        renderer.processInitial(textStorage: textStorage)
        
        // Just verify it doesn't crash and has some attributes
        XCTAssertGreaterThan(textStorage.length, 0)
    }
}
#endif
