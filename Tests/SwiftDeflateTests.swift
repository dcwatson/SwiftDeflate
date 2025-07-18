//
//  SwiftDeflateTests.swift
//  SwiftDeflate
//
//  Created by Daniel Watson on 7/17/25.
//

import Foundation
import SwiftDeflate
import Testing

let testData: Data = {
    var d = Data()
    for _ in 0..<1024 {
        d.append(contentsOf: "Hello world, this is a test!!!".utf8)
    }
    return d
}()

@Test(arguments: CompressionLevel.allCases, CompressionType.allCases)
func testRoundTrip(compressionLevel: CompressionLevel, type: CompressionType) async throws {
    let compressed = try Compressor(compressionLevel).compress(testData, type: type).get()
    let result = Decompressor().decompress(compressed, type: type, size: .original(testData.count))
    #expect(result == .success(testData))
}

@Test(arguments: CompressionLevel.allCases)
func testAutoSize(compressionLevel: CompressionLevel) async throws {
    let compressed = try Compressor(compressionLevel).compress(testData).get()
    #expect(gzipSize(compressed) == testData.count)
    let result = Decompressor().decompress(compressed)
    #expect(result == .success(testData))
}

@Test func testUnknownSize() async throws {
    let compressed = try Compressor().compress(testData, type: .zlib).get()
    let result = Decompressor().decompress(compressed)
    #expect(result == .failure(.unknownSize))
}

@Test(arguments: [-1, 13])
func testBadCompressor(compressionLevel: Int) async throws {
    let result = Compressor(.custom(compressionLevel)).compress(testData)
    #expect(result == .failure(.badCompressor))
}

@Test func testShortOutput() async throws {
    let compressed = try Compressor().compress(testData).get()
    let result = Decompressor().decompress(compressed, size: .original(testData.count + 10))
    #expect(result == .failure(.shortOutput))
}

@Test func testExtraSpace() async throws {
    let compressed = try Compressor().compress(testData).get()
    let result = Decompressor().decompress(compressed, size: .maximumOf(testData.count + 10))
    #expect(result == .success(testData))
}

@Test func testInsufficientSpaceKnown() async throws {
    let compressed = try Compressor().compress(testData).get()
    let result = Decompressor().decompress(compressed, size: .original(testData.count - 10))
    #expect(result == .failure(.insufficientSpace))
}

@Test func testInsufficientSpaceMaximum() async throws {
    let compressed = try Compressor().compress(testData).get()
    let result = Decompressor().decompress(compressed, size: .maximumOf(testData.count - 10))
    #expect(result == .failure(.insufficientSpace))
}

@Test(arguments: CompressionType.allCases)
func testBadData(type: CompressionType) async throws {
    let result = Decompressor().decompress(Data([1, 2, 3, 4]), type: type, size: .maximumOf(1024))
    #expect(result == .failure(.badData))
}

@Test func testGzipDataExtensions() async throws {
    let compressed = try testData.gzipped()
    #expect(compressed.isGzipped)
    let decompressed = try compressed.gunzipped()
    #expect(decompressed == testData)
}

@Test func testCompressionLevelLiteral() async throws {
    #expect(CompressionLevel.none == 0)
    #expect(CompressionLevel.fastest == 1)
    #expect(CompressionLevel.default == 6)
    #expect(CompressionLevel.best == 12)
}

@Test func testEmptyData() async throws {
    #expect(try Compressor().compress(Data()).get() == Data())
    #expect(try Decompressor().decompress(Data()).get() == Data())
}
