module CommutativePatternMatching

include("utils.jl")
include("rule2a.jl")


# interface to be extended by a package
function _eachmatch(pat, sub; kwargs...)
    check_expr_r(sub, pat; kwargs...)
end

function _match(pat, sub; kwargs...)
    first(_eachmatch(pat, sub; kwargs...))
end

end
