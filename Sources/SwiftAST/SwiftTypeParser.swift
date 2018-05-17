import MiniLexer

/// Support for parsing of Swift type signatures into `SwiftType` structures.
public class SwiftTypeParser {
    /// Parses a Swift type from a given type string
    public static func parse(from string: String) throws -> SwiftType {
        let lexer = Lexer(input: string)
        
        let result = try parse(from: lexer)
        
        if !lexer.isEof() {
            throw unexpectedTokenError(lexer: TokenizerLexer<SwiftTypeToken>(lexer: lexer))
        }
        
        return result
    }
    
    /// Parses a Swift type from a given lexer
    ///
    /// Formal Swift type grammar:
    ///
    /// ```
    /// swift-type
    ///     : tuple
    ///     | block
    ///     | array
    ///     | dictionary
    ///     | type-identifier
    ///     | optional
    ///     | implicitly-unwrapped-optional
    ///     | protocol-composition
    ///     | metatype
    ///     ;
    ///
    /// tuple
    ///     : '(' tuple-element (',' tuple-element)* ')' ;
    ///
    /// tuple-element
    ///     : swift-type
    ///     | identifier ':' swift-type
    ///     ;
    ///
    /// block
    ///     : '(' block-argument-list '...'? ')' '->' swift-type ;
    ///
    /// array
    ///     : '[' type ']' ;
    ///
    /// dictionary
    ///     : '[' type ':' type ']' ;
    ///
    /// type-identifier
    ///     : identifier generic-argument-clause?
    ///     | identifier generic-argument-clause? '.' type-identifier
    ///     ;
    ///
    /// generic-argument-clause
    ///     : '<' swift-type (',' swift-type)* '>'
    ///
    /// optional
    ///     : swift-type '?' ;
    ///
    /// implicitly-unwrapped-optional
    ///     : swift-type '!' ;
    ///
    /// protocol-composition
    ///     : type-identifier '&' type-identifier ('&' type-identifier)* ;
    ///
    /// meta-type
    ///     : swift-type '.' 'Type'
    ///     | swift-type '.' 'Protocol'
    ///     ;
    ///
    /// -- Block
    /// block-argument-list
    ///     : block-argument (',' block-argument)* ;
    ///
    /// block-argument
    ///     : (argument-label identifier? ':') arg-attribute-list? 'inout'? swift-type ;
    ///
    /// argument-label
    ///     : '_'
    ///     | identifier
    ///     ;
    ///
    /// arg-attribute-list
    ///     : attribute+
    ///     ;
    ///
    /// arg-attribute
    ///     : '@' identifier
    ///     ;
    ///
    /// -- Atoms
    /// identifier
    ///     : (letter | '_') (letter | '_' | digit)+ ;
    ///
    /// letter : [a-zA-Z]
    ///
    /// digit : [0-9]
    /// ```
    public static func parse(from lexer: Lexer) throws -> SwiftType {
        let tokenizer = TokenizerLexer<SwiftTypeToken>(lexer: lexer)
        return try parseType(tokenizer)
    }
    
    private static func parseType(_ lexer: TokenizerLexer<SwiftTypeToken>) throws -> SwiftType {
        let type: SwiftType
        
        if lexer.tokenType(is: .identifier) {
            let ident = try parseNominalType(lexer)
            
            // Void type
            if ident == .typeName("Void") {
                type = .void
            } else if lexer.tokenType(is: .ampersand) {
                // Protocol type composition
                let prot
                    = try verifyProtocolCompositionTrailing(after: [.nominal(ident)],
                                                            lexer: lexer)
                
                type = .protocolComposition(prot)
            } else if lexer.tokenType(is: .period) {
                // Verify meta-type access
                var isMetatypeAccess = false
                
                let periodBT = lexer.backtracker()
                if lexer.consumeToken(ifTypeIs: .period) != nil {
                    // Backtrack out of this method, in case it's actually a metatype
                    // trailing
                    if let identifier = lexer.consumeToken(ifTypeIs: .identifier)?.value,
                        identifier == "Type" || identifier == "Protocol" {
                        isMetatypeAccess = true
                    }
                    
                    periodBT.backtrack()
                }
                
                // Nested type
                if !isMetatypeAccess {
                    type = .nested(try parseNestedType(lexer, after: ident))
                } else {
                    type = .nominal(ident)
                }
            } else {
                type = .nominal(ident)
            }
        } else if lexer.tokenType(is: .openBrace) {
            type = try parseArrayOrDictionary(lexer)
        } else if lexer.tokenType(is: .openParens) {
            type = try parseTupleOrBlock(lexer)
        } else {
            throw unexpectedTokenError(lexer: lexer)
        }
        
        return try verifyTrailing(after: type, lexer: lexer)
    }
    
