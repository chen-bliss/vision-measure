import SwiftUI
import UniformTypeIdentifiers

struct PatternImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png,.json] }
    var data: Data
    init(data:Data) { self.data=data }
    init(configuration:ReadConfiguration) throws { data=configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}

struct PatternExportRequest {
    let data: Data
    let filename: String
    let completion: (Result<URL,Error>) -> Void
}
