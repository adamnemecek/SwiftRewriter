import GrammarModels

/// Intention to generate a type initializer for a class or protocol initializer
public class InitGenerationIntention: MemberGenerationIntention, FunctionIntention {
    public var parameters: [ParameterSignature]
    
    public var functionBody: FunctionBodyIntention?
    
    public var isOverride: Bool = false
    public var isFailable: Bool = false
    public var isConvenience: Bool = false
    
    public init(parameters: [ParameterSignature],
                accessLevel: AccessLevel = .internal,
                source: ASTNode? = nil) {
        
        self.parameters = parameters
        super.init(accessLevel: accessLevel, source: source)
    }
}

extension InitGenerationIntention: OverridableMemberGenerationIntention {
    
}

extension InitGenerationIntention: KnownConstructor {
    
}
