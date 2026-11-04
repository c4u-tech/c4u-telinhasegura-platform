import UIKit
import UniformTypeIdentifiers

/// Receives a link shared from another app and hands it to Telinha Segura,
/// which opens the suggestion screen with the link filled in.
///
/// The extension shows no interface of its own and reads nothing from the
/// shared text: the app checks the link and tells the guardian when it is
/// not a video it accepts.
class ShareViewController: UIViewController {
  /// The longest text forwarded; a video link is far shorter, and a cap
  /// keeps an accidental share of a long text from building a huge URL.
  private static let maxTextLength = 2048

  private static let scheme = "telinhasegura"
  private static let host = "sugerir"
  private static let unreserved = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  private var handled = false

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // The responder chain reaches the application only once the view is on
    // screen, so the hand-off waits until then.
    guard !handled else { return }
    handled = true
    loadSharedText { [weak self] text in
      DispatchQueue.main.async { self?.forward(text) }
    }
  }

  /// Loads the first shared link, or else the first shared text, and calls
  /// `completion` with nil when neither can be read.
  private func loadSharedText(_ completion: @escaping (String?) -> Void) {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    let url = UTType.url.identifier
    let text = UTType.plainText.identifier
    if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(url) }) {
      provider.loadItem(forTypeIdentifier: url, options: nil) { item, _ in
        completion(Self.string(from: item))
      }
    } else if let provider = providers.first(where: {
      $0.hasItemConformingToTypeIdentifier(text)
    }) {
      provider.loadItem(forTypeIdentifier: text, options: nil) { item, _ in
        completion(Self.string(from: item))
      }
    } else {
      completion(nil)
    }
  }

  private static func string(from item: NSSecureCoding?) -> String? {
    switch item {
    case let url as URL: return url.absoluteString
    case let text as String: return text
    case let data as Data: return String(data: data, encoding: .utf8)
    default: return nil
    }
  }

  /// Opens the suggestion screen in the app, with `text` in the link field
  /// when there is one, then closes the share sheet.
  private func forward(_ text: String?) {
    var components = URLComponents()
    components.scheme = Self.scheme
    components.host = Self.host
    if let text = text, !text.isEmpty,
      let value = String(text.prefix(Self.maxTextLength))
        .addingPercentEncoding(withAllowedCharacters: Self.unreserved)
    {
      // Every reserved character is escaped, "+" included, so the app reads
      // back exactly the shared text rather than a "+" turned into a space.
      components.percentEncodedQueryItems = [URLQueryItem(name: "texto", value: value)]
    }
    guard let target = components.url else {
      finish()
      return
    }
    openInApp(target) { [weak self] in self?.finish() }
  }

  private func finish() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }

  /// An extension cannot reach the shared application object directly, so
  /// the application is found by walking up the responder chain. `done` runs
  /// once the system has handled the open, or at once when there is no
  /// application to open it, so the sheet is never left hanging.
  private func openInApp(_ url: URL, done: @escaping () -> Void) {
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        application.open(url, options: [:]) { _ in
          DispatchQueue.main.async(execute: done)
        }
        return
      }
      responder = current.next
    }
    done()
  }
}
