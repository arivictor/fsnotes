# Simple Markdown Editor - User Guide

## Overview

This application is a simplified version of FSNotes, focused entirely on markdown editing without note management features. It provides a clean, distraction-free environment for writing markdown.

## Features

### Markdown Editing
- Full-featured markdown text editor with syntax highlighting
- Support for all standard markdown syntax
- Real-time syntax highlighting for code blocks (30+ languages)
- Inline image support
- Mermaid diagram rendering
- MathJax mathematical notation support

### User Interface
- **Clean Single-Pane View**: Just you and your markdown
- **Live Preview**: Toggle preview panel with the preview button
- **Dark Mode**: Automatic support for macOS dark mode
- **Distraction-Free**: No sidebars, no file lists, no clutter

### Keyboard Support
All standard markdown formatting shortcuts are available:
- **Headers**: Cmd+1 through Cmd+6 for H1-H6
- **Bold**: Cmd+B
- **Italic**: Cmd+I
- **Code Block**: Cmd+C
- **Link**: Cmd+I (when text selected)
- **Image**: Cmd+Shift+I
- **Todo**: Cmd+T

## Getting Started

1. Launch the application
2. Start typing markdown immediately - the editor is auto-focused
3. Use the Preview button to toggle live preview
4. Use markdown formatting shortcuts as needed

## What's Different from FSNotes?

This simplified version removes:
- Sidebar with projects/folders
- Notes list/library view
- Search functionality
- Multi-note management
- File system synchronization
- Cloud sync
- Git integration
- Encryption features
- Import/export functionality

All markdown editing and rendering features are preserved.

## Technical Notes

- Content is stored in a temporary directory
- No manual configuration required
- Application automatically focuses on the editor on launch
- Window title is simply "Markdown Editor"

## Reverting to Full FSNotes

If you need the full FSNotes functionality, the changes made are minimal and reversible:
1. See `SIMPLIFIED_EDITOR_CHANGES.md` for details
2. Uncomment the "SIMPLE MARKDOWN EDITOR MODE" sections in the code
3. Restore the original README from git history
4. Rebuild the application

## Support

This is a simplified version of FSNotes. For the full-featured notes manager, visit the original FSNotes project.

## License

MIT License - same as FSNotes
