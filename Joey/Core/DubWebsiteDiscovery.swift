import Foundation
import WebKit

public struct DubDiscoveryScan: Sendable {
    public var urls: [String]
    public var status: String
    public init(urls: [String], status: String) {self.urls = urls;self.status = status}
}

/// A user-triggered, bounded read of the existing public website and original
/// account page. WebKit provides normal browser rendering without extracting
/// desktop credentials, spoofing clients or bypassing access challenges.
@MainActor public final class DubWebsiteDiscovery: NSObject, WKNavigationDelegate {
    public static let websiteURL = URL(string:"https://www.thefileswithdub.com/broadcasts")!
    private let webView = WKWebView()
    private var continuation: CheckedContinuation<String,Error>?
    private var script = ""
    private var currentNavigation: WKNavigation?
    private var generation = 0
    private var timeout: Task<Void,Never>?

    nonisolated public static func catalogURLs(_ data: Data) throws -> [String] {
        guard data.count <= 4*1024*1024,
              let object = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let items = object["broadcasts"] as? [[String:Any]],items.count <= 500 else {
            throw JoeyError.dependency("DUB website broadcast catalog is malformed or exceeds the bounded scan")
        }
        return Array(Set(items.compactMap {item -> String? in
            guard let id = item["id"] as? String,let raw = item["sourceUrl"] as? String,
                  let url = try? DubBroadcastDiscovery.originalURL(raw),url.hasSuffix("/"+id) else {return nil}
            return url
        })).sorted()
    }
    nonisolated public static func profileURLs(_ data: Data) throws -> [String] {
        guard data.count <= 1024*1024,let urls = try JSONSerialization.jsonObject(with:data) as? [String],urls.count <= 500 else {
            throw JoeyError.dependency("Original X account page supplied an invalid broadcast-link scan")
        }
        return Array(Set(urls.compactMap {try? DubBroadcastDiscovery.originalURL($0)})).sorted()
    }

    public static func scan() async throws -> DubDiscoveryScan {
        let reader = DubWebsiteDiscovery()
        var urls = Set<String>(),failures: [String] = []
        do {
            let text = try await reader.read(websiteURL,script:"""
                const response = await fetch('/api/x-broadcasts', {credentials:'same-origin'});
                if (!response.ok) throw new Error('Website catalog HTTP ' + response.status);
                const text = await response.text();
                if (text.length > 4000000) throw new Error('Website catalog exceeds scan limit');
                return text;
                """)
            urls.formUnion(try catalogURLs(Data(text.utf8)))
        } catch {
            if error is CancellationError {throw error}
            failures.append("Website catalog: "+error.localizedDescription)
        }
        do {
            let text = try await reader.read(URL(string:DubBroadcastDiscovery.accountURL)!,script:"""
                for (let attempt=0; attempt<30; attempt++) {
                    const links = Array.from(document.querySelectorAll('a[href]')).map(a=>a.href)
                        .filter(url=>url.includes('/i/broadcasts/'));
                    if (links.length) return JSON.stringify(links.slice(0,500));
                    await new Promise(resolve=>setTimeout(resolve,500));
                }
                throw new Error('No original broadcast links visible; account access or page availability may be required');
                """)
            urls.formUnion(try profileURLs(Data(text.utf8)))
        } catch {
            if error is CancellationError {throw error}
            failures.append("Original X profile: "+error.localizedDescription)
        }
        guard !urls.isEmpty else {throw JoeyError.dependency(failures.joined(separator:"\n"))}
        let limitations = "Scanned DUB's website catalog and visible original X profile links. Each candidate requires original broadcaster and complete-replay verification. This bounded scan does not establish a complete account history."
        return DubDiscoveryScan(urls:urls.sorted(),status:([limitations]+failures).joined(separator:"\n"))
    }
    private func read(_ url: URL, script: String) async throws -> String {
        try Task.checkCancellation()
        self.script = script
        generation += 1
        webView.navigationDelegate = self
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {continuation in
                self.continuation = continuation
                timeout = Task { [weak self] in
                    do {try await Task.sleep(nanoseconds:45_000_000_000)} catch {return}
                    self?.finish(.failure(JoeyError.dependency("Public page scan timed out; resolve website/account access before retrying")))
                }
                currentNavigation = webView.load(URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:30))
                if currentNavigation == nil {finish(.failure(JoeyError.dependency("Public page navigation could not start")))}
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === currentNavigation else {return}
        guard continuation != nil,let url = webView.url,
              ["www.thefileswithdub.com","x.com"].contains(url.host),url.scheme == "https" else {
            finish(.failure(JoeyError.dependency("Discovery navigated outside its authorized public source")));return
        }
        let expectedGeneration = generation
        webView.callAsyncJavaScript(script,arguments:[:],in:nil,in:.page) { [weak self] result in
            guard self?.generation == expectedGeneration else {return}
            switch result {
            case .success(let value):
                guard let text = value as? String else {self?.finish(.failure(JoeyError.failed("Page supplied no readable discovery result")));return}
                self?.finish(.success(text))
            case .failure(let error):
                self?.finish(.failure(JoeyError.dependency("Public discovery read failed. "+String(error.localizedDescription.prefix(512)))))
            }
        }
    }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if navigation === currentNavigation {finish(.failure(error))}
    }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if navigation === currentNavigation {finish(.failure(error))}
    }
    private func finish(_ result: Result<String,Error>) {
        guard let continuation else {return}
        self.continuation = nil;timeout?.cancel();timeout = nil;currentNavigation = nil
        webView.stopLoading()
        continuation.resume(with:result)
    }
}
