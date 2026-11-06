import Foundation
import Testing
@testable import Siphon

struct YtDlpInstallTests {
    private let machO = Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2])

    @Test func detectsHomebrewFromCellarPath() {
        let kind = YtDlpInstall.detect(
            resolvedPath: "/opt/homebrew/Cellar/yt-dlp/2026.10.26/libexec/bin/yt-dlp",
            head: Data("#!/opt/homebrew/Cellar/yt-dlp/2026.10.26/libexec/bin/python\n".utf8),
            brew: "/opt/homebrew/bin/brew", pipx: nil)
        #expect(kind == .homebrew(brew: "/opt/homebrew/bin/brew"))
        #expect(kind.commandLine == "/opt/homebrew/bin/brew upgrade yt-dlp")
    }

    @Test func standaloneBinaryInHomebrewBinIsNotHomebrew() {
        let kind = YtDlpInstall.detect(resolvedPath: "/opt/homebrew/bin/yt-dlp", head: machO,
                                       brew: "/opt/homebrew/bin/brew", pipx: nil)
        #expect(kind == .standalone(ytDlp: "/opt/homebrew/bin/yt-dlp"))
        #expect(kind.updateCommand.arguments == ["-U"])
    }

    @Test func detectsPipxAndPip() {
        let pipxKind = YtDlpInstall.detect(
            resolvedPath: "/Users/me/.local/pipx/venvs/yt-dlp/bin/yt-dlp",
            head: Data("#!/Users/me/.local/pipx/venvs/yt-dlp/bin/python\n".utf8),
            brew: nil, pipx: "/opt/homebrew/bin/pipx")
        #expect(pipxKind == .pipx(pipx: "/opt/homebrew/bin/pipx"))

        let pipKind = YtDlpInstall.detect(
            resolvedPath: "/Users/me/.local/bin/yt-dlp",
            head: Data("#!/usr/local/bin/python3.12\n# -*- coding: utf-8 -*-".utf8),
            brew: nil, pipx: nil)
        #expect(pipKind == .pip(python: "/usr/local/bin/python3.12"))
        #expect(pipKind.updateCommand.arguments == ["-m", "pip", "install", "--upgrade", "yt-dlp"])
    }

    @Test func comparesVersions() {
        #expect(YtDlpInstall.isNewer("2026.10.26", than: "2026.07.04"))
        #expect(!YtDlpInstall.isNewer("2026.07.04", than: "2026.07.04"))
        #expect(YtDlpInstall.isNewer("2026.07.04.232815", than: "2026.07.04"))
        #expect(!YtDlpInstall.isNewer("2025.12.31", than: "2026.01.01"))
    }

    @Test func ageInDays() throws {
        let now = try #require(YtDlpInstall.releaseDate(of: "2026.11.06"))
        #expect(YtDlpInstall.ageInDays(of: "2026.07.04", now: now) == 125)
        #expect(YtDlpInstall.ageInDays(of: "nightly") == nil)
    }
}
