module CommutativePatternMatching

export @pattern, @rule

include("utils.jl")
include("rule2a.jl")
include("pattern.jl")
include("rule.jl")


# interface to be extended by a package
function _eachmatch(pat, sub)
    check_expr_r(sub, pat)
end

function _match(pat, sub)
    σs = _eachmatch(pat, sub)
    isempty(σs) && return nothing
    first(σs)
end


end
