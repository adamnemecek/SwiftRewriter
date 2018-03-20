import SwiftAST

/// A function signature transformer allows changing the shape of a postfix function
/// call into equivalent calls with function name and parameters moved around,
/// labeled and transformed properly.
///
/// e.g:
///
/// ```
/// FunctionInvocationTransformer(
///     objcFunctionName: "CGPointMake",
///     toSwiftFunction: "CGPoint",
///     firstArgumentBecomesInstance: false,
///     arguments: [
///         .labeled("x", .asIs),
///         .labeled("y", .asIs)
///     ])
/// ```
///
/// Would allow matching and converting:
/// ```
/// CGPointMake(<x>, <y>)
/// // becomes
/// CGPoint(x: <x>, y: <y>)
/// ```
///
/// The method also allows taking in two arguments and merging them, as well as
/// moving arguments around:
/// ```
/// FunctionInvocationTransformer(
///     objcFunctionName: "CGPathMoveToPoint",
///     toSwiftFunction: "move",
///     firstArgumentBecomesInstance: true,
///     arguments: [
///         .labeled("to",
///                  .mergingArguments(arg0: 1, arg1: 2, { x, y in
///                                       Expression.identifier("CGPoint")
///                                       .call([.labeled("x", x), .labeled("y", y)])
///                                    }))
///     ])
/// ```
///
/// Would allow detecting and converting:
///
/// ```
/// CGPathMoveToPoint(<path>, <transform>, <x>, <y>)
/// // becomes
/// <path>.move(to: CGPoint(x: <x>, y: <y>))
/// ```
///
/// Note that the `<transform>` parameter from the original call was discarded:
/// it is not neccessary to map all arguments of the original call into the target
/// call.
public final class FunctionInvocationTransformer {
    public let objcFunctionName: String
    public let destinationMember: Target
    
    /// The number of arguments this function signature transformer needs, exactly,
    /// in order to be fulfilled.
    public let requiredArgumentCount: Int
    
    
    public init(fromObjcFunctionName: String, destinationMember: Target) {
        self.objcFunctionName = fromObjcFunctionName
        self.destinationMember = destinationMember
        
        switch destinationMember {
        case let .method(_, firstArgumentBecomesInstance, arguments):
            requiredArgumentCount =
                arguments.requiredArgumentCount() + (firstArgumentBecomesInstance ? 1 : 0)
        case .propertyGetter:
            requiredArgumentCount = 1
        case .propertySetter:
            requiredArgumentCount = 2
        }
    }
    
    /// Initializes a new function transformer instance.
    ///
    /// - Parameters:
    ///   - objcFunctionName: Name of free function to match with this converter.
    ///   - swiftName: Name of resulting swift function to transform matching
    /// free-function calls into.
    ///   - firstArgumentBecomesInstance: Whether to convert the first argument
    /// of the call into a target instance, such that the free function call becomes
    /// a method call.
    ///   - arguments: Strategy to apply to each argument in the call.
    public convenience init(objcFunctionName: String,
                            toSwiftFunction swiftName: String,
                            firstArgumentBecomesInstance: Bool,
                            arguments: [ArgumentStrategy]) {
        
        self.init(fromObjcFunctionName: objcFunctionName,
                  destinationMember: .method(swiftName,
                                             firstArgumentBecomesInstance: firstArgumentBecomesInstance,
                                             arguments))
    }
    
    /// Initializes a new function transformer instance that can modify Foundation
    /// style getter global functions into property getters.
    ///
    /// - Parameters:
    ///   - objcFunctionName: The function name to look for to transform.
    ///   - swiftProperty: The target swift property name to transform the getter
    /// into.
    public convenience init(objcFunctionName: String,
                            toSwiftPropertyGetter swiftProperty: String) {
        
        self.init(fromObjcFunctionName: objcFunctionName,
                  destinationMember: .propertyGetter(swiftProperty))
    }
    
    /// Initializes a new function transformer instance that can modify Foundation
    /// style setter global functions into property assignments.
    ///
    /// - Parameters:
    ///   - objcFunctionName: The function name to look for to transform.
    ///   - swiftProperty: The target swift property name to transform the setter
    /// into.
    public convenience init(objcFunctionName: String,
                            toSwiftPropertySetter swiftProperty: String) {
        
        self.init(fromObjcFunctionName: objcFunctionName,
                  destinationMember: .propertySetter(swiftProperty))
    }
    
    public func canApply(to postfix: PostfixExpression) -> Bool {
        guard postfix.exp.asIdentifier?.identifier == objcFunctionName else {
            return false
        }
        guard let functionCall = postfix.functionCall else {
            return false
        }
        
        if functionCall.arguments.count != requiredArgumentCount {
            return false
        }
        
        return true
    }
    
    public func attemptApply(on postfix: PostfixExpression) -> Expression? {
        guard postfix.exp.asIdentifier?.identifier == objcFunctionName else {
            return nil
        }
        guard let functionCall = postfix.functionCall else {
            return nil
        }
        guard !functionCall.arguments.isEmpty else {
            return nil
        }
        
        switch destinationMember {
        case .propertyGetter(let name):
            if functionCall.arguments.count != 1 {
                return nil
            }
            
            return functionCall.arguments[0].expression.dot(name).typed(postfix.resolvedType)
            
        case .propertySetter(let name):
            if functionCall.arguments.count != 2 {
                return nil
            }
            
            let exp = functionCall.arguments[0].expression.dot(name)
            exp.resolvedType = postfix.resolvedType
            
            return exp.assignment(op: .assign, rhs: functionCall.arguments[1].expression)
            
        case let .method(name, firstArgIsInstance, args):
            guard let result = attemptApply(on: functionCall, name: name,
                                            firstArgIsInstance: firstArgIsInstance,
                                            args: args) else {
                return nil
            }
            
            // Construct a new postfix operation with the function's first
            // argument
            if firstArgIsInstance {
                let exp =
                    functionCall.arguments[0]
                        .expression.dot(name).call(result.arguments)
                exp.resolvedType = postfix.resolvedType
                
                return exp
            }
            
            let exp = Expression.identifier(destinationMember.memberName).call(result.arguments)
            exp.resolvedType = postfix.resolvedType
            
            return exp
        }
    }
    