    /// Parses a nominal identifier type.
    ///
    /// ```
    /// type-identifier
    ///     : identifier generic-argument-clause?
    ///     | identifier generic-argument-clause? '.' type-identifier
    ///     ;
    ///
    /// generic-argument-clause
    ///     : '<' swift-type (',' swift-type)* '>'
    /// ```
    private static func parseNominalType(_ lexer: TokenizerLexer<SwiftTypeToken>) throws -> NominalSwiftType {
        
        guard let identifier = lexer.consumeToken(ifTypeIs: .identifier) else {
            throw unexpectedTokenError(lexer: lexer)
        }
        
        // Attempt a generic type parse
        let type =
            try verifyGenericArgumentsTrailing(after: String(identifier.value),
                                               lexer: lexer)
        
        return type
    }
    
    private static func parseNestedType(_ lexer: TokenizerLexer<SwiftTypeToken>,
                                        after base: NominalSwiftType) throws -> NestedSwiftType {
        
        var types = [base]
        
        repeat {
            let periodBT = lexer.backtracker()
            
            try lexer.advance(over: .period)
            
            do {
                // Check if the nesting is not actually a metatype access
                let identBT = lexer.backtracker()
                let ident = lexer.consumeToken(ifTypeIs: .identifier)?.value
                if ident == "Type" || ident == "Protocol" {
                    periodBT.backtrack()
                    break
                }
                
                identBT.backtrack()
            }
            
            let next = try parseNominalType(lexer)
            types.append(next)
        } while lexer.tokenType(is: .period)
        
        return NestedSwiftType.fromCollection(types)
    }
    
    /// Parses a protocol composition for an identifier type.
    ///
    /// ```
    /// protocol-composition
    ///     : type-identifier '&' type-identifier ('&' type-identifier)* ;
    /// ```
    private static func verifyProtocolCompositionTrailing(
        after types: [ProtocolCompositionComponent],
        lexer: TokenizerLexer<SwiftTypeToken>) throws -> ProtocolCompositionSwiftType {
        
        var types = types
        
        while lexer.consumeToken(ifTypeIs: .ampersand) != nil {
            // If we find a parenthesis, unwrap the tuple (if it's a tuple) and
            // check if all its inner types are nominal, then it's a composable
            // type.
            if lexer.tokenType(is: .openParens) {
                let toParens = lexer.backtracker()
                
                let type = try parseType(lexer)
                switch type {
                case .nominal(let nominal):
                    types.append(.nominal(nominal))
                case .nested(let nested):
                    types.append(.nested(nested))
                case .protocolComposition(let list):
                    types.append(contentsOf: list)
                default:
                    toParens.backtrack()
                    
                    throw notProtocolComposableError(type: type, lexer: lexer)
                }
            } else {
                types.append(.nominal(try parseNominalType(lexer)))
            }
        }
        
        return .fromCollection(types)
    }
    
    /// Parses a generic argument clause.
    ///
    /// ```
    /// generic-argument-clause
    ///     : '<' swift-type (',' swift-type)* '>'
    /// ```
    private static func verifyGenericArgumentsTrailing(
        after typeName: String, lexer: TokenizerLexer<SwiftTypeToken>) throws -> NominalSwiftType {
        
        guard lexer.consumeToken(ifTypeIs: .openBracket) != nil else {
            return .typeName(typeName)
        }
        
        var afterComma = false
        var types: [SwiftType] = []
        
        repeat {
            afterComma = false
            
            types.append(try parseType(lexer))
            
            if lexer.consumeToken(ifTypeIs: .comma) != nil {
                afterComma = true
                continue
            }
            try lexer.advance(over: .closeBracket)
            break
        } while !lexer.isEof
        
        if afterComma {
            throw expectedTypeNameError(lexer: lexer)
        }
        
        return .generic(typeName, parameters: .fromCollection(types))
    }
    
