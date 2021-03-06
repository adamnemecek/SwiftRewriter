open class Statement: SyntaxNode, Equatable {
    /// Returns `true` if this statement resolve to an unconditional jump out
    /// of the current context.
    ///
    /// Returns true for `.break`, `.continue` and `.return` statements.
    public var isUnconditionalJump: Bool {
        return false
    }
    
    /// This statement label's (parsed from C's goto labels), if any.
    public var label: String?
    
    open override func copy() -> Statement {
        fatalError("Must be overriden by subclasses")
    }
    
    /// Accepts the given visitor instance, calling the appropriate visiting method
    /// according to this statement's type.
    ///
    /// - Parameter visitor: The visitor to accept
    /// - Returns: The result of the visitor's `visit-` call when applied to this
    /// statement
    public func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitStatement(self)
    }
    
    public func isEqual(to other: Statement) -> Bool {
        return false
    }
    
    public static func == (lhs: Statement, rhs: Statement) -> Bool {
        if lhs === rhs {
            return true
        }
        
        return lhs.isEqual(to: rhs)
    }
    
    fileprivate func cast<T>() -> T? {
        return self as? T
    }
}

/// An empty semicolon statement with no semantic functionality.
public class SemicolonStatement: Statement {
    public override func copy() -> SemicolonStatement {
        return SemicolonStatement().copyMetadata(from: self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        return other is SemicolonStatement
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitSemicolon(self)
    }
}
public extension Statement {
    public var asSemicolon: SemicolonStatement? {
        return cast()
    }
}

/// Encapsulates a compound statement, that is, a series of statements enclosed
/// within braces.
public class CompoundStatement: Statement, ExpressibleByArrayLiteral {
    /// An empty compound statement.
    public static var empty: CompoundStatement {
        return CompoundStatement()
    }
    
    public var isEmpty: Bool {
        return statements.isEmpty
    }
    
    public var statements: [Statement] = [] {
        didSet {
            oldValue.forEach { $0.parent = nil }
            statements.forEach { $0.parent = self }
        }
    }
    
    public override var children: [SyntaxNode] {
        return statements
    }
    
    public init(statements: [Statement]) {
        self.statements = statements
        
        super.init()
        
        statements.forEach { $0.parent = self }
    }
    
    public required init(arrayLiteral elements: Statement...) {
        self.statements = elements
        
        super.init()
        
        statements.forEach { $0.parent = self }
    }
    
    public override func copy() -> CompoundStatement {
        return CompoundStatement(statements: statements.map { $0.copy() }).copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitCompound(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as CompoundStatement:
            return statements == rhs.statements
        default:
            return false
        }
    }
}

extension CompoundStatement: Sequence {
    public func makeIterator() -> IndexingIterator<[Statement]> {
        return statements.makeIterator()
    }
}

public extension Statement {
    public var asCompound: CompoundStatement? {
        return cast()
    }
}

public class IfStatement: Statement {
    public var exp: Expression {
        didSet { oldValue.parent = nil; exp.parent = self }
    }
    public var body: CompoundStatement {
        didSet { oldValue.parent = nil; body.parent = self }
    }
    public var elseBody: CompoundStatement? {
        didSet { oldValue?.parent = nil; elseBody?.parent = self }
    }
    
    /// If non-nil, the expression of this if statement must be resolved to a
    /// pattern match over a given pattern.
    ///
    /// This is used to create if-let statements.
    public var pattern: Pattern?
    
    public var isIfLet: Bool {
        return pattern != nil
    }
    
    public override var children: [SyntaxNode] {
        if let elseBody = elseBody {
            return [exp, body, elseBody]
        }
        return [exp, body]
    }
    
    public init(exp: Expression, body: CompoundStatement, elseBody: CompoundStatement?) {
        self.exp = exp
        self.body = body
        self.elseBody = elseBody
        
        super.init()
        
        exp.parent = self
        body.parent = self
        elseBody?.parent = self
    }
    
