import GrammarModels
import Antlr4
import ObjcParserAntlr

internal class ObjcParserListener: ObjectiveCParserBaseListener {
    let context: NodeCreationContext
    let rootNode: GlobalContextNode
    let typeParser: TypeParsing
    private var nonnullContextQuerier: NonnullContextQuerier
    private let mapper: GenericParseTreeContextMapper
    private let sourceString: String
    private let source: Source
    private let nodeFactory: ASTNodeFactory
    
    /// Whether the listener is currently visiting a @protocol section that was
    /// marked @optional.
    private var inOptionalContext: Bool = false
    
    init(sourceString: String,
         source: Source,
         state: ObjcParserState,
         antlrSettings: AntlrSettings,
         nonnullContextQuerier: NonnullContextQuerier) {
        
        self.sourceString = sourceString
        self.source = source
        self.nonnullContextQuerier = nonnullContextQuerier
        self.nodeFactory =
            ASTNodeFactory(source: source,
                           nonnullContextQuerier: nonnullContextQuerier)
        
        typeParser = TypeParsing(state: state, antlrSettings: antlrSettings)
        context = NodeCreationContext()
        rootNode = GlobalContextNode(isInNonnullContext: false)
        mapper = GenericParseTreeContextMapper(source: source,
                                               nonnullContextQuerier: nonnullContextQuerier)
        
        super.init()
        
        configureMappers()
    }
    
    private func sourceLocation(for rule: ParserRuleContext) -> SourceLocation {
        let startIndex = rule.start?.getStartIndex() ?? 0
        let endIndex = rule.stop?.getStopIndex() ?? 0
        
        let line = rule.start?.getLine() ?? 0
        let column = (rule.start?.getCharPositionInLine()).map { $0 + 1 } ?? 0
        
        return
            SourceLocation(source: source,
                           intRange: startIndex..<endIndex,
                           line: line,
                           column: column)
    }
    
    /// Configures mappers in `self.mapper` so they are automatically pushed and
    /// popped whenever the rules are entered and exited during visit.
    ///
    /// Used as a convenience over manually pushing and popping contexts every
    /// time a node of significance is entered.
    private func configureMappers() {
        mapper.addRuleMap(rule: ObjectiveCParser.TranslationUnitContext.self, node: rootNode)
        mapper.addRuleMap(rule: ObjectiveCParser.ClassInterfaceContext.self, nodeType: ObjcClassInterface.self)
        mapper.addRuleMap(
            rule: ObjectiveCParser.ClassImplementationContext.self, nodeType: ObjcClassImplementation.self)
        mapper.addRuleMap(
            rule: ObjectiveCParser.CategoryInterfaceContext.self, nodeType: ObjcClassCategoryInterface.self)
        mapper.addRuleMap(
            rule: ObjectiveCParser.CategoryImplementationContext.self, nodeType: ObjcClassCategoryImplementation.self)
        mapper.addRuleMap(rule: ObjectiveCParser.MethodDeclarationContext.self, nodeType: MethodDefinition.self)
        mapper.addRuleMap(rule: ObjectiveCParser.MethodDefinitionContext.self, nodeType: MethodDefinition.self)
        mapper.addRuleMap(rule: ObjectiveCParser.KeywordDeclaratorContext.self, nodeType: KeywordDeclarator.self)
        mapper.addRuleMap(rule: ObjectiveCParser.MethodSelectorContext.self, nodeType: MethodSelector.self)
        mapper.addRuleMap(rule: ObjectiveCParser.MethodTypeContext.self, nodeType: MethodType.self)
        mapper.addRuleMap(rule: ObjectiveCParser.InstanceVariablesContext.self, nodeType: IVarsList.self)
        mapper.addRuleMap(rule: ObjectiveCParser.TypedefDeclarationContext.self, nodeType: TypedefNode.self)
        mapper.addRuleMap(rule: ObjectiveCParser.BlockParametersContext.self, nodeType: BlockParametersNode.self)
        mapper.addRuleMap(rule: ObjectiveCParser.ProtocolDeclarationContext.self, nodeType: ProtocolDeclaration.self)
        mapper.addRuleMap(rule: ObjectiveCParser.EnumDeclarationContext.self, nodeType: ObjcEnumDeclaration.self)
        mapper.addRuleMap(rule: ObjectiveCParser.FunctionDeclarationContext.self, nodeType: FunctionDefinition.self)
        mapper.addRuleMap(rule: ObjectiveCParser.FunctionDefinitionContext.self, nodeType: FunctionDefinition.self)
        mapper.addRuleMap(
            rule: ObjectiveCParser.PropertyImplementationContext.self, nodeType: PropertyImplementation.self)
        mapper.addRuleMap(
            rule: ObjectiveCParser.PropertySynthesizeListContext.self, nodeType: PropertySynthesizeList.self)
        mapper.addRuleMap(
            rule: ObjectiveCParser.PropertySynthesizeItemContext.self, nodeType: PropertySynthesizeItem.self)
    }
    
