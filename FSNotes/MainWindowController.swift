//
//  MainWindowController.swift
//  FSNotes
//
//  Created by BUDDAx2 on 8/9/17.
//  Copyright © 2017 Oleksandr Glushchenko. All rights reserved.
//

import AppKit


class MainWindowController: NSWindowController, NSWindowDelegate {
    let notesListUndoManager = UndoManager()
    
    public var lastWindowSize: NSRect? = nil

    override func windowDidLoad() {
        AppDelegate.mainWindowController = self

        self.window?.hidesOnDeactivate = UserDefaultsManagement.hideOnDeactivate
        self.window?.titleVisibility = .hidden
        self.window?.titlebarAppearsTransparent = true

        self.windowFrameAutosaveName = "myMainWindow"
        
        // SIMPLE MARKDOWN EDITOR MODE: Set window title
        self.window?.title = "Markdown Editor"
    }
    
    func windowDidResize(_ notification: Notification) {
        refreshEditArea()
    }
        
    func makeNew() {
        window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
        refreshEditArea(focusSearch: false) // Don't focus search in simple mode
    }
    
    func refreshEditArea(focusSearch: Bool = false) {
        guard let vc = ViewController.shared() else { return }

        // SIMPLE MARKDOWN EDITOR MODE: Always focus editor, not search
        vc.focusEditArea()

        vc.editor.updateTextContainerInset()
    }
    
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        guard let fr = window.firstResponder else {
            return notesListUndoManager
        }
        
        if fr.isKind(of: NotesTableView.self) {
            return notesListUndoManager
        }
        
        if fr.isKind(of: EditTextView.self) {
            guard let vc = ViewController.shared(), let ev = vc.editor, ev.isEditable else { return notesListUndoManager }
            
            return vc.editorUndoManager
        }
        
        return notesListUndoManager
    }

    public static func shared() -> NSWindow? {
        return AppDelegate.mainWindowController?.window
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        UserDefaultsManagement.fullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        UserDefaultsManagement.fullScreen = false
    }
}