    public override func copy() -> IfStatement {
        let copy =
            IfStatement(exp: exp.copy(), body: body.copy(), elseBody: elseBody?.copy())
                .copyMetadata(from: self)
        
        copy.pattern = pattern?.copy()
        
        return copy
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitIf(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as IfStatement:
            return exp == rhs.exp && pattern == rhs.pattern && body == rhs.body && elseBody == rhs.elseBody
        default:
            return false
        }
    }
}
public extension Statement {
    public var asIf: IfStatement? {
        return cast()
    }
}

public class WhileStatement: Statement {
    public var exp: Expression {
        didSet {
            oldValue.parent = nil
            exp.parent = self
        }
    }
    public var body: CompoundStatement {
        didSet {
            oldValue.parent = nil
            body.parent = self
        }
    }
    
    public override var children: [SyntaxNode] {
        return [exp, body]
    }
    
    public init(exp: Expression, body: CompoundStatement) {
        self.exp = exp
        self.body = body
        
        super.init()
        
        exp.parent = self
        body.parent = self
    }
    
    public override func copy() -> WhileStatement {
        return WhileStatement(exp: exp.copy(), body: body.copy()).copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitWhile(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as WhileStatement:
            return exp == rhs.exp && body == rhs.body
        default:
            return false
        }
    }
}
public extension Statement {
    public var asWhile: WhileStatement? {
        return cast()
    }
}

public class DoWhileStatement: Statement {
    public var exp: Expression {
        didSet {
            oldValue.parent = nil
            exp.parent = self
        }
    }
    public var body: CompoundStatement {
        didSet {
            oldValue.parent = nil
            body.parent = self
        }
    }
    
    public override var children: [SyntaxNode] {
        return [exp, body]
    }
    
    public init(exp: Expression, body: CompoundStatement) {
        self.exp = exp
        self.body = body
        
        super.init()
        
        exp.parent = self
        body.parent = self
    }
    
    public override func copy() -> DoWhileStatement {
        return DoWhileStatement(exp: exp.copy(), body: body.copy()).copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitDoWhile(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as DoWhileStatement:
            return exp == rhs.exp && body == rhs.body
        default:
            return false
        }
    }
}
public extension Statement {
    public var asDoWhile: DoWhileStatement? {
        return cast()
    }
}

public class ForStatement: Statement {
    /// Cache of children nodes
    private var _childrenNodes: [SyntaxNode] = []
    
    public var pattern: Pattern {
        didSet {
            oldValue.setParent(nil)
            pattern.setParent(self)
            
            reloadChildrenNodes()
        }
    }
    public var exp: Expression {
        didSet {
            oldValue.parent = nil
            exp.parent = self
            
            reloadChildrenNodes()
        }
    }
    public var body: CompoundStatement {
        didSet {
            oldValue.parent = nil
            body.parent = self
            
            reloadChildrenNodes()
        }
    }
    
    public override var children: [SyntaxNode] {
        return _childrenNodes
    }
    
    public init(pattern: Pattern, exp: Expression, body: CompoundStatement) {
        self.pattern = pattern
        self.exp = exp
        self.body = body
        
        super.init()
        
        pattern.setParent(self)
        exp.parent = self
        body.parent = self
    }
    
    public override func copy() -> ForStatement {
        return
            ForStatement(pattern: pattern.copy(), exp: exp.copy(), body: body.copy())
                .copyMetadata(from: self)
    }
    
    private func reloadChildrenNodes() {
        _childrenNodes.removeAll()
        
        _childrenNodes.append(exp)
        
        pattern.collect(expressions: &_childrenNodes)
        
        _childrenNodes.append(body)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitFor(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as ForStatement:
            return pattern == rhs.pattern && exp == rhs.exp && body == rhs.body
        default:
            return false
        }
    }
}
public extension Statement {
    public var asFor: ForStatement? {
        return cast()
    }
}

public class SwitchStatement: Statement {
    /// Cache of children expression and statements stored into each case pattern
    private var _childrenNodes: [SyntaxNode] = []
    
    public var exp: Expression {
        didSet {
            oldValue.parent = nil
            exp.parent = self
            
            reloadChildrenNodes()
        }
    }
    public var cases: [SwitchCase] {
        didSet {
            oldValue.forEach {
                $0.patterns.forEach {
                    $0.setParent(self)
                }
                $0.statements.forEach {
                    $0.parent = self
                }
            }
            
            cases.forEach {
                $0.patterns.forEach {
                    $0.setParent(self)
                }
                $0.statements.forEach {
                    $0.parent = self
                }
            }
            
            reloadChildrenNodes()
        }
    }
    public var defaultCase: [Statement]? {
        didSet {
            oldValue?.forEach { $0.parent = nil }
            defaultCase?.forEach { $0.parent = nil }
            
            reloadChildrenNodes()
        }
    }
    