    override func enterEveryRule(_ ctx: ParserRuleContext) {
        mapper.matchEnter(rule: ctx, context: context)
    }
    
    override func exitEveryRule(_ ctx: ParserRuleContext) {
        mapper.matchExit(rule: ctx, context: context)
    }
    
    // MARK: - Global Context
    override func enterTranslationUnit(_ ctx: ObjectiveCParser.TranslationUnitContext) {
        // Collect global variables
        let globalVariableListener =
            GlobalVariableListener(typeParser: typeParser,
                                   nonnullContextQuerier: nonnullContextQuerier,
                                   nodeFactory: nodeFactory)
        
        let walker = ParseTreeWalker()
        try? walker.walk(globalVariableListener, ctx)
        
        for global in globalVariableListener.declarations {
            context.addChildNode(global)
        }
    }
    
    // MARK: - Class Interface
    override func enterClassInterface(_ ctx: ObjectiveCParser.ClassInterfaceContext) {
        guard let classNode = context.currentContextNode(as: ObjcClassInterface.self) else {
            return
        }
        
        // Class name
        if let identifier = ctx.className()?.identifier() {
            let identifierNode = nodeFactory.makeIdentifier(from: identifier)
            classNode.addChild(identifierNode)
        }
        
        // Super class name
        if let sup = ctx.superclassName() {
            let supName = nodeFactory.makeSuperclassName(from: sup)
            context.addChildNode(supName)
        }
        
        // Protocol list
        if let protocolList = ctx.protocolList() {
            let protocolListNode =
                nodeFactory.makeProtocolReferenceList(from: protocolList)
            
            context.addChildNode(protocolListNode)
        }
    }
    
    // MARK: - Class Category
    override func enterCategoryInterface(_ ctx: ObjectiveCParser.CategoryInterfaceContext) {
        guard let classNode = context.currentContextNode(as: ObjcClassCategoryInterface.self) else {
            return
        }
        
        // Note: In the original Antlr's grammar, 'className' and 'categoryName'
        // seem to be switched around. We undo that here while parsing.
        
        if let className = ctx.categoryName?.identifier() {
            let identifierNode = nodeFactory.makeIdentifier(from: className)
            classNode.addChild(identifierNode)
        }
        
        // Class category name
        if let identifier = ctx.identifier() {
            let identifierNode = nodeFactory.makeIdentifier(from: identifier)
            classNode.addChild(identifierNode)
        }
        
        // Protocol list
        if let protocolList = ctx.protocolList() {
            let protocolListNode =
                nodeFactory.makeProtocolReferenceList(from: protocolList)
            
            context.addChildNode(protocolListNode)
        }
    }
    
    // MARK: - Class Implementation
    override func enterClassImplementation(_ ctx: ObjectiveCParser.ClassImplementationContext) {
        guard let classNode = context.currentContextNode(as: ObjcClassImplementation.self) else {
            return
        }
        
        // Class name
        if let identifier = ctx.className()?.identifier() {
            let identNode = nodeFactory.makeIdentifier(from: identifier)
            classNode.addChild(identNode)
        }
        
        // Super class name
        if let sup = ctx.superclassName() {
            let supName = nodeFactory.makeSuperclassName(from: sup)
            context.addChildNode(supName)
        }
    }
    
    override func enterCategoryImplementation(_ ctx: ObjectiveCParser.CategoryImplementationContext) {
        guard let classNode = context.currentContextNode(as: ObjcClassCategoryImplementation.self) else {
            return
        }
        
        // Class name
        if let identifier = ctx.className()?.identifier() {
            let identNode = nodeFactory.makeIdentifier(from: identifier)
            classNode.addChild(identNode)
        }
        
        // Category name
        if let identifier = ctx.identifier() {
            let identNode = nodeFactory.makeIdentifier(from: identifier)
            classNode.addChild(identNode)
        }
    }
    
