// SPDX-FileCopyrightText: 2026 Anne Jan Brouwer
// SPDX-License-Identifier: GPL-3.0-or-later
// Print the window id of the largest on-screen window owned by the process
// named in argv[1], for screencapture -l.
import CoreGraphics
let owner = CommandLine.arguments[1]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let wins = list.filter { ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0 }
let area: ([String: Any]) -> Double = { w in
  let b = w[kCGWindowBounds as String] as! [String: Double]; return b["Width"]! * b["Height"]! }
if let w = wins.max(by: { area($0) < area($1) }) { print(w[kCGWindowNumber as String] as! Int) } else { exit(1) }
