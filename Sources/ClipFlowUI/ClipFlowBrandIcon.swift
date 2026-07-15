import AppKit

@MainActor
public enum ClipFlowBrandIcon {
    private static let bundledIcon = ClipFlowResourceBundle.bundle.url(
        forResource: "AppIcon",
        withExtension: "icns"
    ).flatMap(NSImage.init(contentsOf:))

    public static func image() -> NSImage? {
        bundledIcon
    }
}
