## ---- rewriting -----

"""
    Rule

A rule created by [`@rule`](@ref). Call it on a subject to rewrite it:
`rule(sub)` returns the rewritten term, or `nothing` if `sub` does not
match.
"""
struct Rule
    lhs::Any      # pattern
    rhs::Any      # template, used for `Expr` subjects
    f::Function   # σ -> rhs, compiled where the rule was written
end
# `f` is not a type parameter: with thousands of rules, a parameter would
# mean compiling a method for calling each rule.

function (r::Rule)(sub; kwargs...)
    σ = _match(r.lhs, sub; kwargs...)
    σ === nothing && return nothing
    symtype(sub) === Expr ? _rewrite(σ, r.rhs, Expr) : r.f(σ)
end

Base.show(io::IO, r::Rule) = print(io, "@rule ", r.lhs, " => ", r.rhs)

"""
    @rule lhs => rhs

Create a rule which rewrites a subject matching the pattern `lhs` into
`rhs`, with the wildcards of `rhs` replaced by their matched values.

`lhs` is a pattern, as for [`@pattern`](@ref). `rhs` is Julia code: it is
compiled into a function of the match where the macro is called, so
functions and variables it refers to are those of the calling module. A
segment (`~~x`) is replaced by its tuple (or term, with `wrap_commutative`).

For a symbolic subject `rhs` is evaluated; for an `Expr` subject, the
matched values are substituted into `rhs` and an `Expr` is returned.

## Examples

```julia
julia> using CommutativePatternMatching, SymEngine

julia> @vars x;

julia> r = @rule (~x)^(~n::isinteger) => (~x)^(~n + 1) / (~n + 1);

julia> r(x^2)
(1/3)*x^3

julia> r(:(x^2))
:(x ^ (2 + 1) / (2 + 1))

julia> r(sin(x)) === nothing
true
```
"""
macro rule(ex)
    (Meta.isexpr(ex, :call, 3) && ex.args[1] === :(=>)) ||
        throw(ArgumentError("@rule expects `lhs => rhs`"))
    lhs, rhs = ex.args[2], ex.args[3]
    σ = gensym(:σ)
    pat = Expr(:quote, _splice_guards(lhs, false))
    tpl = Expr(:quote, _escape_interpolations(rhs))
    f = esc(Expr(:->, σ, _slots_to_lookups(rhs, σ)))
    :($Rule($pat, $tpl, $f))
end

_isslot(ex) = Meta.isexpr(ex, :call) && first(ex.args) === :(~)

# replace each wildcard of rhs by a lookup in the match σ; `$x` is just `x`
_slots_to_lookups(x, σ) = x
function _slots_to_lookups(ex::Expr, σ)
    _isslot(ex) && return :($σ[$(QuoteNode(varname(ex)))])
    ex.head === :$ && return only(ex.args)
    Expr(ex.head, map(a -> _slots_to_lookups(a, σ), ex.args)...)
end

_escape_interpolations(x) = x
function _escape_interpolations(ex::Expr)
    ex.head === :$ && return Expr(:$, map(esc, ex.args)...)
    Expr(ex.head, map(_escape_interpolations, ex.args)...)
end

"""
    _rewrite(σ, rhs, [S])

Rewrite the template `rhs` using the match `σ`.

If `rhs` is a function, it is called on `σ`, as for a rule from `@rule`.

If `rhs` is an expression, its wildcards are replaced by their values. For
an `Expr` subject (`S == Expr`) the result is an expression. Otherwise each
call is evaluated: an operation given by name is looked up in `Main` and
`Base`, so to use a function from another module use `@rule`, or splice
the function into the template (`:(\$f(~x))`).

The subject type `S` is found from the values in `σ` if not given.
"""
_rewrite(σ::MatchDict, rhs) = _rewrite(σ, rhs, _symtype(σ))

_rewrite(σ::MatchDict, rhs::Function, S) = rhs(σ)
_rewrite(σ::MatchDict, tpl, S) = tpl

function _rewrite(σ::MatchDict, tpl::Symbol, S)
    S === Expr && return tpl
    val = Base.invokelatest(_resolve_name, tpl)
    val === nothing &&
        throw(ArgumentError("`$tpl` can not be resolved; use `@rule` for names from other modules"))
    val
end

function _rewrite(σ::MatchDict, rhs::Expr, S)
    if _isslot(rhs)
        var = varname(rhs)
        haskey(σ, var) || throw(ArgumentError("no match for variable $(var)"))
        return σ[var]
    end

    if !iscall(rhs)
        S === Expr || throw(ArgumentError("`$rhs` is not a call; use `@rule` for general expressions"))
        return Expr(rhs.head, (_rewrite(σ, a, S) for a ∈ rhs.args)...)
    end

    op = operation(rhs)
    args = [_rewrite(σ, a, S) for a ∈ arguments(rhs)]
    if _isslot(op) # (~F)(...)
        op = σ[varname(op)]
    end

    if S === Expr
        op = isa(op, Union{Symbol, Expr}) ? op : nameof(op)
        return pterm(op, args; elide=false)
    end

    f = isa(op, Symbol) ? _rewrite(σ, op, S) : op
    Base.invokelatest(f, args...)
end

# Is the subject an `Expr`? Find a symbolic value among those matched,
# skipping operations bound by `(~F)` (some symbolic types are `Function`s)
_isoperation(u) = isa(u, Function) &&
    Base.moduleroot(parentmodule(typeof(u))) ∈ (Base, Core)

function _symtype(σ::MatchDict)
    for v ∈ values(σ), u ∈ (isa(v, Tuple) ? v : (v,))
        _isoperation(u) && continue
        S = symtype(u)
        S === Expr || return S
    end
    return Expr
end
