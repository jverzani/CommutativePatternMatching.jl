## Backend-specific tests: behavior that depends on how a subject is stored

function backend_tests()
    @testset "Expr (no canonicalization)" begin
        # terms are not combined or rewritten
        @test binds(matchone(:(~x + ~x), :(a + a)), :x => :a)
        @test matchone(:(~x + ~x), :(a + b)) === nothing
        @test binds(matchone(:(~x - ~y), :(a - b)), :x => :a, :y => :b)

        # no associativity: a nested sum has two arguments
        sub = Expr(:call, :+, :(a + b), :c)
        σs = eachm(:(~x + ~y), sub)
        @test length(σs) == 2
        @test has_match(σs, :x => :(a + b), :y => :c)

        # literal symbols in a pattern
        @test binds(matchone(:(x * sin(~y)), :(x * sin(a))), :y => :a)
        @test binds(matchone(:(f(~x)), :(f(a))), :x => :a)
        @test binds(matchone(:((~F)(~x)), :(f(a))), :F => :f, :x => :a)

        # segments in a non-commutative operation keep their order
        σ = matchone(:(f(~x, ~~y)), :(f(a, b, c)))
        @test σ[:x] == :a && collect(σ[:y]) == [:b, :c]
        # segments bind to tuples, as in the commutative case
        @test σ[:y] isa Tuple
        # with no other arguments, segments are filled greedily
        σs = eachm(:(f(~~x, ~~y)), :(f(a, b, c)))
        @test length(σs) == 1
        @test all(σ -> [σ[:x]..., σ[:y]...] == [:a, :b, :c], σs)
        @test isempty(eachm(:(f(~~~x, ~y, ~~~z)), :(f(a, b))))

        # guards on segments of a non-commutative operation
        @test binds(matchone(:(f(~x, ~~y::(u -> length(u) == 2))), :(f(a, b, c))),
                    :x => :a, :y => (:b, :c))
        @test matchone(:(f(~x, ~~y::(u -> length(u) == 1))), :(f(a, b, c))) === nothing
        @test binds(matchone(:((~F)(~~y::(u -> length(u) == 3))), :(f(a, b, c))),
                    :F => :f, :y => (:a, :b, :c))
        @test matchone(:((~F)(~~y::(u -> length(u) == 2))), :(f(a, b, c))) === nothing

        # wrap_commutative only applies to commutative operations
        σ = matchone(:(f(~x, ~~~y)), :(f(a, b, c)); wrap_commutative = true)
        @test σ[:y] == (:b, :c)
    end

    @testset "$(B.name) (canonicalizing)" for B ∈ filter(B -> B.canonicalizes, BACKENDS)
        S = B.build

        # a + a is stored as 2a
        @test matchone(:(~x + ~x), S(:(a + a))) === nothing
        @test binds(matchone(:(~n * ~x), S(:(a + a))), :n => 2, :x => S(:a))

        # a - b is stored as a sum
        @test matchone(:(~x - ~y), S(:(a - b))) === nothing
        @test has_match(eachm(:(~x + ~y), S(:(a - b))), :x => S(:a), :y => S(:(-b)))
    end
end
