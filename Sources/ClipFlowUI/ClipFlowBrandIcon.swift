import AppKit

@MainActor
public enum ClipFlowBrandIcon {
    private static let bundledIcon = Bundle.module.url(
        forResource: "AppIcon",
        withExtension: "icns"
    ).flatMap(NSImage.init(contentsOf:))

    public static func image() -> NSImage? {
        bundledIcon
    }
}
