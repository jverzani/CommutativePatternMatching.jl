## Helpers for comparing matches in a backend-independent way

eachm(pat, sub; kwargs...) = CPM._eachmatch(pat, sub; kwargs...)

# first match or `nothing`
function matchone(pat, sub; kwargs...)
    σs = eachm(pat, sub; kwargs...)
    isempty(σs) ? nothing : first(σs)
end

# compare a matched value with an expected one. Symbolic types differ in
# how `==` behaves (it may return a symbolic value), so check `isequal`
# first, then values after unwrapping constants.
same(a, b) = isequal(a, b) ||
    (a == b) === true ||
    isequal(CPM.unwrap_const(a), CPM.unwrap_const(b))

# segment variables bind to tuples; the order of the arguments depends on
# how the backend stores commutative arguments, so compare as multisets
function same(a::Tuple, b::Tuple)
    length(a) == length(b) || return false
    used = falses(length(b))
    for u ∈ a
        j = findfirst(j -> !used[j] && same(u, b[j]), eachindex(b))
        j === nothing && return false
        used[j] = true
    end
    true
end
same(a::Tuple, b) = false
same(a, b::Tuple) = false

# does σ bind exactly the pairs in `kvs`?
function binds(σ, kvs::Pair...)
    σ === nothing && return false
    length(σ) == length(kvs) || return false
    all(haskey(σ, k) && same(σ[k], v) for (k, v) ∈ kvs)
end

# is there some match in σs binding exactly `kvs`?
has_match(σs, kvs::Pair...) = any(σ -> binds(σ, kvs...), σs)

# all matches bind the same set of keys
binds_keys(σs, ks...) = all(σ -> issetequal(keys(σ), ks), σs)

# operations may come back as a function (sin) or symbol (:sin)
opname(op) = Symbol(op)
