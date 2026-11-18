// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import CoreGraphics
import Foundation

/// Physical modifier identity is separate from a chord's combined modifier flags.
enum DictationShortcut {
    static let modifierNames: [Int64: String] = [54: "Right Command", 55: "Left Command", 56: "Left Shift", 60: "Right Shift", 58: "Left Option", 61: "Right Option", 59: "Left Control", 62: "Right Control", 63: "Fn / Globe"]
    static let masks: [Int64: UInt64] = [54: 0x10, 55: 0x8, 56: 0x2, 60: 0x4, 58: 0x20, 61: 0x40, 59: 0x1, 62: 0x2000, 63: CGEventFlags.maskSecondaryFn.rawValue]
    static func isDown(_ code: Int64, flags: UInt64) -> Bool { flags & (masks[code] ?? 0) != 0 }
    static func isSolo(_ code: Int64, flags: UInt64) -> Bool {
        let all = masks.values.reduce(UInt64(0), |)
        return flags & all == masks[code]
    }
    static func modifier(_ raw: String) -> Int64? {
        guard raw.hasPrefix("single:"), let code = Int64(raw.dropFirst(7)), masks[code] != nil else { return nil }
        return code
    }
    static func migrate() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: DefaultsKey.dictationMouseTriggersMigrated) {
            let old = defaults.integer(forKey: DefaultsKey.dictationMouseButton)
            if (defaults.string(forKey: DefaultsKey.dictationMouseButtons) ?? "").isEmpty, (2...4).contains(old) {
                defaults.set(String(old), forKey: DefaultsKey.dictationMouseButtons)
            }
            defaults.set(true, forKey: DefaultsKey.dictationMouseTriggersMigrated)
        }
        if defaults.bool(forKey: DefaultsKey.dictationRightControl) {
            defaults.set("single:62", forKey: DefaultsKey.dictationShortcut)
            defaults.set(false, forKey: DefaultsKey.dictationRightControl)
        }
    }
}
