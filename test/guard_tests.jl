## Guards defined outside of `Main`, as a package using this one would

module GuardsA
    using CommutativePatternMatching

    isfoo(u) = string(u) == "a"
    ispred(u) = string(u) == "a" # also defined in GuardsB and Main

    named = @pattern sin(~x::isfoo)
    lambda = @pattern sin(~x::(u -> isfoo(u)))
    segment = @pattern ~x + ~~y::(u -> u isa Tuple && all(isfoo, u))
    same_name = @pattern sin(~x::ispred)
    k = 2
    interpolated = @pattern (~x)^$k
    base_guard = @pattern (~x)^(~n::(!=(-1)))
    no_slot = @pattern f(x::Int)

    # by name, the package looks in Main and Base, not here
    quoted = :(sin(~x::isfoo))
end

module GuardsB
    using CommutativePatternMatching
    ispred(u) = string(u) == "b"
    same_name = @pattern sin(~x::ispred)
end

ispred(u) = string(u) == "c"

function guard_tests()
    @testset "@pattern" begin
        # guards are spliced in as values; other `::` are left alone
        @test CPM.get_predicate(GuardsA.named.args[2]) === GuardsA.isfoo
        @test GuardsA.no_slot == :(f(x::Int))
        @test GuardsA.interpolated == :((~x)^2)
    end

    @testset "guards from another module ($B)" for B ∈ BACKENDS
        S = B.build
        a, x = S(:a), S(:x)

        @test binds(matchone(GuardsA.named, S(:(sin(a)))), :x => a)
        @test matchone(GuardsA.named, S(:(sin(b)))) === nothing

        @test binds(matchone(GuardsA.lambda, S(:(sin(a)))), :x => a)
        @test matchone(GuardsA.lambda, S(:(sin(b)))) === nothing

        # segment guards are passed the tuple
        σs = eachm(GuardsA.segment, S(:(x + a)))
        @test has_match(σs, :x => x, :y => (a,))
        @test !has_match(σs, :x => a, :y => (x,))

        # a predicate of the same name in each module
        @test binds(matchone(GuardsA.same_name, S(:(sin(a)))), :x => a)
        @test matchone(GuardsA.same_name, S(:(sin(c)))) === nothing
        @test binds(matchone(GuardsB.same_name, S(:(sin(b)))), :x => S(:b))
        @test matchone(GuardsB.same_name, S(:(sin(a)))) === nothing
        # quoted, the name is found in Main
        @test binds(matchone(:(sin(~x::ispred)), S(:(sin(c)))), :x => S(:c))

        # a name which can not be found fails the match; it does not throw
        @test matchone(GuardsA.quoted, S(:(sin(a)))) === nothing
        @test matchone(:(sin(~x::(u -> isfoo(u)))), S(:(sin(a)))) === nothing

        @test binds(matchone(GuardsA.interpolated, S(:(x^2))), :x => x)

        @test binds(matchone(GuardsA.base_guard, S(:(x^2))), :x => x, :n => 2)
        @test matchone(GuardsA.base_guard, S(:(x^(-1)))) === nothing
        @test binds(matchone(:((~x)^(~n::(!=(-1)))), S(:(x^2))), :x => x, :n => 2)
    end

    @testset "lookup by name" begin
        # a failed lookup is not remembered
        pat = :(sin(~x::_cpm_defined_later))
        @test matchone(pat, :(sin(a))) === nothing
        @eval Main _cpm_defined_later(u) = true
        @test binds(matchone(pat, :(sin(a))), :x => :a)

        pat = :(sin(~x::(_cpm_also_later ∘ identity)))
        @test matchone(pat, :(sin(a))) === nothing
        @eval Main _cpm_also_later(u) = true
        @test binds(matchone(pat, :(sin(a))), :x => :a)

        # a guard which errors, or does not return `true`, fails
        @test matchone(:(sin(~x::(u -> error("oops")))), :(sin(a))) === nothing
        @test matchone(:(sin(~x::(u -> missing))), :(sin(a))) === nothing
    end
end
