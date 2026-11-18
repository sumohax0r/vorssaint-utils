// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import PackageDescription
let package = Package(
    name: "VorssaintDictationEngine",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git",
                 revision: "2d6c42ca5f3accc0faf9fee9e0fff5b9b2cf6042", traits: [])
    ],
    targets: [.executableTarget(name: "DictationEngine", dependencies: [
        .product(name: "FluidAudio", package: "FluidAudio")
    ])]
)