    public override var children: [SyntaxNode] {
        return _childrenNodes
    }
    
    public init(exp: Expression, cases: [SwitchCase], defaultCase: [Statement]?) {
        self.exp = exp
        self.cases = cases
        self.defaultCase = defaultCase
        
        super.init()
        
        exp.parent = self
        cases.forEach {
            $0.patterns.forEach {
                $0.setParent(self)
            }
            $0.statements.forEach {
                $0.parent = self
            }
        }
        defaultCase?.forEach { $0.parent = self }
        
        reloadChildrenNodes()
    }
    
    public override func copy() -> SwitchStatement {
        return
            SwitchStatement(exp: exp.copy(),
                            cases: cases.map { $0.copy() },
                            defaultCase: defaultCase?.map { $0.copy() }).copyMetadata(from: self)
    }
    
    private func reloadChildrenNodes() {
        _childrenNodes.removeAll()
        
        _childrenNodes.append(exp)
        
        cases.forEach {
            $0.patterns.forEach {
                $0.collect(expressions: &_childrenNodes)
            }
            _childrenNodes.append(contentsOf: $0.statements)
        }
        
        if let defaultCase = defaultCase {
            _childrenNodes.append(contentsOf: defaultCase)
        }
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitSwitch(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as SwitchStatement:
            return exp == rhs.exp && cases == rhs.cases && defaultCase == rhs.defaultCase
        default:
            return false
        }
    }
}
public extension Statement {
    public var asSwitch: SwitchStatement? {
        return cast()
    }
}

public class DoStatement: Statement {
    public var body: CompoundStatement {
        didSet {
            oldValue.parent = nil
            body.parent = self
        }
    }
    
    public override var children: [SyntaxNode] {
        return [body]
    }
    
    public init(body: CompoundStatement) {
        self.body = body
        
        super.init()
        
        body.parent = self
    }
    
    public override func copy() -> DoStatement {
        return DoStatement(body: body.copy()).copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitDo(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as DoStatement:
            return body == rhs.body
        default:
            return false
        }
    }
}
public extension Statement {
    public var asDoStatement: DoStatement? {
        return cast()
    }
}

public class DeferStatement: Statement {
    public var body: CompoundStatement {
        didSet {
            oldValue.parent = nil
            body.parent = self
        }
    }
    
    public override var children: [SyntaxNode] {
        return [body]
    }
    
    public init(body: CompoundStatement) {
        self.body = body
        
        super.init()
        
        body.parent = self
    }
    
    public override func copy() -> DeferStatement {
        return DeferStatement(body: body.copy()).copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitDefer(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as DeferStatement:
            return body == rhs.body
        default:
            return false
        }
    }
}
public extension Statement {
    public var asDefer: DeferStatement? {
        return cast()
    }
}

public class ReturnStatement: Statement {
    public override var isUnconditionalJump: Bool {
        return true
    }
    
    public var exp: Expression? {
        didSet {
            oldValue?.parent = nil
            exp?.parent = self
        }
    }
    
    public override var children: [SyntaxNode] {
        if let exp = exp {
            return [exp]
        }
        
        return []
    }
    
    public init(exp: Expression? = nil) {
        self.exp = exp
        
        super.init()
        
        exp?.parent = self
    }
    
    public override func copy() -> ReturnStatement {
        return ReturnStatement(exp: exp?.copy()).copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitReturn(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as ReturnStatement:
            return exp == rhs.exp
        default:
            return false
        }
    }
}
public extension Statement {
    public var asReturn: ReturnStatement? {
        return cast()
    }
}

public class BreakStatement: Statement {
    public override var isUnconditionalJump: Bool {
        return true
    }
    
    public override func copy() -> BreakStatement {
        return BreakStatement().copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitBreak(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        return other is BreakStatement
    }
}
public extension Statement {
    public var asBreak: BreakStatement? {
        return cast()
    }
}

public class ContinueStatement: Statement {
    public override var isUnconditionalJump: Bool {
        return true
    }
    