    // MARK: - Instance Variables
    override func enterVisibilitySection(_ ctx: ObjectiveCParser.VisibilitySectionContext) {
        if let accessModifier = ctx.accessModifier() {
            var accessNode: KeywordNode?
            let nonnull = isInNonnullContext(accessModifier)
            
            if accessModifier.PRIVATE() != nil {
                accessNode = KeywordNode(keyword: .atPrivate, isInNonnullContext: nonnull)
            } else if accessModifier.PACKAGE() != nil {
                accessNode = KeywordNode(keyword: .atPackage, isInNonnullContext: nonnull)
            } else if accessModifier.PROTECTED() != nil {
                accessNode = KeywordNode(keyword: .atProtected, isInNonnullContext: nonnull)
            } else if accessModifier.PUBLIC() != nil {
                accessNode = KeywordNode(keyword: .atPublic, isInNonnullContext: nonnull)
            }
            
            if let accessNode = accessNode {
                context.addChildNode(accessNode)
            }
        }
        
        let declarations = ctx.fieldDeclaration()
        
        for decl in declarations {
            guard let specifierQualifierList = decl.specifierQualifierList() else {
                continue
            }
            guard let fieldDeclarators = decl.fieldDeclaratorList()?.fieldDeclarator() else {
                continue
            }
            
            for fieldDeclarator in fieldDeclarators {
                guard let declarator = fieldDeclarator.declarator() else {
                    continue
                }
                guard let identifier = VarDeclarationIdentifierNameExtractor.extract(from: declarator) else {
                    continue
                }
                guard let type = typeParser.parseObjcType(inSpecifierQualifierList: specifierQualifierList,
                                                          declarator: declarator) else {
                    continue
                }
                
                let nonnull = isInNonnullContext(fieldDeclarator)
                
                let typeNode = TypeNameNode(type: type, isInNonnullContext: nonnull)
                let ident = nodeFactory.makeIdentifier(from: identifier)
                typeNode.location = sourceLocation(for: fieldDeclarator)
                
                let ivar = IVarDeclaration(isInNonnullContext: nonnull)
                ivar.addChild(typeNode)
                ivar.addChild(ident)
                ivar.updateSourceRange()
                
                context.addChildNode(ivar)
            }
        }
    }
    
    // MARK: - Protocol Declaration
    override func enterProtocolDeclaration(_ ctx: ObjectiveCParser.ProtocolDeclarationContext) {
        guard context.currentContextNode(as: ProtocolDeclaration.self) != nil else {
            return
        }
        
        if let identifier = ctx.protocolName()?.identifier() {
            let identifierNode = nodeFactory.makeIdentifier(from: identifier)
            context.addChildNode(identifierNode)
        }
        
        // Protocol list
        if let protocolList = ctx.protocolList() {
            let protocolListNode =
                nodeFactory.makeProtocolReferenceList(from: protocolList)
            
            context.addChildNode(protocolListNode)
        }
    }
    
    override func enterProtocolDeclarationSection(_ ctx: ObjectiveCParser.ProtocolDeclarationSectionContext) {
        inOptionalContext = ctx.OPTIONAL() != nil
    }
    
    override func exitProtocolDeclarationSection(_ ctx: ObjectiveCParser.ProtocolDeclarationSectionContext) {
        inOptionalContext = false
    }
    
    override func exitProtocolDeclaration(_ ctx: ObjectiveCParser.ProtocolDeclarationContext) {
        inOptionalContext = false
    }
    
    // MARK: - Property Declaration
    override func enterPropertyDeclaration(_ ctx: ObjectiveCParser.PropertyDeclarationContext) {
        let listener = PropertyListener(isInNonnullContext: isInNonnullContext(ctx),
                                        typeParser: typeParser,
                                        nonnullContextQuerier: nonnullContextQuerier,
                                        sourceLocation: sourceLocation)
        let walker = ParseTreeWalker()
        try? walker.walk(listener, ctx)
        
        listener.property.isOptionalProperty = inOptionalContext
        
        context.pushContext(node: listener.property)
    }
    
    override func exitPropertyDeclaration(_ ctx: ObjectiveCParser.PropertyDeclarationContext) {
        context.popContext()
    }
    
    override func enterTypeName(_ ctx: ObjectiveCParser.TypeNameContext) {
        guard let type = typeParser.parseObjcType(fromTypeName: ctx) else {
            return
        }
        
        let node = TypeNameNode(type: type, isInNonnullContext: isInNonnullContext(ctx))
        node.location = sourceLocation(for: ctx)
        context.addChildNode(node)
    }
    
    override func enterGenericTypeSpecifier(_ ctx: ObjectiveCParser.GenericTypeSpecifierContext) {
        mapper.pushTemporaryException(forRuleType: ObjectiveCParser.ProtocolListContext.self)
    }
    
    override func exitGenericTypeSpecifier(_ ctx: ObjectiveCParser.GenericTypeSpecifierContext) {
        mapper.popTemporaryException() // ObjectiveCParser.ProtocolListContext
    }
    
    override func enterNullabilitySpecifier(_ ctx: ObjectiveCParser.NullabilitySpecifierContext) {
        let spec = nodeFactory.makeNullabilitySpecifier(from: ctx)
        context.addChildNode(spec)
    }
    
    // MARM: - Property implementaiton
    override func exitPropertyImplementation(_ ctx: ObjectiveCParser.PropertyImplementationContext) {
        guard let node = context.currentContextNode(as: PropertyImplementation.self) else {
            return
        }
        guard let list = node.list else {
            return
        }
        
        for synth in list.synthesizations {
            synth.isDynamic = ctx.DYNAMIC() != nil
        }
    }
    
    override func enterPropertySynthesizeItem(_ ctx: ObjectiveCParser.PropertySynthesizeItemContext) {
        guard let node = context.currentContextNode(as: PropertySynthesizeItem.self) else {
            return
        }
        
        if let propIdentifier = ctx.identifier(0) {
            node.addChild(nodeFactory.makeIdentifier(from: propIdentifier))
        }
        if let ivarIdentifier = ctx.identifier(1) {
            node.addChild(nodeFactory.makeIdentifier(from: ivarIdentifier))
        }
    }
    
