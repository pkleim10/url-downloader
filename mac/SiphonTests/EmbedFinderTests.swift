import Foundation
import Testing
@testable import Siphon

struct EmbedFinderTests {
    let page = URL(string: "https://puncher.tube/video/1185159/clip.html")!

    @Test func findsThePlayerBoxIframe() {
        let html = """
        <iframe src="https://googleads.g.doubleclick.net/pagead/ads?x=1" width="300"></iframe>
        <div class="player-box">
            <iframe src="https://x-x-x.tube/embed/270856/" frameborder="0" allowfullscreen></iframe>
        </div>
        <iframe src="https://www.facebook.com/plugins/like.php?href=x"></iframe>
        """
        #expect(EmbedFinder.find(in: html, pageURL: page)?.absoluteString == "https://x-x-x.tube/embed/270856/")
    }

    @Test func resolvesRelativeAndSingleQuotedSources() {
        let html = "<div id='video-wrap'><iframe allowfullscreen src='/embed/42?autoplay=1&amp;t=0'></iframe></div>"
        #expect(EmbedFinder.find(in: html, pageURL: page)?.absoluteString == "https://puncher.tube/embed/42?autoplay=1&t=0")
    }

    @Test func ignoresPagesWithoutAPlayerFrame() {
        let html = """
        <iframe src="https://www.google.com/recaptcha/api2/anchor?k=1"></iframe>
        <iframe src="https://example.com/newsletter-signup"></iframe>
        """
        #expect(EmbedFinder.find(in: html, pageURL: page) == nil)
    }

    @Test func doesNotTreatHostsEndingInXAsTwitter() {
        let html = #"<iframe src="https://txxx.com/embed/21277783/" allowfullscreen></iframe>"#
        #expect(EmbedFinder.find(in: html, pageURL: page)?.host == "txxx.com")
        let x = #"<iframe src="https://x.com/i/embed/123" allowfullscreen></iframe>"#
        #expect(EmbedFinder.find(in: x, pageURL: page) == nil)
    }

    @Test func prefersTheMostPlayerLikeFrame() {
        let html = """
        <iframe src="https://other.example/widget" allowfullscreen></iframe>
        <div class="video-container"><iframe src="https://cdn.example/e/abc" allowfullscreen></iframe></div>
        """
        #expect(EmbedFinder.find(in: html, pageURL: page)?.absoluteString == "https://cdn.example/e/abc")
    }
}
