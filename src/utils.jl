## ---- utils.jl -----


const M = MatchDict = Base.ImmutableDict{Symbol, Any}
const FAIL_DICT = MatchDict(:_fail, 0)

const NO_MATCH = ∅ = MatchDict[]
𝑀 = Vector{MatchDict}



## unwrap a constant to a Julia value; extend for symbolic types
unwrap_const(x::Any) = x
function unwrap_const(x::Symbol)
    if hasproperty(Base.MathConstants, x)
        return getproperty(Base.MathConstants, x)
    end
    x == :twoπ && return 2π
    x == :fourπ && return      4π
    x == :halfπ && return      π / 2
    x == :quartπ && return     π / 4
    x == :invπ && return       1 / π
    x == :twoinvπ && return    2 / π
    x == :fourinvπ && return   4 / π
    x == :inv2π && return      1 / (2π)
    x == :inv4π && return      1 / (4π)
    x == :sqrt2 && return      √2
    x == :sqrt3 && return      √3
    x == :sqrtπ && return      √π
    x == :sqrt2π && return     √2π
    x == :sqrt4π && return     √4π
    x == :sqrthalfπ && return  √(π / 2)
    x == :invsqrt2 && return   1 / √2
    x == :invsqrtπ && return   1 / √π
    x == :invsqrt2π && return  1 / √2π
    x == :loghalf && return    log(1 / 2)
    x == :logtwo && return     log(2)
    x == :logten && return     log(10)
    x == :logπ && return       log(π)
    x == :log2π && return      log(2π)
    x == :log4π && return      log(4π)
    return x
end

_unwrap_const(x) = unwrap_const(x)

# compare head and arguments of two terms
function syntactic_match(a, b)
    𝑎, 𝑏 = isexpr(a), isexpr(b)
    𝑎 == 𝑏 || return false
    !𝑎 && return isequal(a, b)
    operation(a) ==  operation(b) || return false
    as, bs = arguments(a), arguments(b)
    length(as) == length(bs) || return false
    all(splat(isequal), zip(as, bs))
end


## matches are ImmutableDicts
match_dict() = MatchDict()

function match_dict(kvs::Pair...)::M
    σ = MatchDict()
    match_dict(σ, kvs...)
end

function match_dict(σ::MatchDict, kvs::Pair...)::M
    for (k,v) ∈ kvs
        v = isa(v,Number) ? unwrap_const(v) : v
        if haskey(σ, k)
            σk = σ[k]
            !isequal(σk, v) && error("repeated key with different value: $k => $v ($σk)")
        else
            σ = MatchDict(σ, k, v)
        end
    end
    σ
end

# same keys and `isequal` values. (`==` may not return a Bool for
# symbolic values, e.g. SymbolicUtils)
function _isequal_match(σ::MatchDict, σ′::MatchDict)::Bool
    length(σ) == length(σ′) || return false
    for (k, v) ∈ σ
        haskey(σ′, k) || return false
        isequal(v, σ′[k]) || return false
    end
    return true
end

#  σ △ σ′ (\bigtriangleup) for every x in the intersection of the domains has same value
function iscompatible(σ::MatchDict, σ′::MatchDict)::Bool
    isempty(σ) && return true
    isempty(σ′) && return true
    for (k, v) ∈ σ
        if haskey(σ′, k) # intersect(keys(σ), keys(σ′)) allocates
            isequal(v, σ′[k]) || return false
        end
    end
    return true
end

# σ ⊔ σ′ (\sqcup) is union of two compatible matches
function merge_match(σ::MatchDict, σ′::MatchDict)::M
    # assume compatible
    for (k,v) ∈ σ′
        σ = match_dict(σ, k => v)
    end
    σ
end
## XXXmerge_match(σ::Tuple, σ′::MatchDict) = σ′

function union_merge(θ::𝑀, σ′::MatchDict)::𝑀
    σ′ === FAIL_DICT && return NO_MATCH
    MatchDict[merge_match(σ, σ′) for σ ∈ θ if iscompatible(σ, σ′)]