    // MARK: - Method Declaration
    override func enterMethodDeclaration(_ ctx: ObjectiveCParser.MethodDeclarationContext) {
        guard let node = context.currentContextNode(as: MethodDefinition.self) else {
            return
        }
        
        node.isOptionalMethod = inOptionalContext
        node.isClassMethod = ctx.parent is ObjectiveCParser.ClassMethodDeclarationContext
    }
    
    override func enterMethodDefinition(_ ctx: ObjectiveCParser.MethodDefinitionContext) {
        guard let node = context.currentContextNode(as: MethodDefinition.self) else {
            return
        }
        
        node.isClassMethod = ctx.parent is ObjectiveCParser.ClassMethodDefinitionContext
        
        let methodBody = nodeFactory.makeMethodBody(from: ctx)
        
        node.body = methodBody
    }
    
    override func enterMethodSelector(_ ctx: ObjectiveCParser.MethodSelectorContext) {
        if let selIdentifier = ctx.selector()?.identifier() {
            let node = nodeFactory.makeIdentifier(from: selIdentifier)
            context.addChildNode(node)
        }
    }
    
    override func enterKeywordDeclarator(_ ctx: ObjectiveCParser.KeywordDeclaratorContext) {
        guard let node = context.currentContextNode(as: KeywordDeclarator.self) else {
            return
        }
        
        let selectorIdent =
            (ctx.selector()?.identifier()).map(nodeFactory.makeIdentifier(from:))
        
        let ident =
            ctx.identifier().map(nodeFactory.makeIdentifier(from:))
        
        if let ident = selectorIdent {
            node.addChild(ident)
        }
        if let ident = ident {
            node.addChild(ident)
        }
    }
    
    // MARK: - Typedef
    
    override func enterTypedefDeclaration(_ ctx: ObjectiveCParser.TypedefDeclarationContext) {
        guard let typedefNode = context.currentContextNode(as: TypedefNode.self) else {
            return
        }
        
        if let functionPointer = ctx.functionPointer() {
            // TODO: FunctionPointerVisitor may be better off being a listener
            // instead of a visitor due to this awkward use case?
            let visitor =
                FunctionPointerVisitor(typedefNode: typedefNode,
                                       typeParser: typeParser,
                                       nonnullContextQuerier: nonnullContextQuerier,
                                       nodeFactory: nodeFactory)
            
            _=functionPointer.accept(visitor)
            
            return
        }
        
        guard let typeDeclaratorList = ctx.typeDeclaratorList() else {
            return
        }
        
        // Collect structs
        let listener = StructListener(typeParser: typeParser,
                                      nonnullContextQuerier: nonnullContextQuerier,
                                      nodeFactory: nodeFactory)
        let walker = ParseTreeWalker()
        try? walker.walk(listener, ctx)
        
        typedefNode.addChildren(listener.structs)
        
        for (i, typeDeclarator) in typeDeclaratorList.declarator().enumerated() {
            let declarator = nodeFactory.makeTypeDeclarator(from: typeDeclarator)
            
            // Tie first declarator to any pointer from the type specifier of the
            // struct declaration, recording it as a typealias to a pointer type.
            if i == 0, let pointer = ctx.declarationSpecifiers()?.typeSpecifier(0)?.pointer() {
                declarator.addChild(nodeFactory.makePointer(from: pointer))
            }
            
            typedefNode.addChild(declarator)
        }
    }
    
    override func exitTypedefDeclaration(_ ctx: ObjectiveCParser.TypedefDeclarationContext) {
        guard let typedefNode = context.currentContextNode(as: TypedefNode.self) else {
            return
        }
        
        guard let declarationSpecifiers = ctx.declarationSpecifiers() else {
            return
        }
        guard let typeDeclaratorList = ctx.typeDeclaratorList() else {
            return
        }
        
        // Detect block types
        for typeDeclarator in typeDeclaratorList.declarator() {
            guard let directDeclarator = typeDeclarator.directDeclarator() else {
                continue
            }
            guard let identifier = directDeclarator.identifier() else {
                continue
            }
            
            guard let type = typeParser.parseObjcType(inDeclarationSpecifiers: declarationSpecifiers,
                                                      declarator: typeDeclarator) else {
                continue
            }
            
            typedefNode.addChild(nodeFactory.makeIdentifier(from: identifier))
            
            let typeNameNode = TypeNameNode(type: type,
                                            isInNonnullContext: isInNonnullContext(ctx))
            typeNameNode.location = sourceLocation(for: typeDeclarator)
            typedefNode.addChild(typeNameNode)
        }
    }
    
