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