    public override func copy() -> ContinueStatement {
        return ContinueStatement().copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitContinue(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        return other is ContinueStatement
    }
}
public extension Statement {
    public var asContinue: ContinueStatement? {
        return cast()
    }
}

public class ExpressionsStatement: Statement {
    public var expressions: [Expression] {
        didSet {
            oldValue.forEach { $0.parent = self }
            expressions.forEach { $0.parent = self }
        }
    }
    
    public override var children: [SyntaxNode] {
        return expressions
    }
    
    public init(expressions: [Expression]) {
        self.expressions = expressions
        
        super.init()
        
        expressions.forEach { $0.parent = self }
    }
    
    public override func copy() -> ExpressionsStatement {
        return
            ExpressionsStatement(expressions: expressions.map { $0.copy() })
                .copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitExpressions(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as ExpressionsStatement:
            return expressions == rhs.expressions
        default:
            return false
        }
    }
}
public extension Statement {
    public var asExpressions: ExpressionsStatement? {
        return cast()
    }
}

public class VariableDeclarationsStatement: Statement {
    public var decl: [StatementVariableDeclaration] {
        didSet {
            oldValue.forEach {
                $0.initialization?.parent = nil
            }
            decl.forEach {
                $0.initialization?.parent = self
            }
        }
    }
    
    public override var children: [SyntaxNode] {
        return decl.compactMap { $0.initialization }
    }
    
    public init(decl: [StatementVariableDeclaration]) {
        self.decl = decl
        
        super.init()
        
        decl.forEach {
            $0.initialization?.parent = self
        }
    }
    
    public override func copy() -> VariableDeclarationsStatement {
        return VariableDeclarationsStatement(decl: decl.map { $0.copy() }).copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitVariableDeclarations(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        switch other {
        case let rhs as VariableDeclarationsStatement:
            return decl == rhs.decl
        default:
            return false
        }
    }
}
public extension Statement {
    public var asVariableDeclaration: VariableDeclarationsStatement? {
        return cast()
    }
}

public class UnknownStatement: Statement {
    public var context: UnknownASTContext
    
    public init(context: UnknownASTContext) {
        self.context = context
    }
    
    public override func copy() -> UnknownStatement {
        return UnknownStatement(context: context).copyMetadata(from: self)
    }
    
    public override func accept<V: StatementVisitor>(_ visitor: V) -> V.StmtResult {
        return visitor.visitUnknown(self)
    }
    
    public override func isEqual(to other: Statement) -> Bool {
        return other is UnknownStatement
    }
}
public extension Statement {
    public var asUnknown: UnknownStatement? {
        return cast()
    }
}

public extension Statement {
    public static var semicolon: SemicolonStatement {
        return SemicolonStatement()
    }
    public static func compound(_ cpd: [Statement]) -> CompoundStatement {
        return CompoundStatement(statements: cpd)
    }
    public static func `if`(_ exp: Expression,
                            body: CompoundStatement,
                            else elseBody: CompoundStatement?) -> IfStatement {
        
        return IfStatement(exp: exp, body: body, elseBody: elseBody)
    }
    public static func ifLet(_ pattern: Pattern,
                             _ exp: Expression,
                             body: CompoundStatement,
                             else elseBody: CompoundStatement?) -> IfStatement {
        
        let stmt = IfStatement(exp: exp, body: body, elseBody: elseBody)
        stmt.pattern = pattern
        
        return stmt
    }
    public static func `while`(_ exp: Expression, body: CompoundStatement) -> WhileStatement {
        return WhileStatement(exp: exp, body: body)
    }
    public static func doWhile(_ exp: Expression, body: CompoundStatement) -> DoWhileStatement {
        return DoWhileStatement(exp: exp, body: body)
    }
    public static func `for`(_ pattern: Pattern, _ exp: Expression, body: CompoundStatement) -> ForStatement {
        return ForStatement(pattern: pattern, exp: exp, body: body)
    }
    public static func `switch`(_ exp: Expression,
                                cases: [SwitchCase],
                                default defaultCase: [Statement]?) -> SwitchStatement {
        
        return SwitchStatement(exp: exp, cases: cases, defaultCase: defaultCase)
    }
    public static func `do`(_ stmt: CompoundStatement) -> DoStatement {
        return DoStatement(body: stmt)
    }
    public static func `defer`(_ stmt: CompoundStatement) -> DeferStatement {
        return DeferStatement(body: stmt)
    }
    public static func `return`(_ exp: Expression?) -> ReturnStatement {
        return ReturnStatement(exp: exp)
    }
    public static var `break`: BreakStatement {
        return BreakStatement()
    }
    public static var `continue`: ContinueStatement {
        return ContinueStatement()
    }
    public static func expressions(_ exp: [Expression]) -> ExpressionsStatement {
        return ExpressionsStatement(expressions: exp)
    }
    public static func variableDeclarations(_ decl: [StatementVariableDeclaration]) -> VariableDeclarationsStatement {
        return VariableDeclarationsStatement(decl: decl)
    }
    public static func unknown(_ context: UnknownASTContext) -> UnknownStatement {
        return UnknownStatement(context: context)
    }
    public static func expression(_ expr: Expression) -> Statement {
        return .expressions([expr])
    }
    