    override func enterEnumDeclaration(_ ctx: ObjectiveCParser.EnumDeclarationContext) {
        guard let enumSpecifier = ctx.enumSpecifier() else {
            return
        }
        
        guard let enumNode = context.currentContextNode(as: ObjcEnumDeclaration.self) else {
            return
        }
        
        let isObjcEnum = enumSpecifier.NS_ENUM() != nil || enumSpecifier.NS_OPTIONS() != nil
        
        enumNode.isOptionSet = enumSpecifier.NS_OPTIONS() != nil
        
        if let identifier = enumSpecifier.identifier(isObjcEnum ? 0 : 1) {
            enumNode.addChild(nodeFactory.makeIdentifier(from: identifier))
        }
    }
    
    override func enterEnumerator(_ ctx: ObjectiveCParser.EnumeratorContext) {
        guard let identifier = ctx.enumeratorIdentifier()?.identifier() else {
            return
        }
        
        let enumCase = nodeFactory.makeEnumCase(from: ctx, identifier: identifier)
            
        context.addChildNode(enumCase)
    }
    
    override func enterBlockParameters(_ ctx: ObjectiveCParser.BlockParametersContext) {
        for typeVariableDeclaratorOrName in ctx.typeVariableDeclaratorOrName() {
            guard let type
                = typeParser.parseObjcType(fromTypeVariableDeclaratorOrTypeName: typeVariableDeclaratorOrName) else {
                continue
            }
            
            let typeNameNode =
                TypeNameNode(type: type,
                             isInNonnullContext: isInNonnullContext(typeVariableDeclaratorOrName))
            typeNameNode.location = sourceLocation(for: typeVariableDeclaratorOrName)
            
            context.addChildNode(typeNameNode)
        }
    }
    
    // MARK: - Function Declaration/Definition
    override func enterFunctionDefinition(_ ctx: ObjectiveCParser.FunctionDefinitionContext) {
        guard let function = context.currentContextNode(as: FunctionDefinition.self) else {
            return
        }
        guard let compoundStatement = ctx.compoundStatement() else {
            return
        }
        
        let body = nodeFactory.makeMethodBody(from: compoundStatement)
        
        function.addChild(body)
    }
    
    override func enterFunctionSignature(_ ctx: ObjectiveCParser.FunctionSignatureContext) {
        guard let function = context.currentContextNode(as: FunctionDefinition.self) else {
            return
        }
        
        if let declarationSpecifiers = ctx.declarationSpecifiers() {
            let returnType = typeParser.parseObjcType(inDeclarationSpecifiers: declarationSpecifiers)
            
            if let returnType = returnType {
                let typeNameNode =
                    TypeNameNode(type: returnType,
                                 isInNonnullContext: isInNonnullContext(declarationSpecifiers))
                typeNameNode.location = sourceLocation(for: declarationSpecifiers)
                function.addChild(typeNameNode)
            }
        }
        
        if let identifier = ctx.identifier() {
            function.addChild(nodeFactory.makeIdentifier(from: identifier))
        }
        
        // Parameter list
        let parameterListNode = context.pushContext(nodeType: ParameterList.self)
        defer {
            context.popContext()
        }
        
        if let params = ctx.parameterList(), let paramDecl = params.parameterDeclarationList() {
            for param in paramDecl.parameterDeclaration() {
                let node = context.pushContext(nodeType: FunctionParameter.self)
                defer {
                    context.popContext()
                }
                
                guard let declarationSpecifiers = param.declarationSpecifiers() else {
                    continue
                }
                guard let declarator = param.declarator() else {
                    continue
                }
                guard let identifier = VarDeclarationIdentifierNameExtractor.extract(from: declarator) else {
                    continue
                }
                guard let type = typeParser.parseObjcType(inDeclarationSpecifiers: declarationSpecifiers,
                                                          declarator: declarator) else {
                    continue
                }
                
                let identifierNode = nodeFactory.makeIdentifier(from: identifier)
                context.addChildNode(identifierNode)
                
                let typeNode = TypeNameNode(type: type,
                                            isInNonnullContext: isInNonnullContext(param))
                typeNode.location = sourceLocation(for: param)
                context.addChildNode(typeNode)
            }
            
            if params.ELIPSIS() != nil {
                let variadicParameter =
                    VariadicParameter(isInNonnullContext: isInNonnullContext(ctx))
                variadicParameter.location = sourceLocation(for: params)
                context.addChildNode(variadicParameter)
            }
        }
    }
    
    private func isInNonnullContext(_ rule: ParserRuleContext) -> Bool {
        return nonnullContextQuerier.isInNonnullContext(rule)
    }
}

private class GlobalVariableListener: ObjectiveCParserBaseListener {
    var declarations: [ASTNode] = []
    var typeParser: TypeParsing
    var nonnullContextQuerier: NonnullContextQuerier
    var nodeFactory: ASTNodeFactory
    
    init(typeParser: TypeParsing,
         nonnullContextQuerier: NonnullContextQuerier,
         nodeFactory: ASTNodeFactory) {
        
        self.typeParser = typeParser
        self.nonnullContextQuerier = nonnullContextQuerier
        self.nodeFactory = nodeFactory
    }
    
