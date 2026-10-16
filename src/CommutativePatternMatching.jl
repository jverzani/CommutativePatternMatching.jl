module CommutativePatternMatching

export @pattern, @rule

include("utils.jl")
include("rule2a.jl")
include("pattern.jl")
include("rule.jl")


# interface to be extended by a package
function _eachmatch(pat, sub; kwargs...)
    check_expr_r(sub, pat; kwargs...)
end

function _match(pat, sub; kwargs...)
    σs = _eachmatch(pat, sub; kwargs...)
    isempty(σs) && return nothing
    first(σs)
end


end
