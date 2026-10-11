// SPDX-FileCopyrightText: 2026 Anne Jan Brouwer
// SPDX-License-Identifier: GPL-3.0-or-later
// Print the window id of the largest on-screen window owned by the process
// with pid argv[1] (or named argv[1]), for screencapture -l. With --list,
// print every window seen, to stderr.
import CoreGraphics
import Foundation
let key = CommandLine.arguments[1]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
if CommandLine.arguments.contains("--list") {
  for w in list {
    FileHandle.standardError.write("\(w[kCGWindowOwnerPID as String] ?? "-") \(w[kCGWindowOwnerName as String] ?? "-") layer=\(w[kCGWindowLayer as String] ?? "-") \(w[kCGWindowBounds as String] ?? "-")\n".data(using: .utf8)!)
  }
}
let wins = list.filter { w in
  let pid = w[kCGWindowOwnerPID as String] as? Int
  let name = w[kCGWindowOwnerName as String] as? String
  return (String(pid ?? -1) == key || name == key) && (w[kCGWindowLayer as String] as? Int) == 0
}
let area: ([String: Any]) -> Double = { w in
  let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
  return (b["Width"] ?? 0) * (b["Height"] ?? 0)
}
if let w = wins.max(by: { area($0) < area($1) }) { print(w[kCGWindowNumber as String] as! Int) } else { exit(1) }