    // Pick global variable declarations on top level
    override func enterTranslationUnit(_ ctx: ObjectiveCParser.TranslationUnitContext) {
        let topLevelDeclarations = ctx.topLevelDeclaration()
        let visitor = GlobalVariableVisitor(typeParser: typeParser,
                                            nonnullContextQuerier: nonnullContextQuerier,
                                            nodeFactory: nodeFactory)
        
        for topLevelDeclaration in topLevelDeclarations {
            guard let declaration = topLevelDeclaration.declaration() else { continue }
            guard let varDeclaration = declaration.varDeclaration() else { continue }
            
            if let vars = varDeclaration.accept(visitor) {
                declarations.append(contentsOf: vars)
            }
        }
    }
    
    // Pick global variable declarations that are beneath the top-level, like inside
    // class @interface/@implementations etc.
    override func enterVarDeclaration(_ ctx: ObjectiveCParser.VarDeclarationContext) {
        if ctx.context.scope != .class || !ctx.context.isStatic {
            return
        }
        
        let visitor =
            GlobalVariableVisitor(typeParser: typeParser,
                                  nonnullContextQuerier: nonnullContextQuerier,
                                  nodeFactory: nodeFactory)
        
        if let vars = ctx.accept(visitor) {
            declarations.append(contentsOf: vars)
        }
    }
    
    private class GlobalVariableVisitor: ObjectiveCParserBaseVisitor<[ASTNode]> {
        var typeParser: TypeParsing
        var nonnullContextQuerier: NonnullContextQuerier
        var nodeFactory: ASTNodeFactory
        
        init(typeParser: TypeParsing,
             nonnullContextQuerier: NonnullContextQuerier,
             nodeFactory: ASTNodeFactory) {
            
            self.typeParser = typeParser
            self.nonnullContextQuerier = nonnullContextQuerier
            self.nodeFactory = nodeFactory
        }
        
        override func visitVarDeclaration(_ ctx: ObjectiveCParser.VarDeclarationContext) -> [ASTNode]? {
            var declarations: [ASTNode] = []
            
            // Free struct/union declarators
            if let typeSpecifiers = ctx.declarationSpecifiers()?.typeSpecifier() {
                for specifier in typeSpecifiers {
                    if let vars = specifier.accept(self) {
                        declarations.append(contentsOf: vars)
                    }
                }
            }
            
            guard let initDeclarators = ctx.initDeclaratorList()?.initDeclarator() else {
                return declarations
            }
            
            let allTypes = VarDeclarationTypeExtractor.extractAll(from: ctx)
            
            for (initDeclarator, typeString) in zip(initDeclarators, allTypes) {
                guard let identifier = initDeclarator.declarator()?.directDeclarator()?.identifier() else { continue }
                
                // Get a type string to convert into a proper type
                guard let type = typeParser.parseObjcType(typeString) else { continue }
                
                let inNonnull = nonnullContextQuerier.isInNonnullContext(initDeclarator)
                
                let varDecl = VariableDeclaration(isInNonnullContext: inNonnull)
                
                let identifierNode = nodeFactory.makeIdentifier(from: identifier)
                let typeNameNode = TypeNameNode(type: type, isInNonnullContext: inNonnull)
                typeNameNode.location = nodeFactory.sourceLocation(for: ctx)
                
                varDecl.addChild(identifierNode)
                varDecl.addChild(typeNameNode)
                
                if let initializer = initDeclarator.initializer() {
                    let expression = ExpressionNode(isInNonnullContext: inNonnull)
                    expression.expression = initializer.expression()
                    if let exp = initializer.expression() {
                        expression.location = nodeFactory.sourceLocation(for: exp)
                    }
                    let constantExpression = ConstantExpressionNode(isInNonnullContext: inNonnull)
                    constantExpression.addChild(expression)
                    constantExpression.updateSourceRange()
                    let initialExpression = InitialExpression(isInNonnullContext: inNonnull)
                    initialExpression.addChild(constantExpression)
                    initialExpression.updateSourceRange()
                    
                    varDecl.addChild(initialExpression)
                }
                
                varDecl.updateSourceRange()
                
                declarations.append(varDecl)
            }
            
            return declarations
        }
        
        override func visitTypeSpecifier(_ ctx: ObjectiveCParser.TypeSpecifierContext) -> [ASTNode]? {
            
            if ctx.structOrUnionSpecifier() != nil {
                let structListener =
                    StructListener(typeParser: typeParser,
                                   nonnullContextQuerier: nonnullContextQuerier,
                                   nodeFactory: nodeFactory)
                
                let walker = ParseTreeWalker()
                try? walker.walk(structListener, ctx)
                
                return structListener.structs
            }
            
            return nil
        }
    }
}

