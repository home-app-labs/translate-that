// Draws the app icon and writes a 1024px PNG. Usage: swift make-icon.swift <output.png>
// Two speech bubbles saying the same thing in two languages: the original behind, the translation in front.
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset = 100.0
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let background = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.27, green: 0.22, blue: 0.56, alpha: 1),
                    NSColor(red: 0.10, green: 0.08, blue: 0.24, alpha: 1)])!.draw(in: background, angle: -90)

let violet = NSColor(red: 0.56, green: 0.50, blue: 1.00, alpha: 1)
let amber = NSColor(red: 1.00, green: 0.80, blue: 0.36, alpha: 1)
let ink = NSColor(red: 0.10, green: 0.08, blue: 0.22, alpha: 1)

/// A rounded bubble with a tail at its bottom edge. `grow` widens the whole outline, for the dark rim.
func bubblePath(_ frame: NSRect, tailLeft: Bool, grow: Double = 0) -> NSBezierPath {
    let corner = 78.0
    let path = NSBezierPath(roundedRect: frame.insetBy(dx: -grow, dy: -grow), xRadius: corner + grow, yRadius: corner + grow)
    let base = tailLeft ? frame.minX + 96 : frame.maxX - 96
    let tip = tailLeft ? frame.minX + 40 : frame.maxX - 40
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: base - 62 - grow, y: frame.minY + 30))
    tail.line(to: NSPoint(x: tip + (tailLeft ? -grow : grow), y: frame.minY - 82 - grow * 1.6))
    tail.line(to: NSPoint(x: base + 62 + grow, y: frame.minY + 30))
    tail.close()
    path.append(tail)
    return path
}

func bubble(_ frame: NSRect, tailLeft: Bool, fill: NSColor, letter: String, color: NSColor, fontSize: Double) {
    // A dark rim keeps the bubbles apart where they overlap.
    ink.withAlphaComponent(0.6).setFill()
    bubblePath(frame, tailLeft: tailLeft, grow: 13).fill()
    fill.setFill()
    bubblePath(frame, tailLeft: tailLeft).fill()
    let text = NSAttributedString(string: letter, attributes: [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: color,
    ])
    let bounds = text.size()
    text.draw(at: NSPoint(x: frame.midX - bounds.width / 2, y: frame.midY - bounds.height / 2))
}

// Behind: the original text.
bubble(NSRect(x: 196, y: 498, width: 400, height: 300), tailLeft: true, fill: amber, letter: "A", color: ink, fontSize: 220)
// In front: the translation.
bubble(NSRect(x: 428, y: 306, width: 400, height: 300), tailLeft: false, fill: violet, letter: "文", color: .white, fontSize: 196)

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
