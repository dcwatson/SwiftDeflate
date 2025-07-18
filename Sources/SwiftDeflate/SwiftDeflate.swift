import CLibDeflate
import Foundation

public enum CompressionError: Error {
    case badCompressor
    case compressionFailed
}

public enum DecompressionError: Error {
    case badDecompressor
    case badData
    case shortOutput
    case insufficientSpace
    case unknownError
    case unknownSize
}

typealias BoundFunction = (OpaquePointer, Int) -> Int
typealias CompressFunction =
    (OpaquePointer, UnsafeRawPointer, Int, UnsafeMutableRawPointer, Int) -> Int
typealias DecompressFunction =
    (OpaquePointer, UnsafeRawPointer, Int, UnsafeMutableRawPointer, Int, UnsafeMutablePointer<Int>?)
    -> libdeflate_result

public enum CompressionType: CaseIterable, Sendable {
    case gzip
    case zlib
    case deflate

    var bound: BoundFunction {
        switch self {
        case .gzip:
            return libdeflate_gzip_compress_bound
        case .zlib:
            return libdeflate_zlib_compress_bound
        case .deflate:
            return libdeflate_deflate_compress_bound
        }
    }

    var compress: CompressFunction {
        switch self {
        case .gzip:
            return libdeflate_gzip_compress
        case .zlib:
            return libdeflate_zlib_compress
        case .deflate:
            return libdeflate_deflate_compress
        }
    }

    var decompress: DecompressFunction {
        switch self {
        case .gzip:
            return libdeflate_gzip_decompress
        case .zlib:
            return libdeflate_zlib_decompress
        case .deflate:
            return libdeflate_deflate_decompress
        }
    }
}

public enum CompressionLevel: RawRepresentable, CaseIterable, Sendable {
    case none
    case fastest
    case `default`
    case best
    case custom(Int)

    public static let allCases = (0...12).map { CompressionLevel(rawValue: $0) }

    public init(rawValue: Int) {
        switch rawValue {
        case 0: self = .none
        case 1: self = .fastest
        case 6: self = .default
        case 12: self = .best
        default: self = .custom(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
        case .none: return 0
        case .fastest: return 1
        case .default: return 6
        case .best: return 12
        case .custom(let value): return value
        }
    }
}

extension CompressionLevel: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(rawValue: value)
    }
}

public enum DecompressedSize {
    case original(Int)
    case maximumOf(Int)
    case auto
}

public class Compressor {
    let _compressorPtr: OpaquePointer?

    public init(_ compressionLevel: CompressionLevel = .default) {
        _compressorPtr = libdeflate_alloc_compressor(Int32(compressionLevel.rawValue))
    }

    deinit {
        if let _compressorPtr {
            libdeflate_free_compressor(_compressorPtr)
        }
    }

    public func compress(_ data: Data, type: CompressionType = .gzip)
        -> Result<Data, CompressionError>
    {
        guard let compressor = _compressorPtr else {
            return .failure(.badCompressor)
        }

        if data.isEmpty { return .success(data) }

        let srcCount = data.count
        let bound = type.bound(compressor, data.count)
        let dstPtr = UnsafeMutableRawPointer.allocate(byteCount: bound, alignment: 1)
        let compressedSize = data.withUnsafeBytes { src in
            return type.compress(
                compressor,
                src.baseAddress!,
                srcCount,
                dstPtr,
                bound
            )
        }

        if compressedSize <= 0 {
            dstPtr.deallocate()
            return .failure(.compressionFailed)
        }

        return .success(Data(bytesNoCopy: dstPtr, count: compressedSize, deallocator: .free))
    }
}

public func gzipSize(_ data: Data) -> Int? {
    guard data.count >= 6, data.isGzipped else { return nil }
    let i = data.count - 4
    return Int(
        UInt32(data[i])
            | (UInt32(data[i + 1]) << 8)
            | (UInt32(data[i + 2]) << 16)
            | (UInt32(data[i + 3]) << 24)
    )
}

public class Decompressor {
    let _decompressorPtr: OpaquePointer?

    public init() {
        _decompressorPtr = libdeflate_alloc_decompressor()
    }

    deinit {
        if let _decompressorPtr {
            libdeflate_free_decompressor(_decompressorPtr)
        }
    }

    public func decompress(
        _ data: Data,
        type: CompressionType = .gzip,
        size: DecompressedSize = .auto
    ) -> Result<Data, DecompressionError> {
        guard let decompressor = _decompressorPtr else {
            return .failure(.badDecompressor)
        }

        if data.isEmpty { return .success(data) }

        var decompressedData: Data
        var actualSize: UnsafeMutablePointer<Int>? = nil
        switch size {
        case .original(let count):
            decompressedData = Data(count: count)
        case .maximumOf(let count):
            decompressedData = Data(count: count)
            actualSize = .allocate(capacity: 1)
        case .auto:
            guard let size = gzipSize(data) else { return .failure(.unknownSize) }
            decompressedData = Data(count: size)
        }


        defer { actualSize?.deallocate() }

        let srcCount = data.count
        let dstCount = decompressedData.count
        let result = data.withUnsafeBytes { src in
            decompressedData.withUnsafeMutableBytes { dst in
                return type.decompress(
                    decompressor,
                    src.baseAddress!,
                    srcCount,
                    dst.baseAddress!,
                    dstCount,
                    actualSize
                )
            }
        }

        switch result {
        case LIBDEFLATE_SUCCESS:
            if let actualSize, actualSize.pointee < dstCount {
                return .success(decompressedData[0..<actualSize.pointee])
            }
            return .success(decompressedData)
        case LIBDEFLATE_BAD_DATA:
            return .failure(.badData)
        case LIBDEFLATE_SHORT_OUTPUT:
            return .failure(.shortOutput)
        case LIBDEFLATE_INSUFFICIENT_SPACE:
            return .failure(.insufficientSpace)
        default:
            return .failure(.unknownError)
        }
    }
}

extension Data {
    public var isGzipped: Bool {
        return self.starts(with: [0x1f, 0x8b])
    }

    public func gzipped(_ compressionLevel: CompressionLevel = .default) throws -> Data {
        try Compressor(compressionLevel).compress(self).get()
    }

    public func gunzipped() throws -> Data {
        try Decompressor().decompress(self).get()
    }
}
