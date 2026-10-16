## Backends for the shared test suite.
##
## Each backend knows how to turn a plain Julia expression (`:(sin(2x) + a)`)
## into a subject of its own type. Tests are written once, in terms of `Expr`,
## and run against every backend. The `Expr` backend uses the expression
## itself as the subject.

using SymEngine, SymbolicUtils, SimpleExpressions

struct Backend{F}
    name::String
    build::F            # Expr/Symbol/Number -> subject
    canonicalizes::Bool # does the type rewrite expressions (a + a -> 2a)?
end

Base.show(io::IO, B::Backend) = print(io, B.name)

# Build a subject from an expression by evaluating each call with the Base
# function of the same name, starting from the backend's variables.
function evaluator(var)
    f(x::Number) = x
    f(x::Symbol) = var(x)
    function f(ex::Expr)
        Meta.isexpr(ex, :call) || throw(ArgumentError("can not build $ex"))
        op = getfield(Base, first(ex.args))
        op(map(f, ex.args[2:end])...)
    end
    f
end

const BACKENDS = (
    Backend("Expr",              identity,                                  false),
    Backend("SymEngine",         evaluator(s -> SymEngine.symbols(s)),      true),
    Backend("SymbolicUtils",     evaluator(s -> SymbolicUtils.Sym{SymbolicUtils.SymReal}(s; type=Number)), true),
    Backend("SimpleExpressions", evaluator(SimpleExpressions.SymbolicVariable), true),
)

backend(name) = only(B for B ∈ BACKENDS if B.name == name)

## Glue code. This would naturally live in a package extension (or in
## SimpleExpressions itself); it is needed so that numeric literals in a
## pattern compare equal to numeric terms in the subject.
CPM.unwrap_const(x::SimpleExpressions.SymbolicNumber) = x()
# SymbolicUtils v4 wraps numeric arguments as symbolic constants
CPM.unwrap_const(x::SymbolicUtils.BasicSymbolic) = SymbolicUtils.unwrap_const(x)
