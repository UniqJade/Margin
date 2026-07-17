import Foundation

struct ConversionFailure: Error {}

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let values = try JSONDecoder().decode([String].self, from: input)
    let transform = StringTransform("Traditional-Simplified")
    let converted = try values.map { value -> String in
        guard let result = value.applyingTransform(transform, reverse: false) else {
            throw ConversionFailure()
        }
        return result
    }
    let output = try JSONEncoder().encode(converted)
    FileHandle.standardOutput.write(output)
} catch {
    FileHandle.standardError.write(Data("conversion failed\n".utf8))
    exit(1)
}