    /// Parses an array or dictionary type.
    ///
    /// ```
    /// array
    ///     : '[' type ']' ;
    ///
    /// dictionary
    ///     : '[' type ':' type ']' ;
    /// ```
    private static func parseArrayOrDictionary(_ lexer: TokenizerLexer<SwiftTypeToken>) throws -> SwiftType {
        try lexer.advance(over: .openBrace)
        
        let type1 = try parseType(lexer)
        var type2: SwiftType?
        
        if lexer.tokenType(is: .colon) {
            lexer.consumeToken(ifTypeIs: .colon)
            
            type2 = try parseType(lexer)
        }
        
        try lexer.advance(over: .closeBrace)
        
        if let type2 = type2 {
            return .dictionary(key: type1, value: type2)
        }
        
        return .array(type1)
    }
    
    /// Parses a tuple or block type
    ///
    /// ```
    /// tuple
    ///     : '(' tuple-element (',' tuple-element)* ')' ;
    ///
    /// tuple-element
    ///     : swift-type
    ///     | identifier ':' swift-type
    ///     ;
    ///
    /// block
    ///     : '(' block-argument-list '...'? ')' '->' swift-type ;
    ///
    /// block-argument-list
    ///     : block-argument (',' block-argument)* ;
    ///
    /// block-argument
    ///     : (argument-label identifier? ':') arg-attribute-list? 'inout'? swift-type ;
    ///
    /// argument-label
    ///     : '_'
    ///     | identifier
    ///     ;
    ///
    /// arg-attribute-list
    ///     : attribute+
    ///     ;
    ///
    /// arg-attribute
    ///     : '@' identifier
    ///     ;
    /// ```
    private static func parseTupleOrBlock(_ lexer: TokenizerLexer<SwiftTypeToken>) throws -> SwiftType {
        func verifyAndSkipAnnotations() throws {
            guard lexer.consumeToken(ifTypeIs: .at) != nil else {
                return
            }
            
            try lexer.advance(over: .identifier)
            
            if lexer.lexer.safeIsNextChar(equalTo: "(") && lexer.consumeToken(ifTypeIs: .openParens) != nil {
                while !lexer.isEof && !lexer.tokenType(is: .closeParens) {
                    try lexer.advance(over: lexer.token().tokenType)
                }
                
                try lexer.advance(over: .closeParens)
            }
            
            // Check for another attribute
            try verifyAndSkipAnnotations()
        }
        
        var returnType: SwiftType
        var parameters: [SwiftType] = []
        
        try lexer.advance(over: .openParens)
        
        var expectsBlock = false
        
        var afterComma = false
        while !lexer.tokenType(is: .closeParens) {
            afterComma = false
            
            // Inout label
            var expectsType = false
            
            if lexer.consumeToken(ifTypeIs: .inout) != nil {
                expectsType = true
            }
            
            if lexer.tokenType(is: .at) {
                expectsType = true
                try verifyAndSkipAnnotations()
            }
            
            // If we see an 'inout', skip identifiers and force a parameter type
            // to be read
            if !expectsType {
                // Check if we're handling a label
                let hasSingleLabel: Bool = lexer.backtracking {
                    return (lexer.consumeToken(ifTypeIs: .identifier) != nil && lexer.consumeToken(ifTypeIs: .colon) != nil)
                }
                let hasDoubleLabel: Bool = lexer.backtracking {
                    return (lexer.consumeToken(ifTypeIs: .identifier) != nil && lexer.consumeToken(ifTypeIs: .identifier) != nil && lexer.consumeToken(ifTypeIs: .colon) != nil)
                }
                
                if hasSingleLabel {
                    lexer.consumeToken(ifTypeIs: .identifier)
                    lexer.consumeToken(ifTypeIs: .colon)
                } else if hasDoubleLabel {
                    lexer.consumeToken(ifTypeIs: .identifier)
                    lexer.consumeToken(ifTypeIs: .identifier)
                    lexer.consumeToken(ifTypeIs: .colon)
                }
            }
            
            // Attributes
            if lexer.tokenType(is: .at) {
                if expectsType {
                    throw unexpectedTokenError(lexer: lexer)
                }
                
                try verifyAndSkipAnnotations()
            }
            
            // Inout label
            if lexer.consumeToken(ifTypeIs: .inout) != nil {
                if expectsType {
                    throw unexpectedTokenError(lexer: lexer)
                }
            }
            
            let type = try parseType(lexer)
            
            // Verify ellipsis for variadic parameter
            if lexer.consumeToken(ifTypeIs: .ellipsis) != nil {
                parameters.append(.array(type))
                
                expectsBlock = true
                break
            }
            
            parameters.append(type)
            
            if lexer.consumeToken(ifTypeIs: .comma) != nil {
                afterComma = true
            } else if !lexer.tokenType(is: .closeParens) {
                throw unexpectedTokenError(lexer: lexer)
            }
        }
        
        if afterComma {
            throw expectedTypeNameError(lexer: lexer)
        }
        
        try lexer.advance(over: .closeParens)
        
        // It's a block if if features a function arrow afterwards...
        if lexer.consumeToken(ifTypeIs: .functionArrow) != nil {
            returnType = try parseType(lexer)
            
            return .block(returnType: returnType, parameters: parameters)
        } else if expectsBlock {
            throw expectedBlockType(lexer: lexer)
        }
        
        // ...otherwise it is a tuple
        
        // Check for protocol compositions (types must be all nominal)
        if lexer.tokenType(is: .ampersand) {
            if parameters.count != 1 {
                throw unexpectedTokenError(lexer: lexer)
            }
            
            switch parameters[0] {
            case .nominal(let nominal):
                let prot =
                    try verifyProtocolCompositionTrailing(after: [.nominal(nominal)],
                                                          lexer: lexer)
                
                return .protocolComposition(prot)
                
            case .nested(let nested):
                let prot =
                    try verifyProtocolCompositionTrailing(after: [.nested(nested)],
                                                          lexer: lexer)
                
                return .protocolComposition(prot)
                
            case .protocolComposition(let composition):
                let prot =
                    try verifyProtocolCompositionTrailing(after: Array(composition),
                                                          lexer: lexer)
                
                return .protocolComposition(prot)
                
            default:
                throw notProtocolComposableError(type: parameters[0], lexer: lexer)
            }
        }
        
        if parameters.isEmpty {
            return .tuple(.empty)
        }
        
        if parameters.count == 1 {
            return parameters[0]
        }
        
        return .tuple(TupleSwiftType.types(.fromCollection(parameters)))
    }
    
