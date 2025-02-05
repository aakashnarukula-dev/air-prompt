import SwiftUI
import WebKit

final class LoginWebViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {
    let loginURL: URL
    let onToken: (String) -> Void
    private var webView: WKWebView!

    init(loginURL: URL, onToken: @escaping (String) -> Void) {
        self.loginURL = loginURL
        self.onToken = onToken
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "airprompt")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        self.webView = wv
        self.view = wv
        wv.load(URLRequest(url: loginURL))
    }

    func userContentController(_ uc: WKUserContentController, didReceive msg: WKScriptMessage) {
        guard msg.name == "airprompt",
              let body = msg.body as? [String: Any],
              let token = body["idToken"] as? String else { return }
        onToken(token)
    }
}

struct LoginWebView: NSViewControllerRepresentable {
    let loginURL: URL
    let onToken: (String) -> Void

    func makeNSViewController(context: Context) -> LoginWebViewController {
        LoginWebViewController(loginURL: loginURL, onToken: onToken)
    }

    func updateNSViewController(_ vc: LoginWebViewController, context: Context) {}
}
