# InlineMarkdownRenderer

A portable, single-file markdown inline renderer for macOS NSTextStorage/NSTextView.

## Overview

`InlineMarkdownRenderer.swift` is a standalone Swift file that provides live, Bear-like markdown styling for macOS text editors. It applies real-time markdown highlighting directly to `NSTextStorage` as users type, without requiring HTML conversion or export functionality.

## Features

- ✅ **Incremental rendering** - Only processes edited paragraphs for optimal performance
- ✅ **Headers** - ATX (`# Header`) and Setext (`Header\n====`) styles with scaled fonts
- ✅ **Bold/Italic** - CommonMark-style `**bold**`, `*italic*`, `__bold__`, `_italic_`
- ✅ **Code** - Inline `` `code` `` spans and fenced code blocks with syntax highlighting
- ✅ **Links** - Autolinks and `[text](url)` inline links
- ✅ **Tags** - `#hashtag` style tags (optional)
- ✅ **Lists & Quotes** - Basic styling support
- ✅ **Strikethrough** - `~~text~~` styling
- ✅ **hideSyntax** - Optional hiding of markdown delimiters
- ✅ **Pluggable highlighter** - Attach external syntax highlighters

## Installation

### Drop-in Integration

Simply copy `InlineMarkdownRenderer.swift` to your macOS project. No other dependencies required.

### Requirements

- macOS 10.15+
- Swift 5.0+
- Foundation and AppKit frameworks

## Usage

### Basic Setup

```swift
import Cocoa

// Create a text view
let textView = NSTextView()
let textStorage = textView.textStorage!

// Create renderer with default options
let renderer = InlineMarkdownRenderer()

// Set as text storage delegate
textStorage.delegate = renderer

// Add initial markdown content
let markdown = """
# Hello World

This is **bold** and this is *italic*.

Here's some `inline code` and a [link](https://example.com).
"""

textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: markdown)
renderer.processInitial(textStorage: textStorage)
```

### Custom Options

```swift
// Configure custom options
let options = InlineMarkdownRenderer.Options(
    noteFont: NSFont.systemFont(ofSize: 16),
    codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
    hideSyntax: true,    // Hide markdown markers
    inlineTags: true     // Enable #hashtag links
)

let renderer = InlineMarkdownRenderer(options: options)
textStorage.delegate = renderer
```

### Using External Syntax Highlighters

The renderer supports pluggable syntax highlighting for code blocks. Here's how to integrate popular highlighters:

#### Example: Highlightr

```swift
import Highlightr

class HighlightrAdapter: CodeHighlighter {
    private let highlightr = Highlightr()!
    
    init() {
        highlightr.setTheme(to: "atom-one-light")
    }
    
    func highlight(code: String, language: String?) -> NSAttributedString {
        let lang = language ?? "plaintext"
        return highlightr.highlight(code, as: lang) ?? NSAttributedString(string: code)
    }
}

// Attach to renderer
let renderer = InlineMarkdownRenderer()
renderer.setHighlighter(HighlightrAdapter())
```

#### Example: SyntaxKit

```swift
import SyntaxKit

class SyntaxKitAdapter: CodeHighlighter {
    private let manager = SyntaxManager()
    
    func highlight(code: String, language: String?) -> NSAttributedString {
        guard let language = language,
              let syntax = manager.syntax(forLanguage: language) else {
            return NSAttributedString(string: code)
        }
        
        let parser = SyntaxParser(syntax: syntax)
        return parser.attributedString(for: code)
    }
}

// Attach to renderer
renderer.setHighlighter(SyntaxKitAdapter())
```

## Configuration Options

### InlineMarkdownRenderer.Options

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `noteFont` | `NSFont` | System 14pt | Font for regular text |
| `codeFont` | `NSFont` | Monospaced 13pt | Font for code spans and blocks |
| `hideSyntax` | `Bool` | `false` | Hide markdown syntax characters |
| `inlineTags` | `Bool` | `true` | Convert `#hashtag` to links |

## API Reference

### InlineMarkdownRenderer

```swift
public final class InlineMarkdownRenderer: NSObject, NSTextStorageDelegate
```

#### Initialization

```swift
public init(options: Options = .default)
```

#### Methods

```swift
// Process entire text storage for initial render
public func processInitial(textStorage: NSTextStorage)

// Force a full re-render
public func forceFullRender(_ textStorage: NSTextStorage)

// Set custom code highlighter
public func setHighlighter(_ highlighter: CodeHighlighter?)

// NSTextStorageDelegate method (called automatically)
public func textStorage(
    _ textStorage: NSTextStorage,
    didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange,
    changeInLength delta: Int
)
```

### CodeHighlighter Protocol

```swift
public protocol CodeHighlighter {
    func highlight(code: String, language: String?) -> NSAttributedString
}
```

