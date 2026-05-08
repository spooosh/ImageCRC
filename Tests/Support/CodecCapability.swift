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
    /// AppleAVEVA IOService return false (encode throws `encodeFailed`).
    /// Probe uses a 64x64 image — small enough to be sub-millisecond on real
    /// hardware, large enough to exercise the full encode pipeline (1x1
    /// can short-circuit special cases that mask the hardware failure).
    static let avifEncodeAvailable: Bool = {
        let img = SyntheticImage.solid(width: 64, height: 64)
        return (try? AVIFEncoder.encode(image: img, quality: 0.5)) != nil
    }()

    /// True iff HEIC encode via ImageIO works on this host. Same hardware
    /// dependency as AVIF (HEVC encoder via AppleAVEVA). On CI runners the
    /// destination creation succeeds but `CGImageDestinationFinalize` fails;
    /// the 64x64 probe catches that before any test runs.
    static let heicEncodeAvailable: Bool = {
        let img = SyntheticImage.solid(width: 64, height: 64)
        return (try? HEICEncoder.encode(image: img, quality: 0.5)) != nil
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