end

## AI generated union_merge
function _merge_single(σs::𝑀, σ′::M)::𝑀
    σ′ === FAIL_DICT && return NO_MATCH
    σs == NO_MATCH &&  return NO_MATCH
    merged = MatchDict[]
    sizehint!(merged, length(σs))
    for σ ∈ σs
        iscompatible(σ, σ′) || continue
        push!(merged, merge_match(σ, σ′))
    end
    return isempty(merged) ? MatchDict[] : merged
end

## AI generated union_merge with k=>v
function _merge_single_expr(σs, k, v)
    σ = match_dict(k => v)
    _merge_single(σs, σ)
end

function union_merge(θ::𝑀, θ′::𝑀)::𝑀
    [merge_match(σ, σ′) for σ ∈ θ for σ′ ∈ θ′ if iscompatible(σ, σ′)]
end

## more utils
_isone(x) = isequal(x, 1)
_groupby(pred, t) = (t = filter(pred,t), f=filter(!pred, t))

## co-pilot written utils
function _split_segments(arg_rule)
    seg = Expr[]
    notseg = Any[]
    seg_positions = Int[]
    for (i, pat) ∈ enumerate(arg_rule)
        if is_segment(pat) || is_plus(pat)
            push!(seg, pat)
            push!(seg_positions, i)
        else
            push!(notseg, pat)
        end
    end
    return seg, notseg, seg_positions
end

function _tuple_without_indices(arg_data, ind, n)
    vals = Any[]
    sizehint!(vals, n - length(ind))
    k = 1
    nextskip = first(ind)
    @inbounds for i ∈ 1:n
        if k <= length(ind) && i == nextskip
            k += 1
            nextskip = k <= length(ind) ? ind[k] : 0
        else
            push!(vals, arg_data[i])
        end
    end
    return tuple(vals...)
end

# Generate every k-tuple of nonnegative integers that sum to n (a
# "composition" of n into k parts, stars-and-bars style), by direct
# recursive construction. This visits exactly the C(n+k-1, k-1) valid
# tuples, as opposed to generating the full (n+1)^k Cartesian product via
# `Iterators.product(0:n, ..., 0:n)` and discarding every tuple whose
# entries don't sum to n -- the latter wastes work that grows quickly
# (exponentially in k) as the number of segment wildcards increases.
function _compositions(n::Int, k::Int)
    k == 1 && return Any[(n,)]
    out = Any[]
    for a ∈ 0:n
        for rest ∈ _compositions(n - a, k - 1)
            push!(out, (a, rest...))
        end
    end
    return out
end


## Expression related methods
_is_operation(op) = ex -> iscall(ex) && operation(ex) ∈ (op, Symbol(op))

# need to compare x and p when p is from an expression
# trick -- SymEngine.Basic <: Number
# compare Number, Expr, Irrational, Symbol

eq_expr(a::Any, b::Any) = isequal(_unwrap_const(a), _unwrap_const(b))
eq_expr(a::Expr, b::Expr) = syntactic_match(_unwrap_const(a), _unwrap_const(b))

# a symbol in a pattern matches a symbolic variable of the same name
eq_expr(a::Any, b::Symbol) = isequal(_unwrap_const(a), _unwrap_const(b)) ||
    (!iscall(a) && !isa(a, Symbol) && Symbol(string(a)) === b)

## -- evaluate a guard
#
# A guard is best given as a value -- a function spliced into the pattern,
# as `@pattern` does, or as with `:(~x::$pred)`. Such a guard is called
# directly.
#
# A guard given by name or as an expression in a quoted pattern
# (`:(~x::isfoo)`) is looked up in `Main` and `Base`, not in the module
# which wrote the pattern; use `@pattern` for that. A guard which can not be
# resolved, or which errors, fails the match.

_resolve_predicate(pred) = pred

