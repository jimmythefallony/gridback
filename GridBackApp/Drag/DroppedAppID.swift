import AppKit
import UniformTypeIdentifiers

/// In-app drag payload for an app id. Plain text keeps the drag inside GridBack
/// without a custom file type.
enum DroppedAppID {
    static func provider(for id: String) -> NSItemProvider {
        let provider = NSItemProvider(object: id as NSString)
        provider.suggestedName = id
        return provider
    }

    static func load(from providers: [NSItemProvider], completion: @escaping (String?) -> Void) {
        guard let provider = providers.first else {
            completion(nil)
            return
        }
        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                let text = (object as? NSString) as String?
                DispatchQueue.main.async {
                    completion(clean(text))
                }
            }
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            DispatchQueue.main.async {
                completion(clean(text))
            }
        }
    }

    private static func clean(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