    private static func verifyTrailing(after type: SwiftType, lexer: TokenizerLexer<SwiftTypeToken>) throws -> SwiftType {
        // Meta-type
        if lexer.consumeToken(ifTypeIs: .period) != nil {
            guard let ident = lexer.consumeToken(ifTypeIs: .identifier)?.value else {
                throw unexpectedTokenError(lexer: lexer)
            }
            if ident != "Type" && ident != "Protocol" {
                throw expectedMetatypeError(lexer: lexer)
            }
            
            return try verifyTrailing(after: .metatype(for: type), lexer: lexer)
        }
        
        // Optional
        if lexer.consumeToken(ifTypeIs: .questionMark) != nil {
            return try verifyTrailing(after: .optional(type), lexer: lexer)
        }
        
        // Implicitly unwrapped optional
        if lexer.consumeToken(ifTypeIs: .exclamationMark) != nil {
            return try verifyTrailing(after: .implicitUnwrappedOptional(type), lexer: lexer)
        }
        
        return type
    }
    
    private static func expectedMetatypeError(lexer: TokenizerLexer<SwiftTypeToken>) -> Error {
        let index = indexOn(lexer: lexer)
        return .expectedMetatype(index)
    }
    
    private static func expectedBlockType(lexer: TokenizerLexer<SwiftTypeToken>) -> Error {
        let index = indexOn(lexer: lexer)
        return .expectedBlockType(index)
    }
    
    private static func expectedTypeNameError(lexer: TokenizerLexer<SwiftTypeToken>) -> Error {
        let index = indexOn(lexer: lexer)
        return .expectedTypeName(index)
    }
    
    private static func unexpectedTokenError(lexer: TokenizerLexer<SwiftTypeToken>) -> Error {
        let index = indexOn(lexer: lexer)
        return .unexpectedToken(lexer.token().tokenType, index)
    }
    
    private static func notProtocolComposableError(
        type: SwiftType, lexer: TokenizerLexer<SwiftTypeToken>) -> Error {
        
        let index = indexOn(lexer: lexer)
        return .notProtocolComposable(type, index)
    }
    
    private static func indexOn(lexer: TokenizerLexer<SwiftTypeToken>) -> Int {
        let input = lexer.lexer.inputString
        return input.distance(from: input.startIndex, to: lexer.lexer.inputIndex)
    }
    
