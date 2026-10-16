using CommutativePatternMatching
using Test

const CPM = CommutativePatternMatching

include("backends.jl")
include("helpers.jl")
include("shared_tests.jl")
include("backend_tests.jl")
include("guard_tests.jl")

@testset "CommutativePatternMatching.jl" begin
    @testset "$B" for B ∈ BACKENDS
        shared_tests(B)
    end
    backend_tests()
    guard_tests()
end
