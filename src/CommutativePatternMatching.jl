module CommutativePatternMatching

export @pattern, @rule

include("utils.jl")
include("rule2a.jl")
include("pattern.jl")
include("rule.jl")


# interface to be extended by a package
"""
    _eachmatch(pat, sub)

Return a vector of the matches of the pattern `pat` to the subject `sub`,
each a dictionary from wildcard names to their values. The vector is
empty if there is no match.
"""
function _eachmatch(pat, sub)
    check_expr_r(sub, pat)
end

"""
    _match(pat, sub)

Return the first match of the pattern `pat` to the subject `sub`, or
`nothing` if there is no match. See [`_eachmatch`](@ref).
"""
function _match(pat, sub)
    σs = _eachmatch(pat, sub)
    isempty(σs) && return nothing
    first(σs)
end


end