# a name, as used in a quoted pattern or template, or `nothing`
function _resolve_name(x::Symbol)
    for M ∈ (Main, Base)
        isdefined(M, x) && return getfield(M, x)
    end
    return nothing
end

_resolve_predicate(pred::Symbol) = _resolve_name(pred)

# guards given as expressions (e.g. `!=(-1)`) are evaluated once and cached,
# keyed by the identity of the expression. A failure is not cached, so a
# guard defined later will be found.
const PREDICATE_FN_CACHE = IdDict{Expr, Any}()

function _resolve_predicate(pred::Expr)
    haskey(PREDICATE_FN_CACHE, pred) && return PREDICATE_FN_CACHE[pred]
    pred_fn = try
        Core.eval(Main, pred)
    catch err
        return nothing
    end
    PREDICATE_FN_CACHE[pred] = pred_fn
    return pred_fn
end

function _evalguard(pred, data)
    # look up in the latest world, as the guard may be defined after this
    # code was compiled
    pred_fn = Base.invokelatest(_resolve_predicate, pred)
    pred_fn === nothing && return false
    try
        Base.invokelatest(pred_fn, _unwrap_const(data)) === true
    catch err
        false
    end
end


# create a term for a pattern (pterm) or a subject (sterm)
# the former is only for expressions
# the latter might involve a symbolic type
function pterm(op::Union{Expr,Symbol}, args; elide=true)
    if elide && length(args) == 1 && op ∈(:+, :*, :^, :/)
        return only(args)
    else
        return maketerm(Expr, :call, (op, args...), nothing)
    end
end

# symbolic type

# to pass to maketerm (sterm)
# Might want to do something like
# AssociativeCommutativePatternMatching.symtype(::SymEngine.Basic) = SymEngine.Basic
symtype(::Real) = Expr
symtype(::Symbol) = Expr
symtype(::Expr) = Expr
symtype(::T) where T = T

# create a term on the subject side
function sterm(op, args)
    # numbers (e.g. 2 in 2x) may not identify the symbolic type
    i = findfirst(a -> !isa(_unwrap_const(a), Real), args)
    S = symtype(args[something(i, firstindex(args))])
    sterm(S, op, args)
end

# construct term of abstract type S from op and args
function sterm(S, op, args)
    if S == Expr
        !isa(op, Union{Expr, Symbol}) && (op = nameof(op))
        return pterm(op, args)
    end

    if isa(op, Symbol)
        for M ∈ (@__MODULE__, Main, Base)
            if isdefined(M, op)
                op = getfield(M, op)
                break
            end
        end
        isa(op, Symbol) && (op = Core.eval(Main, op))
    elseif isa(op, Expr)
        for M ∈ (@__MODULE__, Main, Base)
            try
                op = Core.eval(M, op)
                break
            catch err
                # fall through if the expression is not yet resolvable in this module
            end
        end
    end

    maketerm(S, op, args, nothing)
end


# invert an expr to regularize a/b --> a*b^{-1}
# a rule `u / v` as the factors `u` (unless 1) and `vᵢ^-1` for each factor `vᵢ` of `v`
function _rule_as_powers(rule)
    u, v = arguments(rule)
    vs = _is_operation(*)(v) ? arguments(v) : (v,)
    vs′ = map(_invert_expr, vs)
    u == 1 ? vs′ : Any[u, vs′...]
end

# a subject `u / v` likewise: the factors of `u` (dropping a 1), and for each
# factor of `v` its inverse, `f^-1`, or `b^(-k)` for a power `b^k`
_factors(x) = iscall(x) && Symbol(operation(x)) === :* ? arguments(x) : (x,)
function _invert_data(f)
    if iscall(f) && Symbol(operation(f)) === :^
        b, k = arguments(f)
        return sterm(^, (b, sterm(-, (k,))))
    end
    sterm(^, (f, -1))
end
function _data_as_powers(data)
    u, v = arguments(data)
    Any[(f for f in _factors(u) if !_isone(_unwrap_const(f)))..., map(_invert_data, _factors(v))...]