private class StructListener: ObjectiveCParserBaseListener {
    var structs: [ObjcStructDeclaration] = []
    var typeParser: TypeParsing
    var nonnullContextQuerier: NonnullContextQuerier
    var nodeFactory: ASTNodeFactory
    
    init(typeParser: TypeParsing,
         nonnullContextQuerier: NonnullContextQuerier,
         nodeFactory: ASTNodeFactory) {
        
        self.typeParser = typeParser
        self.nonnullContextQuerier = nonnullContextQuerier
        self.nodeFactory = nodeFactory
    }
    
    override func enterStructOrUnionSpecifier(_ ctx: ObjectiveCParser.StructOrUnionSpecifierContext) {
        guard ctx.STRUCT() != nil else {
            return
        }
        
        let inNonnull = nonnullContextQuerier.isInNonnullContext(ctx)
        
        let str = ObjcStructDeclaration(isInNonnullContext: inNonnull)
        str.location = nodeFactory.sourceLocation(for: ctx)
        
        if let identifier = ctx.identifier() {
            let identifier = nodeFactory.makeIdentifier(from: identifier)
            
            str.addChild(identifier)
        }
        
        for fieldDeclaration in ctx.fieldDeclaration() {
            let names
                = VarDeclarationIdentifierNameExtractor
                    .extractAll(from: fieldDeclaration)
            
            let types
                = typeParser.parseObjcTypes(inDeclaration: fieldDeclaration)
            
            for (type, identifier) in zip(types, names) {
                let field = ObjcStructField(isInNonnullContext: inNonnull)
                
                let identifierNode = nodeFactory.makeIdentifier(from: identifier)
                
                let typeNode = TypeNameNode(type: type, isInNonnullContext: inNonnull)
                typeNode.location = nodeFactory.sourceLocation(for: fieldDeclaration)
                
                field.addChild(identifierNode)
                field.addChild(typeNode)
                field.location = nodeFactory.sourceLocation(for: fieldDeclaration)
                
                str.addChild(field)
            }
        }
        
        structs.append(str)
    }
}

private class PropertyListener: ObjectiveCParserBaseListener {
    var property: PropertyDefinition
    var typeParser: TypeParsing
    var nonnullContextQuerier: NonnullContextQuerier
    var sourceLocation: (ParserRuleContext) -> SourceLocation
    
    init(isInNonnullContext: Bool,
         typeParser: TypeParsing,
         nonnullContextQuerier: NonnullContextQuerier,
         sourceLocation: @escaping (ParserRuleContext) -> SourceLocation) {
        
        self.property = PropertyDefinition(isInNonnullContext: isInNonnullContext)
        self.typeParser = typeParser
        self.nonnullContextQuerier = nonnullContextQuerier
        self.sourceLocation = sourceLocation
    }
    
    override func enterPropertyDeclaration(_ ctx: ObjectiveCParser.PropertyDeclarationContext) {
        
        let node =
            KeywordNode(keyword: .atProperty,
                        isInNonnullContext: nonnullContextQuerier.isInNonnullContext(ctx))
        node.location = sourceLocation(ctx)
        property.addChild(node)
        
        if let ident =
            ctx.fieldDeclaration()?
                .fieldDeclaratorList()?
                .fieldDeclarator(0)?
                .declarator()?
                .directDeclarator()?
                .identifier() {
            
            let inNonnull = nonnullContextQuerier.isInNonnullContext(ident)
            
            let node = Identifier(name: ident.getText(),
                                  isInNonnullContext: inNonnull)
            node.location = sourceLocation(ident)
            
            property.addChild(node)
        }
        
        if let fieldDeclaration = ctx.fieldDeclaration() {
            let inNonnull = nonnullContextQuerier.isInNonnullContext(fieldDeclaration)
            
            if let type = typeParser.parseObjcType(inDeclaration: fieldDeclaration) {
                let typeNode = TypeNameNode(type: type, isInNonnullContext: inNonnull)
                typeNode.location = sourceLocation(fieldDeclaration)
                property.addChild(typeNode)
            }
        }
    }
    
    override func enterPropertyAttributesList(_ ctx: ObjectiveCParser.PropertyAttributesListContext) {
        let inNonnull = nonnullContextQuerier.isInNonnullContext(ctx)
        
        let node = PropertyAttributesList(isInNonnullContext: inNonnull)
        node.location = sourceLocation(ctx)
        property.addChild(node)
    }
    
    override func enterPropertyAttribute(_ ctx: ObjectiveCParser.PropertyAttributeContext) {
        let modifier: PropertyAttributeNode.Attribute
        
        if let ident = ctx.identifier()?.getText() {
            if ctx.GETTER() != nil {
                modifier = .getter(ident)
            } else if ctx.SETTER() != nil {
                modifier = .setter(ident)
            } else {
                modifier = .keyword(ident)
            }
        } else {
            modifier = .keyword(ctx.getText())
        }
        
        let inNonnull = nonnullContextQuerier.isInNonnullContext(ctx)
        
        let node = PropertyAttributeNode(modifier: modifier,
                                         isInNonnullContext: inNonnull)
        node.location = sourceLocation(ctx)
        property.attributesList?.addChild(node)
    }
}