    public static func variableDeclaration(identifier: String,
                                           type: SwiftType,
                                           ownership: Ownership = .strong,
                                           isConstant: Bool = false,
                                           initialization: Expression?) -> Statement {
        
        return .variableDeclarations([
            StatementVariableDeclaration(identifier: identifier,
                                         type: type,
                                         ownership: ownership,
                                         isConstant: isConstant,
                                         initialization: initialization)
        ])
    }
}

public struct SwitchCase: Equatable {
    /// Patterns for this switch case
    public var patterns: [Pattern]
    /// Statements for the switch case
    public var statements: [Statement]
    
    public init(patterns: [Pattern], statements: [Statement]) {
        self.patterns = patterns
        self.statements = statements
    }
    
    public func copy() -> SwitchCase {
        return SwitchCase(patterns: patterns.map { $0.copy() },
                          statements: statements.map { $0.copy() })
    }
}

/// A pattern for pattern-matching
public enum Pattern: Equatable {
    /// An identifier pattern
    case identifier(String)
    
    /// An expression pattern
    case expression(Expression)
    
    /// A tuple pattern
    indirect case tuple([Pattern])
    
    /// Simplifies patterns that feature 1-item tuples (i.e. `(<item>)`) by unwrapping
    /// the inner patterns.
    public var simplified: Pattern {
        switch self {
        case .tuple(let pt) where pt.count == 1:
            return pt[0].simplified
        default:
            return self
        }
    }
    
    public static func fromExpressions(_ expr: [Expression]) -> Pattern {
        if expr.count == 1 {
            return .expression(expr[0])
        }
        
        return .tuple(expr.map { .expression($0) })
    }
    
    public func copy() -> Pattern {
        switch self {
        case .identifier:
            return self
        case .expression(let exp):
            return .expression(exp.copy())
        case .tuple(let patterns):
            return .tuple(patterns.map { $0.copy() })
        }
    }
    
    internal func setParent(_ node: SyntaxNode?) {
        switch self {
        case .expression(let exp):
            exp.parent = node
            
        case .tuple(let tuple):
            tuple.forEach { $0.setParent(node) }
            
        case .identifier:
            break
        }
    }
    
    internal func collect(expressions: inout [SyntaxNode]) {
        switch self {
        case .expression(let exp):
            expressions.append(exp)
            
        case .tuple(let tuple):
            tuple.forEach { $0.collect(expressions: &expressions) }
            
        case .identifier:
            break
        }
    }
}

/// A variable declaration statement
public struct StatementVariableDeclaration: Equatable {
    public var identifier: String
    public var type: SwiftType
    public var ownership: Ownership
    public var isConstant: Bool
    public var initialization: Expression?
    
    public init(identifier: String,
                type: SwiftType,
                ownership: Ownership = .strong,
                isConstant: Bool = false,
                initialization: Expression? = nil) {
        
        self.identifier = identifier
        self.type = type
        self.ownership = ownership
        self.isConstant = isConstant
        self.initialization = initialization
    }
    
    public func copy() -> StatementVariableDeclaration {
        var new = self
        new.initialization = self.initialization?.copy()
        return new
    }
}

extension Pattern: CustomStringConvertible {
    public var description: String {
        switch self.simplified {
        case .tuple(let tups):
            return "(" + tups.map({ $0.description }).joined(separator: ", ") + ")"
        case .expression(let exp):
            return exp.description
        case .identifier(let ident):
            return ident
        }
    }
}

public extension Statement {
    
    func copyMetadata(from other: Statement) -> Self {
        self.label = other.label
        
        return self
    }
    
}