end

function _invert_expr(pat)
    if isa(pat, Integer)
        return pterm(:^, (pat, -1.0))
    elseif is_operation(:(//))(pat)
        u,v = arguments(pat)
        u′ = isa(u, Number) ? -u : pterm(:*, (u,-1))
        return pterm(:(//), (u′, v))
    else
        return pterm(:^, (pat, -1))
    end
end

# --- basic total order, can override for other types
<ₑ(x::Symbol, y::Symbol) = x < y
<ₑ(x::Any, y::Any) = <ₑ(Symbol(x), Symbol(y))


# ----- predicates
_is_rational(x) = isa(_unwrap_const(x), Rational)

# can override, say with :Symbol
iscommutative(op) = op ∈ (:+, :*, +, *)
isassociative(op) = op ∈ (:+, :*, +, *)

isassociative(::typeof(+)) = true
isassociative(::typeof(*)) = true

iscommutative(::typeof(+)) = true
iscommutative(::typeof(*)) = true

# check for wildcard variables
is_𝑋(x::Any) = false
has_𝑋(x::Any) = false
is_slot(x::Any) = false
is_segment(x::Any) = false
is_plus(x::Any) = false
is_op(x::Any) = false
is_defslot(x::Any) = false

# Expr
is_𝑋(x::Expr) = (iscall(x) && operation(x) === :(~))  ||
    ((!iscall(x) && isexpr(x)) && head(x) != :... && is_𝑋(first(x.args)))

function has_𝑋(x::Expr)
    is_𝑋(x) && return true
    !iscall(x) && return false
    is_𝑋(operation(x)) && return true
    any(has_𝑋, arguments(x))
end

function is_slot(x::Expr)
    is_𝑋(x) || return false
    _, x = x.args
    iscall(x) && return false
    return true
end

function is_segment(x::Expr)
    is_𝑋(x) || return false # first is ~
    h,x = x.args
    is_𝑋(h) && return false # an op
    is_𝑋(x) || return false # second is ~
    _, x = x.args
    is_𝑋(x) && return false
    return true
end

# ~~~x (1 or more)
function is_plus(x::Expr)
    is_𝑋(x) || return false
    _,x = x.args
    is_𝑋(x) || return false
    _,x = x.args
    is_𝑋(x) || return false
    return true
end

# (~G)(~x)
function is_op(x::Expr)
    is_𝑋(x) && iscall(x) && is_𝑋(operation(x))
end

function is_defslot(x::Expr)

    is_𝑋(x) || return false
    _, arg = x.args
    is_operation(:(!))(arg) && return true

    return false
end

has_defslot(::Any) = false
function has_defslot(x::Expr)
    return is_defslot(x) ||
        (is_operation(:^)(x) && is_defslot(last(arguments(x))))
end


## ------
const defslot_op_map = Dict(:+ => 0, :* => 1, :^ => 1, :/ => 1)

# return symbol holding variable name
varname(x::Symbol) = x
function varname(x::Expr)
    iscall(x) && !(x.args[1] ∈ (:~, :!)) && throw(ArgumentError("$x is not a wild card variable"))
    if x.args[1] ∈ (:~, :!)
        varname(x.args[2])
    else
        varname(x.args[1])
    end
end

## -- work with guards
# Does wildcard have a predicate?
has_predicate(::Any)::Bool = false
has_predicate(x::Symbol)::Bool = false
function has_predicate(x::Expr)::Bool
    if x.args[1] ∈ (:~, :!)
        has_predicate(x.args[2])
    else
        length(x.args) == 2 && x.head==:(::)
    end
end

# get_predicate. Assumes user has called `has_predicate` and got TRUE
get_predicate(x::Symbol) = :nothing
function get_predicate(x::Expr)
    if x.args[1] ∈ (:~, :!)
        get_predicate(x.args[2])
    else
        x.args[2]
    end
end