private class FunctionPointerVisitor: ObjectiveCParserBaseVisitor<TypedefNode> {
    
    var typedefNode: TypedefNode
    var typeParser: TypeParsing
    var nonnullContextQuerier: NonnullContextQuerier
    var nodeFactory: ASTNodeFactory
    
    init(typedefNode: TypedefNode,
         typeParser: TypeParsing,
         nonnullContextQuerier: NonnullContextQuerier,
         nodeFactory: ASTNodeFactory) {
        
        self.typedefNode = typedefNode
        self.typeParser = typeParser
        self.nonnullContextQuerier = nonnullContextQuerier
        self.nodeFactory = nodeFactory
    }
    
    override func visitFunctionPointer(_ ctx: ObjectiveCParser.FunctionPointerContext) -> TypedefNode? {
        guard let identifier = VarDeclarationIdentifierNameExtractor.extract(from: ctx) else {
            return nil
        }
        guard let type = typeParser.parseObjcType(fromFunctionPointer: ctx) else {
            return nil
        }
        
        let inNonnull = nonnullContextQuerier.isInNonnullContext(ctx)
        
        let identifierNode = nodeFactory.makeIdentifier(from: identifier)
        let typeNameNode = TypeNameNode(type: type, isInNonnullContext: inNonnull)
        typeNameNode.location = nodeFactory.sourceLocation(for: ctx)
        
        typedefNode.addChild(identifierNode)
        typedefNode.addChild(typeNameNode)
        
        typedefNode.location = nodeFactory.sourceLocation(for: ctx)
        
        return nil
    }
}

private class GenericParseTreeContextMapper {
    typealias NodeType = ASTNode & InitializableNode
    
    private var pairs: [Pair] = []
    private var exceptions: [ParserRuleContext.Type] = []
    
    private var source: Source
    
    private var nonnullContextQuerier: NonnullContextQuerier
    
    init(source: Source, nonnullContextQuerier: NonnullContextQuerier) {
        self.source = source
        self.nonnullContextQuerier = nonnullContextQuerier
    }
    
    func addRuleMap<T: ParserRuleContext, U: NodeType>(rule: T.Type, nodeType: U.Type) {
        assert(match(ruleType: rule) == nil, "Duplicated mapping rule for parser rule context \(rule)")
        
        pairs.append(.type(rule: rule, nodeType: nodeType))
    }
    
    func addRuleMap<T: ParserRuleContext, U: NodeType>(rule: T.Type, node: U) {
        assert(match(ruleType: rule) == nil, "Duplicated mapping rule for parser rule context \(rule)")
        
        pairs.append(.instance(rule: rule, node: node))
    }
    
    func pushTemporaryException(forRuleType ruleType: ParserRuleContext.Type) {
        exceptions.append(ruleType)
    }
    
    func popTemporaryException() {
        exceptions.removeLast()
    }
    
    func matchEnter(rule: ParserRuleContext, context: NodeCreationContext) {
        let ruleType = type(of: rule)
        guard let nodeType = match(ruleType: ruleType) else {
            return
        }
        
        switch nodeType {
        case .type(_, let nodeType):
            let node =
                nodeType.init(isInNonnullContext:
                    nonnullContextQuerier.isInNonnullContext(rule))
            
            let startIndex = rule.start?.getStartIndex() ?? 0
            let endIndex = rule.stop?.getStopIndex() ?? 0
            
            let line = rule.start?.getLine() ?? 0
            let column = (rule.start?.getCharPositionInLine()).map { $0 + 1 } ?? 0
            
            node.location =
                SourceLocation(source: source,
                               intRange: startIndex..<endIndex,
                               line: line,
                               column: column)
            
            context.pushContext(node: node)
        case .instance(_, let node):
            context.pushContext(node: node)
        }
    }
    
    func matchExit(rule: ParserRuleContext, context: NodeCreationContext) {
        let ruleType = type(of: rule)
        guard let pair = match(ruleType: ruleType) else {
            return
        }
        
        if let popped = context.popContext() {
            switch pair {
            case .type(_, let nodeType):
                assert(type(of: popped) == nodeType)
            case .instance(_, let node):
                assert(popped === node)
            }
        }
    }
    
    private func match(ruleType: ParserRuleContext.Type) -> Pair? {
        if exceptions.contains(where: { $0 === ruleType }) {
            return nil
        }
        
        return pairs.first { $0.ruleType === ruleType }
    }
    
    private enum Pair {
        case type(rule: ParserRuleContext.Type, nodeType: NodeType.Type)
        case instance(rule: ParserRuleContext.Type, node: NodeType)
        
        var ruleType: ParserRuleContext.Type {
            switch self {
            case .type(let rule, _):
                return rule
            case .instance(let rule, _):
                return rule
            }
        }
    }
}
