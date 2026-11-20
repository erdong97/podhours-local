import UIKit
import WebKit

/// Single-screen shell: a full-screen WKWebView showing the bundled,
/// fully offline PodHours page (index.html). When the page asks through
/// the "podhealth" bridge, samples are read from HealthKit directly and
/// handed to the page in chunks; the file-import flow stays as fallback.
/// No network code anywhere.
class ViewController: UIViewController, WKUIDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private let healthReader = HealthKitReader()
    private var delivering = false

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.allowUniversalAccessFromFileURLs = true
        config.userContentController.add(self, name: "podhealth")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.uiDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.027, green: 0.039, blue: 0.078, alpha: 1.0)
        webView = wv
        view = wv
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    // MARK: - Page -> native bridge

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "podhealth",
              let body = message.body as? [String: Any],
              body["action"] as? String == "read",
              !delivering else { return }
        delivering = true
        healthReader.readHeadphoneSamples { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.delivering = false
                switch result {
                case .failure:
                    self.callJS("window.PodHealth && window.PodHealth.onError('read_failed')")
                case .success(let rows) where rows.isEmpty:
                    self.callJS("window.PodHealth && window.PodHealth.onError('denied_or_empty')")
                case .success(let rows):
                    self.deliver(rows)
                }
            }
        }
    }

    // MARK: - Native -> page delivery (chunked)

    private func callJS(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func deliver(_ rows: [[String: Any]]) {
        callJS("window.PodHealth && window.PodHealth.onStart(\(rows.count))")
        let chunkSize = 1500
        var index = 0
        func sendNext() {
            guard index < rows.count else {
                callJS("window.PodHealth && window.PodHealth.onDone()")
                return
            }
            let chunk = Array(rows[index..<min(index + chunkSize, rows.count)])
            index += chunk.count
            guard let data = try? JSONSerialization.data(withJSONObject: chunk),
                  let json = String(data: data, encoding: .utf8) else {
                callJS("window.PodHealth && window.PodHealth.onError('read_failed')")
                return
            }
            webView.evaluateJavaScript("window.PodHealth && window.PodHealth.addSamples(\(json))") { _, _ in
                sendNext()
            }
        }
        sendNext()
    }
}
