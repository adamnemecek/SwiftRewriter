/// Specifies an objetive-c type for a property or local.
/// For objc class pointers, they are always specified as pointers to structs,
/// like `.pointerType(.structType("NSObject"))`
public enum ObjcType: Equatable, CustomStringConvertible {
    /// Objective-c's `id` type, with optional protocol array specifiers
    case id(protocols: [String])
    
    /// Special 'generic'-like specifier.
    /// Closely related to `id` type.
    case instancetype
    
    /// A struct-type.
    /// May be any type that is not an `id`.
    case `struct`(String)
    
    /// A special `void` type that indicates an empty value.
    case void
    
    /// A composed pointer, like `NSObject*` or `int*`.
    /// May be an objc class or a struct-type pointer.
    indirect case pointer(ObjcType)
    
    /// A generic objc type- e.g. `NSArray<NSNumber*>`
    indirect case generic(String, parameters: [ObjcType])
    
    /// An Objc type that has associated pointer qualifiers, such as `NSObject *_Nonnull`,
    /// which is a pointer to a struct NSObject with _Nonnull qualifier.
    indirect case qualified(ObjcType, qualifiers: [String])
    
    /// An Objc type that has associated specifiers, such as `__weak NSObject*`,
    /// which is a __weak-tagged type of a pointer to a struct NSObject.
    indirect case specified(specifiers: [String], ObjcType)
    
    /// An objective-C block type.
    /// Block types may specify names, or not (in case of block literals).
    indirect case blockType(name: String?, returnType: ObjcType, parameters: [ObjcType])
    
    /// A C function pointer.
    /// Function pointer types may specify names, or not (in case of pointer literals).
    indirect case functionPointer(name: String?, returnType: ObjcType, parameters: [ObjcType])
    
    /// A fixed array type
    indirect case fixedArray(ObjcType, length: Int)
    
    /// Gets the plain string definition for this type.
    /// Always maps to valid objc type
    public var description: String {
        switch self {
        case .instancetype:
            return "instancetype"
            
        case .void:
            return "void"
            
        case .struct(let s):
            return s
            
        case let .generic(cl, parameters):
            let typeNames = parameters.map { $0.description }.joined(separator: ", ")
            
            if !typeNames.isEmpty {
                return "\(cl)<\(typeNames)>"
            } else {
                return cl
            }
            
        case .id(let protocols):
            if !protocols.isEmpty {
                let protocolNames = protocols.joined(separator: ", ")
                return "id<\(protocolNames)>"
            } else {
                return "id"
            }
            
        case .pointer(let type):
            return "\(type.description)*"
            
        case let .qualified(type, qualifiers):
            return "\(type.description) \(qualifiers.joined(separator: " "))"
            
        case let .specified(specifiers, type):
            return "\(specifiers.joined(separator: " ")) \(type.description)"
            
        case let .blockType(name, returnType, parameters):
            return "\(returnType)(^\(name ?? ""))(\(parameters.map { $0.description }.joined(separator: ", ")))"
            
        case let .functionPointer(name, returnType, parameters):
            return "\(returnType)(*\(name ?? ""))(\(parameters.map { $0.description }.joined(separator: ", ")))"
            
        case let .fixedArray(type, length):
            return "\(type)[\(length)]"
        }
    }
    
    /// Returns a normalized type for this type.
    /// Normalizes qualified types with empty qualifiers to their base type.
    public var normalized: ObjcType {
        switch self {
        case let .pointer(ptr):
            return .pointer(ptr.normalized)
            
        case let .generic(type, parameters) where parameters.isEmpty:
            return .struct(type)
            
        case let .generic(type, parameters):
            return .generic(type, parameters: parameters.map { $0.normalized })
            
        case let .qualified(type, qualifiers) where qualifiers.isEmpty:
            return type.normalized
            
        case let .specified(specifiers, type) where specifiers.isEmpty:
            return type.normalized
            
        // Nested specified and qualified types can be unwrapped into one single
        // qualified/specified type with all annotations in a row
        case let .qualified(.qualified(innerType, innerQualifiers), qualifiers):
            return .qualified(innerType.normalized, qualifiers: qualifiers + innerQualifiers)
            
        case let .specified(specifiers, .specified(innerSpecifiers, innerType)):
            return .specified(specifiers: specifiers + innerSpecifiers, innerType.normalized)
            
        case let .blockType(name, returnType, parameters):
            return .blockType(name: name,
                              returnType: returnType.normalized,
                              parameters: parameters.map { $0.normalized })
            
        case let .functionPointer(name, returnType, parameters):
            return .functionPointer(name: name,
                                    returnType: returnType.normalized,
                                    parameters: parameters.map { $0.normalized })
            
        case let .fixedArray(inner, length):
            return .fixedArray(inner.normalized, length: length)
            
        default:
            return self
        }
    }
    
    /// Returns true if this is a pointer type
    public var isPointer: Bool {
        switch self {
        case .pointer, .id, .instancetype, .blockType, .functionPointer, .fixedArray:
            return true
            
        case .specified(_, let type):
            return type.isPointer
            
        case .qualified(let type, _):
            return type.isPointer
            
        default:
            return false
        }
    }
}
