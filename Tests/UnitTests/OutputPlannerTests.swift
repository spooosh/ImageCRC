import Testing
@testable import ImageCRC

@Suite("OutputPlanner")
struct OutputPlannerTests {
    @Test("Direct output formats always encode to that format regardless of input")
    func directFormats() {
        let inputs: [InputFormat] = [.jpeg, .png, .svg, .webp, .avif, .heic]
        let cases: [(OutputFormat, EncoderFormat)] = [
            (.jpeg, .jpeg),
            (.png,  .png),
            (.webp, .webp),
            (.avif, .avif),
        ]
        for input in inputs {
            for (selected, expected) in cases {
                let plan = OutputPlanner.plan(for: input, selected: selected)
                #expect(plan == .encode(expected),
                        "Expected \(expected) for input=\(input) selected=\(selected), got \(plan)")
            }
        }
    }

    @Test("sameAsOrigin maps each raster input to the matching encoder")
    func sameAsOriginRaster() {
        let cases: [(InputFormat, EncoderFormat)] = [
            (.jpeg, .jpeg),
            (.png,  .png),
            (.webp, .webp),
            (.avif, .avif),
            (.heic, .heic),
        ]
        for (input, expected) in cases {
            let plan = OutputPlanner.plan(for: input, selected: .sameAsOrigin)
            #expect(plan == .encode(expected))
        }
    }

    @Test("sameAsOrigin + SVG resolves to a verbatim copy")
    func sameAsOriginSVG() {
        let plan = OutputPlanner.plan(for: .svg, selected: .sameAsOrigin)
        #expect(plan == .copy)
    }
}

@Suite("OutputPlanner — exhaustiveness")
struct OutputPlannerExhaustivenessTests {
    @Test("every InputFormat has an explicit sameAsOrigin plan",
          arguments: InputFormat.allCases)
    func sameAsOriginExhaustive(input: InputFormat) {
        let plan = OutputPlanner.plan(for: input, selected: .sameAsOrigin)
        // Plan must be either an explicit encode for that format, or a copy.
        // A bogus default-clause that returns .encode(.jpeg) would fail this
        // for every input that isn't actually JPEG.
        switch (input, plan) {
        case (.jpeg, .encode(.jpeg)),
             (.png,  .encode(.png)),
             (.webp, .encode(.webp)),
             (.avif, .encode(.avif)),
             (.heic, .encode(.heic)),
             (.svg,  .copy):
            break  // expected
        default:
            Issue.record("Unexpected sameAsOrigin plan for \(input): \(plan)")
        }
    }

    @Test("every InputFormat × every direct OutputFormat encodes to that format",
          arguments: InputFormat.allCases,
          [OutputFormat.jpeg, .png, .webp, .avif])
    func directFormatsExhaustive(input: InputFormat, selected: OutputFormat) {
        let expected: EncoderFormat = {
            switch selected {
            case .jpeg: return .jpeg
            case .png:  return .png
            case .webp: return .webp
            case .avif: return .avif
            case .sameAsOrigin: fatalError("not reachable")
            }
        }()
        #expect(OutputPlanner.plan(for: input, selected: selected) == .encode(expected),
                "for input=\(input) selected=\(selected)")
    }
}