    public enum Error: Swift.Error, CustomStringConvertible {
        case invalidType
        case expectedTypeName(Int)
        case expectedMetatype(Int)
        case expectedBlockType(Int)
        case notProtocolComposable(SwiftType, Int)
        case unexpectedToken(SwiftTypeToken, Int)
        
        public var description: String {
            switch self {
            case .invalidType:
                return "Invalid Swift type signature"
            case .expectedTypeName(let offset):
                return "Expected type name at column \(offset + 1)"
            case .expectedBlockType(let offset):
                return "Expected block type at column \(offset + 1)"
            case .expectedMetatype(let offset):
                return "Expected .Type or .Protocol metatype at column \(offset + 1)"
            case let .notProtocolComposable(type, offset):
                return "Found protocol composition, but type \(type) is not composable on composition '&' at column \(offset + 1)"
            case let .unexpectedToken(token, offset):
                return "Unexpected token '\(token.tokenString)' at column \(offset + 1)"
            }
        }
    }
}

public enum SwiftTypeToken: String, TokenProtocol {
    private static let identifierLexer = (.letter | "_") + (.letter | "_" | .digit)*
    
    public static var eofToken: SwiftTypeToken = .eof
    
    /// Character '('
    case openParens = "("
    /// Character ')'
    case closeParens = ")"
    /// Character '.'
    case period = "."
    /// Character sequence '...' (three consecutive periods)
    case ellipsis = "..."
    /// Function arrow chars '->'
    case functionArrow = "->"
    /// An identifier token
    case identifier = "identifier"
    /// An 'inout' keyword
    case `inout` = "inout"
    /// Character '?'
    case questionMark = "?"
    /// Character '!'
    case exclamationMark = "!"
    /// Character ':'
    case colon = ":"
    /// Character '&'
    case ampersand = "&"
    /// Character '['
    case openBrace = "["
    /// Character ']'
    case closeBrace = "]"
    /// Character '<'
    case openBracket = "<"
    /// Character '>'
    case closeBracket = ">"
    /// Character '@'
    case at = "@"
    /// Character ','
    case comma = ","
    /// End-of-file character
    case eof = ""
    
    public var tokenString: String {
        return rawValue
    }
    
    public func length(in lexer: Lexer) -> Int {
        switch self {
        case .openParens, .closeParens, .period, .questionMark, .exclamationMark,
             .colon, .ampersand, .openBrace, .closeBrace, .openBracket,
             .closeBracket, .comma, .at:
            return 1
        case .functionArrow:
            return 2
        case .ellipsis:
            return 3
        case .inout:
            return "inout".count
        case .identifier:
            return SwiftTypeToken.identifierLexer.maximumLength(in: lexer) ?? 0
        case .eof:
            return 0
        }
    }
    
    public func advance(in lexer: Lexer) throws {
        let l = length(in: lexer)
        if l == 0 {
            return
        }
        
        try lexer.advanceLength(l)
    }
    
    public func matchesText(in lexer: Lexer) -> Bool {
        return lexer.checkNext(matches: tokenString)
    }
    
    public static func tokenType(at lexer: Lexer) -> SwiftTypeToken? {
        do {
            let next = try lexer.peek()
            
            // Single character tokens
            switch next {
            case "(":
                return .openParens
            case ")":
                return .closeParens
            case ".":
                if lexer.checkNext(matches: "...") {
                    return .ellipsis
                }
                
                return .period
            case "?":
                return .questionMark
            case "!":
                return .exclamationMark
            case ":":
                return .colon
            case "&":
                return .ampersand
            case "[":
                return .openBrace
            case "]":
                return .closeBrace
            case "<":
                return .openBracket
            case ">":
                return .closeBracket
            case "@":
                return .at
            case ",":
                return .comma
            case "-":
                if try lexer.peekForward() == ">" {
                    try lexer.advanceLength(2)
                    
                    return .functionArrow
                }
            default:
                break
            }
            
            // Identifier
            if identifierLexer.passes(in: lexer) {
                // Check it's not actually an `inout` keyword
                let ident = try lexer.withTemporaryIndex { try identifierLexer.consume(from: lexer) }
                
                if ident == "inout" {
                    return .inout
                } else {
                    return .identifier
                }
            }
            
            return nil
        } catch {
            return nil
        }
    }
}