Implement this protocol to provide custom syntax highlighting for fenced code blocks.

## Supported Markdown Elements

### Headers

```markdown
# Header 1
## Header 2
### Header 3
#### Header 4
##### Header 5
###### Header 6

Header 1 (Setext)
=================

Header 2 (Setext)
-----------------
```

Font sizes scale from 2.0x (H1) to 1.05x (H6) of the base font, with bold weight.

### Emphasis

```markdown
**bold text** or __bold text__
*italic text* or _italic text_
***bold and italic*** or ___bold and italic___
~~strikethrough~~
```

### Code

```markdown
Inline `code` with backticks

```python
# Fenced code block
def hello():
    print("Hello, world!")
```
```

### Links

```markdown
https://example.com (autolink)
[Link text](https://example.com)
```

### Lists

```markdown
- Bullet item
- Another item

1. Numbered item
2. Another numbered item
```

### Quotes

```markdown
> This is a blockquote
> It can span multiple lines
```

### Tags

```markdown
#hashtag #another-tag
```

Tags are converted to clickable links with the URL scheme `tag://hashtag`.

## Performance Characteristics

- **Incremental updates**: Only processes the edited paragraph range
- **Regex-based**: Uses NSRegularExpression for pattern matching
- **Thread-safe**: All UI updates happen on the main thread
- **Memory efficient**: No full document parsing required

## Design Philosophy

This renderer prioritizes:

1. **Simplicity** - Single file, no external dependencies
2. **Portability** - No FSNotes-specific code
3. **Performance** - Incremental processing for large documents
4. **Pragmatism** - Common markdown patterns over 100% CommonMark compliance
5. **Extensibility** - Pluggable syntax highlighting

## Limitations

- **Not a full CommonMark parser** - Uses regex patterns for detection
- **macOS only** - Uses AppKit (NSTextStorage/NSTextView)
- **No HTML export** - Inline rendering only
- **No tables, footnotes, or complex extensions** - Focuses on core markdown elements
- **Nested structures** - Limited support for deeply nested markdown

## Testing

The file includes built-in tests in DEBUG builds:

```swift
#if DEBUG
InlineMarkdownRendererExample.runTests()
#endif
```

Tests verify:
- Bold/italic styling is applied correctly
- Code blocks trigger the highlighter
- Syntax hiding works as expected

## Examples

### Example 1: Simple Note Editor

```swift
class MarkdownEditorViewController: NSViewController {
    @IBOutlet weak var textView: NSTextView!
    private var renderer: InlineMarkdownRenderer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup renderer
        renderer = InlineMarkdownRenderer()
        textView.textStorage?.delegate = renderer
        
        // Load initial content
        if let markdown = loadMarkdownFile() {
            textView.string = markdown
            renderer.processInitial(textStorage: textView.textStorage!)
        }
    }
}
```

### Example 2: Custom Styling

```swift
// Custom options for a dark theme
let darkOptions = InlineMarkdownRenderer.Options(
    noteFont: NSFont(name: "Menlo", size: 15)!,
    codeFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
    hideSyntax: true,
    inlineTags: true
)

let renderer = InlineMarkdownRenderer(options: darkOptions)
```

### Example 3: Programmatic Rendering

```swift
// Render markdown to attributed string
let markdown = "# Title\n\nThis is **bold**."
let textStorage = NSTextStorage(string: markdown)
let renderer = InlineMarkdownRenderer()

textStorage.delegate = renderer
renderer.processInitial(textStorage: textStorage)

// textStorage now contains styled attributed string
let attributedString = NSAttributedString(attributedString: textStorage)
```

## Troubleshooting

### Syntax not highlighting

- Ensure `textStorage.delegate = renderer` is set
- Call `processInitial(textStorage:)` after setting initial content
- Check that text storage has non-zero length

### Performance issues

- The renderer only processes edited paragraphs
- For very large documents (>10,000 lines), consider debouncing edits
- Disable code block highlighting if not needed

### Code blocks not highlighting

- Verify a highlighter is set via `setHighlighter(_:)`
- Check that code blocks use triple backticks: ` ``` `
- Ensure language identifier is supported by your highlighter

## Contributing

This file is designed to be standalone and portable. If you make improvements:

1. Keep all code in a single file
2. Maintain zero external dependencies (except AppKit)
3. Ensure backward compatibility with existing API
4. Add tests for new features
5. Update this README

## License

This file is part of the FSNotes project. See the main project LICENSE file for details.

## Credits

Extracted from FSNotes by Oleksandr Glushchenko and contributors.
Standalone version created for portability and reusability.

## Version History

- **1.0.0** (2026-02-11) - Initial standalone extraction
  - Complete markdown inline rendering
  - Pluggable code highlighting
  - Comprehensive documentation
