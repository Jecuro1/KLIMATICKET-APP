# Wave 4: mutations against the API added during this round (UIKit interop, QuartzCore,
# Darwin-only Foundation shims) - checks that the new stubs are not looser than the SDK.
P = []


def pair(id, cat, desc, path, good, bad, expect="error"):
    P.append(dict(id=id, cat=cat, desc=desc, path=path, good=good, bad=bad, expect=expect))


D = "App/Sources/Features/MutW4/"
VIEW = "import UIKit\n\nfinal class %s: UIView {\n    let label = UILabel()\n    override init(frame: CGRect) {\n        super.init(frame: frame)\n%s\n    }\n    required init?(coder: NSCoder) { fatalError() }\n}\n"

pair("V01", "quartzcore", "layer.borderColor = UIColor (needs .cgColor)", D + "V01.swift",
     VIEW % ("V01", "        layer.borderColor = UIColor.separator.cgColor"),
     VIEW % ("V01", "        layer.borderColor = UIColor.separator"))
pair("V02", "quartzcore", "layer.shadowOpacity with a Double variable (Float property)", D + "V02.swift",
     VIEW % ("V02", "        let o: Float = 0.3\n        layer.shadowOpacity = o"),
     VIEW % ("V02", "        let o: Double = 0.3\n        layer.shadowOpacity = o"))
pair("V03", "autolayout", "NSLayoutConstraint.activate with a single constraint (needs an array)", D + "V03.swift",
     VIEW % ("V03", "        addSubview(label)\n        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: leadingAnchor)])"),
     VIEW % ("V03", "        addSubview(label)\n        NSLayoutConstraint.activate(label.leadingAnchor.constraint(equalTo: leadingAnchor))"))
pair("V04", "autolayout", "X-axis anchor constrained to a Y-axis anchor", D + "V04.swift",
     VIEW % ("V04", "        addSubview(label)\n        label.topAnchor.constraint(equalTo: topAnchor, constant: 8).isActive = true"),
     VIEW % ("V04", "        addSubview(label)\n        label.leadingAnchor.constraint(equalTo: topAnchor, constant: 8).isActive = true"))
pair("V05", "autolayout", "NSLayoutDimension constraint(equalTo: 44) (it is equalToConstant:)", D + "V05.swift",
     VIEW % ("V05", "        label.heightAnchor.constraint(equalToConstant: 44).isActive = true"),
     VIEW % ("V05", "        label.heightAnchor.constraint(equalTo: 44).isActive = true"))
pair("V06", "autolayout", "UILayoutPriority .low (it is .defaultLow)", D + "V06.swift",
     VIEW % ("V06", "        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)"),
     VIEW % ("V06", "        label.setContentCompressionResistancePriority(.low, for: .horizontal)"))
pair("V07", "uikit", "NSTextAlignment .centre typo", D + "V07.swift",
     VIEW % ("V07", "        label.textAlignment = .center"),
     VIEW % ("V07", "        label.textAlignment = .centre"))
pair("V08", "uikit", "UILabel.text assigned an Int", D + "V08.swift",
     VIEW % ("V08", "        label.text = String(42)"),
     VIEW % ("V08", "        label.text = 42"))
pair("V09", "uikit", "attributed-string key that does not exist (.textColor)", D + "V09.swift",
     VIEW % ("V09", "        label.attributedText = NSAttributedString(string: \"x\", attributes: [.foregroundColor: UIColor.label])"),
     VIEW % ("V09", "        label.attributedText = NSAttributedString(string: \"x\", attributes: [.textColor: UIColor.label])"))
pair("V10", "uikit", "layerClass override as an instance property", D + "V10.swift",
     "import UIKit\n\nfinal class V10: UIView {\n    override class var layerClass: AnyClass { CAGradientLayer.self }\n}\n",
     "import UIKit\n\nfinal class V10: UIView {\n    override var layerClass: AnyClass { CAGradientLayer.self }\n}\n")
pair("V11", "uikit", "sheet detents [.medium] without () (Detent factory is a method)", D + "V11.swift",
     "import UIKit\n\n@MainActor enum V11 {\n    static func configure(_ vc: UIViewController) { vc.sheetPresentationController?.detents = [.medium(), .large()] }\n}\n",
     "import UIKit\n\n@MainActor enum V11 {\n    static func configure(_ vc: UIViewController) { vc.sheetPresentationController?.detents = [.medium, .large] }\n}\n")
pair("V12", "uikit", "image picker delegate that is not a UINavigationControllerDelegate", D + "V12.swift",
     "import UIKit\n\nfinal class V12Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {}\n\n@MainActor enum V12 {\n    static func make(_ c: V12Coordinator) -> UIImagePickerController {\n        let p = UIImagePickerController()\n        p.sourceType = .camera\n        p.delegate = c\n        return p\n    }\n}\n",
     "import UIKit\n\nfinal class V12Coordinator: NSObject, UIImagePickerControllerDelegate {}\n\n@MainActor enum V12 {\n    static func make(_ c: V12Coordinator) -> UIImagePickerController {\n        let p = UIImagePickerController()\n        p.sourceType = .camera\n        p.delegate = c\n        return p\n    }\n}\n")
