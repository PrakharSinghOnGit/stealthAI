//
//  StealthPanel 2.swift
//  stealthAI
//
//  Created by Shaan SIngh on 28/03/26.
//


import Cocoa

class StealthPanel: NSPanel {
    // 1. The Magic Override: Allows typing without stealing app focus
    override var canBecomeKey: Bool {
        return true
    }
    
    // 2. Optional: Allow the panel to become the main window for its own app space
    override var canBecomeMain: Bool {
        return true
    }
}