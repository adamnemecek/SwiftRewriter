import SwiftAST

/// Represents an Objective-C selector signature.
public struct SelectorSignature: Hashable, Codable {
    public var isStatic: Bool
    public var keywords: [String?]
    
    public init(isStatic: Bool, keywords: [String?]) {
        self.isStatic = isStatic
        self.keywords = keywords
    }
}

public extension FunctionCallPostfix {
    public func identifierWith(methodName: String) -> FunctionIdentifier {
        let arguments = self.arguments.map { $0.label }
        
        return FunctionIdentifier(name: methodName, parameterNames: arguments)
    }
    
    /// Generates an Objective-C selector from this function call united with
    /// a given method name.
    public func selectorWith(methodName: String) -> SelectorSignature {
        let selectors: [String?]
            = [methodName] + arguments.map { $0.label }
        
        return SelectorSignature(isStatic: false, keywords: selectors)
    }
}
