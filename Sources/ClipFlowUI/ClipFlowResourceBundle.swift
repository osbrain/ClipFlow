import Foundation

enum ClipFlowResourceBundle {
    static let bundle: Bundle = {
        if let packagedBundleURL = packagedBundleURL(
            mainResourceURL: Bundle.main.resourceURL
        ), let packagedBundle = Bundle(url: packagedBundleURL) {
            return packagedBundle
        }
        return Bundle.module
    }()

    static func packagedBundleURL(mainResourceURL: URL?) -> URL? {
        mainResourceURL?.appendingPathComponent(
            "ClipFlow_ClipFlowUI.bundle",
            isDirectory: true
        )
    }
}
