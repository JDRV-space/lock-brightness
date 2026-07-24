// brightness-ctl: Native brightness control for Apple Silicon Macs
// Uses Apple's private DisplayServices framework.
//
// Usage:
//   brightness-ctl get          - Print current brightness (0.0 to 1.0)
//   brightness-ctl set <value>  - Set brightness (0.0 to 1.0)
//   brightness-ctl version      - Print version
//
// Exit codes:
//   0 - Success
//   1 - Usage error
//   2 - Display error (not found, not built-in, or framework failure)

import Foundation
import CoreGraphics

@_silgen_name("DisplayServicesSetBrightness")
func DisplayServicesSetBrightness(_ display: CGDirectDisplayID, _ brightness: Float) -> Int32

@_silgen_name("DisplayServicesGetBrightness")
func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32

let version = "1.0.0"

func printUsage(toStdout: Bool = false) {
    let output = toStdout ? stdout : stderr
    fputs("""
    brightness-ctl v\(version)
    Native brightness control for Apple Silicon Macs.

    Usage:
      brightness-ctl get          Print current brightness (0.0 to 1.0)
      brightness-ctl set <value>  Set brightness (clamped to 0.0 - 1.0)
      brightness-ctl version      Print version

    Examples:
      brightness-ctl get
      brightness-ctl set 0.75

    Exit codes:
      0  Success
      1  Usage error
      2  Display error

    """, output)
}

/// Find the active built-in display. External-only setups are unsupported.
func builtInDisplayID() -> CGDirectDisplayID? {
    var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
    var displayCount: UInt32 = 0
    let err = CGGetActiveDisplayList(16, &displayIDs, &displayCount)
    guard err == .success else {
        return nil
    }

    for i in 0..<Int(displayCount) {
        if CGDisplayIsBuiltin(displayIDs[i]) != 0 {
            return displayIDs[i]
        }
    }
    return nil
}

func requireBuiltInDisplayID() -> CGDirectDisplayID {
    guard let display = builtInDisplayID() else {
        fputs("error: active built-in display not found; external displays are not supported\n", stderr)
        exit(2)
    }
    return display
}

guard CommandLine.arguments.count >= 2 else {
    printUsage()
    exit(1)
}

let command = CommandLine.arguments[1]

switch command {
case "get":
    let display = requireBuiltInDisplayID()
    var brightness: Float = 0
    let err = DisplayServicesGetBrightness(display, &brightness)
    guard err == 0 else {
        fputs("error: failed to read brightness (code \(err))\n", stderr)
        exit(2)
    }
    print(String(format: "%.4f", brightness))

case "set":
    guard CommandLine.arguments.count >= 3 else {
        fputs("error: missing brightness value\n", stderr)
        fputs("usage: brightness-ctl set <0.0-1.0>\n", stderr)
        exit(1)
    }
    guard let value = Float(CommandLine.arguments[2]) else {
        fputs("error: invalid brightness value '\(CommandLine.arguments[2])'\n", stderr)
        exit(1)
    }
    guard value.isFinite else {
        fputs("error: brightness value must be finite\n", stderr)
        exit(1)
    }
    let clamped = min(max(value, 0.0), 1.0)
    let display = requireBuiltInDisplayID()
    let err = DisplayServicesSetBrightness(display, clamped)
    guard err == 0 else {
        fputs("error: failed to set brightness (code \(err))\n", stderr)
        exit(2)
    }

case "version":
    print(version)

case "-h", "--help", "help":
    printUsage(toStdout: true)

default:
    fputs("error: unknown command '\(command)'\n", stderr)
    printUsage()
    exit(1)
}
