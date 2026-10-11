#if DEBUG
import KlimaCore
import UIKit

// MARK: stops – a SYNTHETIC logo pack for screenshots and QA (DEBUG builds only). Solid colours with the word
// „DEMO“, no real logo, written to the temporary directory. Shows how rows and the Gebietsleiste look once the
// owner's pack is online; never shipped and never installed into Application Support.

extension LogoPackStore {
    /// Installs the demo pack (brands for Ski Arlberg, Bregenzerwald and Warth-Schröcken).
    func installDemoPack() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("KBDemoLogoPack", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        func write(_ id: String, _ name: String, size: CGSize, color: UIColor, ink: UIColor) -> LogoPackManifest.Images {
            func png(_ scale: CGFloat) -> Data {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                format.opaque = false
                let s = CGSize(width: size.width * scale, height: size.height * scale)
                return UIGraphicsImageRenderer(size: s, format: format).pngData { ctx in
                    color.setFill()
                    ctx.fill(CGRect(origin: .zero, size: s))
                    let text = "DEMO" as NSString
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: min(s.height * 0.34, s.width * 0.22), weight: .heavy), .foregroundColor: ink,
                    ]
                    let t = text.size(withAttributes: attrs)
                    text.draw(at: CGPoint(x: (s.width - t.width) / 2, y: (s.height - t.height) / 2), withAttributes: attrs)
                }
            }
            let folder = dir.appendingPathComponent("b/\(id)", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? png(1).write(to: folder.appendingPathComponent("s.png"))
            try? png(2.4).write(to: folder.appendingPathComponent("l.png"))
            func rec(_ f: String, _ k: CGFloat) -> LogoPackManifest.Image {
                .init(f: "b/\(id)/\(f).png", w: Int(size.width * 3 * k), h: Int(size.height * 3 * k), sha256: "")
            }
            return .init(s: rec("s", 1), l: rec("l", 2.4))
        }
        let ski = LogoPackManifest.Brand(
            id: "demo_ski", level: .ski, name: "Demo Ski", owner: "Demo", attribution: "Demo-Logo (kein echtes Logo)",
            web: "https://example.org", states: ["V", "T"], match: .tags, tags: ["ski": ["ski-arlberg"]],
            img: write("demo_ski", "Demo Ski", size: CGSize(width: 20, height: 20), color: UIColor(red: 0.20, green: 0.28, blue: 0.77, alpha: 1), ink: .white),
            aspect: 1, compact: .tile, hero: true, selfPlate: true, status: "demo")
        let region = LogoPackManifest.Brand(
            id: "demo_region", level: .region, name: "Demo Region", owner: "Demo", attribution: "Demo-Logo (kein echtes Logo)",
            web: "https://example.org", states: ["V"], match: .tags, tags: ["region": ["bregenzerwald"]],
            img: write("demo_region", "Demo Region", size: CGSize(width: 56, height: 20), color: UIColor(red: 0.12, green: 0.55, blue: 0.40, alpha: 1), ink: .white),
            aspect: 2.8, compact: .logo, hero: true, status: "demo")
        let ort = LogoPackManifest.Brand(
            id: "demo_ort", level: .ort, name: "Demo Ort", owner: "Demo", attribution: "Demo-Logo (kein echtes Logo)",
            web: "https://example.org", states: ["V"], match: .gkz,
            img: write("demo_ort", "Demo Ort", size: CGSize(width: 56, height: 20), color: UIColor(red: 0.85, green: 0.38, blue: 0.17, alpha: 1), ink: .white),
            aspect: 2.8, compact: .logo, hero: true, status: "demo", gkz: ["80239"])
        let manifest = LogoPackManifest(
            packVersion: 1, generated: "demo", imageFormat: "png", scale: 3, brands: [ski, region, ort],
            byTag: ["ski": ["ski-arlberg": "demo_ski"], "region": ["bregenzerwald": "demo_region"]],
            byGkz: ["80239": ["demo_ort"]])
        apply(config: LogoConfig(enabled: true, pack: nil, revoked: [], armsDisabled: ["NÖ"], armsEnabled: []), persist: false)
        activate(manifest, directory: dir)
    }
}
#endif