pair("V13", "uikit", "picker info dictionary read with a String key", D + "V13.swift",
     "import UIKit\n\nenum V13 {\n    static func image(_ info: [UIImagePickerController.InfoKey: Any]) -> UIImage? { info[.originalImage] as? UIImage }\n}\n",
     "import UIKit\n\nenum V13 {\n    static func image(_ info: [UIImagePickerController.InfoKey: Any]) -> UIImage? { info[\"UIImagePickerControllerOriginalImage\"] as? UIImage }\n}\n")
pair("V14", "uikit", "UINavigationBar.appearance().standardAppearance set to nil (non-optional)", D + "V14.swift",
     "import UIKit\n\n@MainActor enum V14 {\n    static func style() {\n        let a = UINavigationBarAppearance()\n        a.configureWithOpaqueBackground()\n        UINavigationBar.appearance().standardAppearance = a\n        UINavigationBar.appearance().scrollEdgeAppearance = nil\n    }\n}\n",
     "import UIKit\n\n@MainActor enum V14 {\n    static func style() {\n        let a = UINavigationBarAppearance()\n        a.configureWithOpaqueBackground()\n        UINavigationBar.appearance().standardAppearance = nil\n        UINavigationBar.appearance().scrollEdgeAppearance = a\n    }\n}\n")
pair("V15", "uikit", "UIControl.addTarget without the for: event", D + "V15.swift",
     "import UIKit\n\nfinal class V15: UIControl {\n    func wire() { addTarget(self, action: #selector(changed), for: .valueChanged) }\n    @objc func changed() {}\n}\n",
     "import UIKit\n\nfinal class V15: UIControl {\n    func wire() { addTarget(self, action: #selector(changed)) }\n    @objc func changed() {}\n}\n")
pair("V16", "uikit", "UIPanGestureRecognizer.translation() without in:", D + "V16.swift",
     "import UIKit\n\n@MainActor enum V16 {\n    static func dx(_ g: UIPanGestureRecognizer) -> CGFloat { g.translation(in: g.view).x }\n}\n",
     "import UIKit\n\n@MainActor enum V16 {\n    static func dx(_ g: UIPanGestureRecognizer) -> CGFloat { g.translation().x }\n}\n")
pair("V17", "foundation", "ProcessInfo.thermalState compared with a non-existent case", D + "V17.swift",
     "import Foundation\n\nenum V17 {\n    static var hot: Bool { ProcessInfo.processInfo.thermalState == .serious }\n}\n",
     "import Foundation\n\nenum V17 {\n    static var hot: Bool { ProcessInfo.processInfo.thermalState == .hot }\n}\n")
pair("V18", "foundation", "NSUbiquitousKeyValueStore.string(forKey:) used as non-optional", D + "V18.swift",
     "import Foundation\n\nenum V18 {\n    static var name: String { NSUbiquitousKeyValueStore.default.string(forKey: \"n\") ?? \"\" }\n}\n",
     "import Foundation\n\nenum V18 {\n    static var name: String { NSUbiquitousKeyValueStore.default.string(forKey: \"n\") }\n}\n")
pair("V19", "foundation", "DateComponentsFormatter.unitsStyle .long (no such style)", D + "V19.swift",
     "import Foundation\n\nenum V19 {\n    static func text(_ t: TimeInterval) -> String? {\n        let f = DateComponentsFormatter()\n        f.unitsStyle = .full\n        return f.string(from: t)\n    }\n}\n",
     "import Foundation\n\nenum V19 {\n    static func text(_ t: TimeInterval) -> String? {\n        let f = DateComponentsFormatter()\n        f.unitsStyle = .long\n        return f.string(from: t)\n    }\n}\n")
pair("V20", "foundation", "URLSession.bytes(from:) without try", D + "V20.swift",
     "import Foundation\n\nenum V20 {\n    static func first(_ url: URL) async throws -> String? {\n        let (bytes, _) = try await URLSession.shared.bytes(from: url)\n        for try await line in bytes.lines { return line }\n        return nil\n    }\n}\n",
     "import Foundation\n\nenum V20 {\n    static func first(_ url: URL) async throws -> String? {\n        let (bytes, _) = await URLSession.shared.bytes(from: url)\n        for try await line in bytes.lines { return line }\n        return nil\n    }\n}\n")
pair("V21", "foundation", "AttributedString(markdown:) without try", D + "V21.swift",
     "import Foundation\n\nenum V21 {\n    static let text = (try? AttributedString(markdown: \"**fett**\")) ?? AttributedString(\"fett\")\n}\n",
     "import Foundation\n\nenum V21 {\n    static let text = AttributedString(markdown: \"**fett**\")\n}\n")
pair("V22", "foundation", "AsyncSequence (notifications(named:)) iterated with plain for-in instead of for await", D + "V22.swift",
     "import Foundation\n\nenum V22 {\n    static func watch() async {\n        for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) { break }\n    }\n}\n",
     "import Foundation\n\nenum V22 {\n    static func watch() async {\n        for _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) { break }\n    }\n}\n")
pair("V23", "uikit", "UIImage.systemImageNamed (Swift only has init(systemName:))", D + "V23.swift",
     "import UIKit\n\nenum V23 { static let star = UIImage(systemName: \"star.fill\") }\n",
     "import UIKit\n\nenum V23 { static let star = UIImage.systemImageNamed(\"star.fill\") }\n")
