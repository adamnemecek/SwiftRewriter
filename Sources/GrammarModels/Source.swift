/// A protocol for a source for source code.
/// It is used to group up units of compilation to aid in checking of access control
/// across compilation unit/file boundaries.
public protocol Source {
    /// Gets the full file name for this source file.
    var filePath: String { get }
    
    func isEqual(to other: Source) -> Bool
    
    func stringIndex(forCharOffset offset: Int) -> String.Index
    
    /// Gets the line number at a given source location
    func lineNumber(at index: String.Index) -> Int
    func columnNumber(at index: String.Index) -> Int
}

/// Represents an invalid source, which is neither a file nor a string source.
/// Used to represent an invalid original source location for a node.
public struct InvalidSource: Source {
    private static let _stringIndex = "".startIndex
    
    /// Gets the default invalid source instance singleton.
    public static let invalid = InvalidSource()
    
    public let filePath: String = "<invalid>"
    
    private init() {
        
    }
    
    public func stringIndex(forCharOffset offset: Int) -> String.Index {
        return InvalidSource._stringIndex
    }
    
    public func isEqual(to other: Source) -> Bool {
        return other is InvalidSource
    }
    
    public func lineNumber(at index: String.Index) -> Int {
        return 0
    }
    
    public func columnNumber(at index: String.Index) -> Int {
        return 0
    }
}
