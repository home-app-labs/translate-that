// Draws the app icon and writes a 1024px PNG. Usage: swift make-icon.swift <output.png>
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let inset = 100.0
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let background = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.20, green: 0.74, blue: 0.66, alpha: 1),
                    NSColor(red: 0.08, green: 0.45, blue: 0.56, alpha: 1)])!.draw(in: background, angle: -90)

let ink = NSColor(red: 0.07, green: 0.40, blue: 0.50, alpha: 1)

// Two overlapping cards, one letter each: the source behind, the translation in front.
func card(_ frame: NSRect, fill: NSColor, letter: String, color: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: frame, xRadius: 70, yRadius: 70).fill()
    let text = NSAttributedString(string: letter, attributes: [
        .font: NSFont.systemFont(ofSize: 250, weight: .bold),
        .foregroundColor: color,
    ])
    let bounds = text.size()
    text.draw(at: NSPoint(x: frame.midX - bounds.width / 2, y: frame.midY - bounds.height / 2))
}
card(NSRect(x: 452, y: 232, width: 360, height: 360), fill: NSColor.white.withAlphaComponent(0.32), letter: "文", color: .white)
card(NSRect(x: 212, y: 432, width: 360, height: 360), fill: .white, letter: "A", color: ink)

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