    public func attemptApply(on functionCall: FunctionCallPostfix,
                             name: String, firstArgIsInstance: Bool,
                             args: [ArgumentStrategy]) -> FunctionCallPostfix? {
        if functionCall.arguments.count != requiredArgumentCount {
            return nil
        }
        
        var arguments = firstArgIsInstance
            ? Array(functionCall.arguments.dropFirst())
            : functionCall.arguments
        
        var result: [FunctionArgument] = []
        
        func handleArg(i: Int, argument: ArgumentStrategy) -> FunctionArgument? {
            switch argument {
            case .asIs:
                return arguments[i]
            case let .mergingArguments(arg0, arg1, merger):
                let arg =
                    FunctionArgument(
                        label: nil,
                        expression: merger(arguments[arg0].expression,
                                           arguments[arg1].expression)
                )
                
                return arg
                
            case let .fixed(maker):
                return FunctionArgument(label: nil, expression: maker())
                
            case let .transformed(transform, strat):
                if var arg = handleArg(i: i, argument: strat) {
                    arg.expression = transform(arg.expression)
                    return arg
                }
                
                return nil
                
            case .fromArgIndex(let index):
                return arguments[index]
                
            case let .omitIf(matches: exp, strat):
                guard let result = handleArg(i: i, argument: strat) else {
                    return nil
                }
                
                if result.expression == exp {
                    return nil
                }
                
                return result
            case let .labeled(label, strat):
                if let arg = handleArg(i: i, argument: strat) {
                    return .labeled(label, arg.expression)
                }
                
                return nil
            }
        }
        
        var i = 0
        while i < args.count {
            let arg = args[i]
            if let res = handleArg(i: i, argument: arg) {
                result.append(res)
                
                if case .mergingArguments = arg {
                    i += 1
                }
            }
            
            i += 1
        }
        
        return FunctionCallPostfix(arguments: result)
    }
    
    /// What to do with one or more arguments of a function call
    public enum ArgumentStrategy {
        /// Maps the target argument from the original argument at the nth index
        /// on the original call.
        case fromArgIndex(Int)
        
        /// Maps the current argument as-is, with no changes.
        case asIs
        
        /// Merges two argument indices into a single expression, using a given
        /// transformation closure.
        case mergingArguments(arg0: Int, arg1: Int, (Expression, Expression) -> Expression)
        
        /// Puts out a fixed expression at the target argument position
        case fixed(() -> Expression)
        
        /// Transforms an argument using a given transformation method
        indirect case transformed((Expression) -> Expression, ArgumentStrategy)
        
        /// Creates a rule that omits the argument in case it matches a given
        /// expression.
        indirect case omitIf(matches: Expression, ArgumentStrategy)
        
        /// Allows adding a label to the result of an argument strategy for the
        /// current parameter.
        indirect case labeled(String, ArgumentStrategy)
        
        /// Gets the number of arguments this argument strategy will consume when
        /// applied.
        var argumentConsumeCount: Int {
            switch self {
            case .fixed:
                return 0
            case .asIs, .fromArgIndex:
                return 1
            case .mergingArguments:
                return 2
            case .labeled(_, let inner), .omitIf(_, let inner), .transformed(_, let inner):
                return inner.argumentConsumeCount
            }
        }
        
        /// Gets the index of the maximal argument index referenced by this argument
        /// rule.
        /// Returns 0, for non-indexed arguments.
        var maxArgumentReferenced: Int {
            switch self {
            case .asIs, .fixed:
                return 0
            case .fromArgIndex(let index):
                return index
            case let .mergingArguments(index1, index2, _):
                return max(index1, index2)
            case .labeled(_, let inner), .omitIf(_, let inner), .transformed(_, let inner):
                return inner.maxArgumentReferenced
            }
        }
    }
    
    public enum Target {
        case propertyGetter(String)
        
        case propertySetter(String)
        
        ///   - firstArgumentBecomesInstance: Whether to convert the first argument
        /// of the call into a target instance, such that the free function call becomes
        /// a method call.
        ///   - arguments: Strategy to apply to each argument in the call.
        case method(String, firstArgumentBecomesInstance: Bool, [FunctionInvocationTransformer.ArgumentStrategy])
        
        public var memberName: String {
            switch self {
            case .propertyGetter(let name), .propertySetter(let name),
                 .method(let name, _, _):
                return name
            }
        }
    }
}

public extension Sequence where Element == FunctionInvocationTransformer.ArgumentStrategy {
    public func requiredArgumentCount() -> Int {
        var requiredArgs = reduce(0) { $0 + $1.argumentConsumeCount }
        
        // Verify max arg count inferred from indexes of arguments
        if let max = map({ $0.maxArgumentReferenced }).max(), max > requiredArgs {
            requiredArgs = max
        }
        
        return requiredArgs
    }
}
