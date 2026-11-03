import XCTest
@testable import JoeyCore

final class SourceClassificationEvidenceTests: XCTestCase {
    private func parse(rows: String, frames: String, header: String? = nil) throws -> SourceClassificationProof {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let hashes = root.appendingPathComponent("hashes"), metadata = root.appendingPathComponent("frames")
        let required = "#format: frame checksums\n#version: 2\n#hash: SHA256\n#media_type 0: video\n#codec_id 0: rawvideo\n"
        try Data(((header ?? required)+rows).utf8).write(to:hashes)
        try Data(frames.utf8).write(to:metadata)
        return try Media.parseClassificationProof(hashes:hashes,frames:metadata,sha256:String(repeating:"b",count:64))
    }

    private let pictureHash = String(repeating:"a",count:64)
    private func frame(_ number: Int, geometry: String = "160x90", format: String = "yuv420p") -> String {
        let size = geometry.split(separator:"x")
        return "width=\(size[0])|height=\(size[1])|pix_fmt=\(format)"+(number == 0 ? "|\n" : "\n")
    }

    func testGeometryFormatAndByteSizeMustAllRemainIdentical() throws {
        let rows = "0, 0, 0, 1, 21600, \(pictureHash)\n0, 1, 1, 1, 21600, \(pictureHash)\n"
        let same = try parse(rows:rows,frames:frame(0)+frame(1))
        XCTAssertEqual(same.uniformFrameSHA256,pictureHash);XCTAssertEqual(same.decodedFrameCount,2)
        for second in [frame(1,geometry:"90x160"),frame(1,format:"yuvj420p")] {
            let changed = try parse(rows:rows,frames:frame(0)+second)
            XCTAssertNil(changed.uniformFrameSHA256,"Same hash cannot hide geometry or format changes")
        }
        let resized = try parse(rows:"0, 0, 0, 1, 21600, \(pictureHash)\n0, 1, 1, 1, 43200, \(pictureHash)\n",frames:frame(0)+frame(1))
        XCTAssertNil(resized.uniformFrameSHA256)
    }

    func testMalformedOrIncompleteEvidenceCannotProveStaticVideo() throws {
        let row = "0, 0, 0, 1, 21600, \(pictureHash)\n"
        for rows in ["","0, 0, 0, 1, 21600, invalid\n","1, 0, 0, 1, 21600, \(pictureHash)\n",row+row,"0, bad, 0, 1, 21600, \(pictureHash)\n"] {
            XCTAssertThrowsError(try parse(rows:rows,frames:frame(0)))
        }
        for metadata in ["",frame(0,geometry:"0x90"),frame(0)+frame(1),"width=160|height=90\n","width=160|height=90|pix_fmt=unknown\n"] {
            XCTAssertThrowsError(try parse(rows:row,frames:metadata))
        }
        XCTAssertThrowsError(try parse(rows:row,frames:frame(0),header:"#hash: MD5\n"))
    }
}
