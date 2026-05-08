// Tests/Support/CodecCapability.swift
import Foundation
@testable import ImageCRC

/// Runtime probes for codec/binary availability on the host. Used to gate
/// tests that depend on hardware codecs (AppleAVEVA / HEVC / AV1) or external
/// binaries (pngquant). Each probe runs once at test bundle load and the
/// result is cached for the life of the process.
///
/// Why runtime probes instead of env vars: xcodebuild's host-app test runner
/// pattern does not propagate process-level environment into the runner
/// process, so env-flag gating from the workflow doesn't reach
/// `ProcessInfo.processInfo.environment` at test time. A runtime probe
/// (try-and-see) is robust to that and self-documents the precondition.
enum CodecCapability {
    /// True iff AVIF encode via ImageIO works on this host. Apple Silicon with
    /// hardware AV1 returns true; virtualised macOS CI runners lacking the
    /// AppleAVEVA IOService return false. Probe at q=1.0 with a 128x128
    /// gradient — matches the strictest matrix-test case (lossless mode,
    /// real entropy) so a passing probe guarantees every gated test reaches
    /// the same codepath.
    static let avifEncodeAvailable: Bool = {
        let img = SyntheticImage.gradient(width: 128, height: 128)
        return (try? AVIFEncoder.encode(image: img, quality: 1.0)) != nil
    }()

    /// True iff HEIC encode via ImageIO works on this host. HEIC is more
    /// permissive than AVIF: destination creation and mid-quality encodes
    /// can succeed via fallback paths even without the HEVC driver, while
    /// q=1.0 (lossless HEVC) goes through `CGImageDestinationFinalize`
    /// which depends on the missing AppleAVEVA driver. Mid-quality probes
    /// returned false-positive `true` against tests that include q=1.0;
    /// probing at q=1.0 directly is the only reliable signal.
    static let heicEncodeAvailable: Bool = {
        let img = SyntheticImage.gradient(width: 128, height: 128)
        return (try? HEICEncoder.encode(image: img, quality: 1.0)) != nil
    }()

    /// True iff a pngquant binary is reachable on a known PATH location. The
    /// production lookup also checks `Bundle.main/Contents/Resources/bin`,
    /// but that's irrelevant to the test bundle; the brew-installed path
    /// is what matters for CI and dev machines with `brew install pngquant`.
    static let pngquantAvailable: Bool = {
        let candidates = [
            "/opt/homebrew/bin/pngquant",
            "/usr/local/bin/pngquant",
            "/usr/bin/pngquant",
        ]
        return candidates.contains {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }()
}
