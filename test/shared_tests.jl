## Tests run against every backend.
##
## Subjects are written as `Expr` and built by the backend, so they should
## be chosen to survive the canonicalization a symbolic type may do (e.g.
## SymEngine rewrites `a - b` as `a + (-1)*b`). Backend-specific behavior
## goes in `backend_tests.jl`.

function shared_tests(B::Backend)
    S = B.build
    a, b, c, x = S(:a), S(:b), S(:c), S(:x)

    @testset "single slot" begin
        σ = matchone(:(~x), S(:(a + b + c)))
        @test binds(σ, :x => S(:(a + b + c)))

        @test binds(matchone(:(sin(~x)), S(:(sin(2x)))), :x => S(:(2x)))
        @test binds(matchone(:((~x)^2), S(:((x + a)^2))), :x => S(:(x + a)))
        @test binds(matchone(:(exp(~x)), S(:(exp(x)))), :x => x)
        @test binds(matchone(:(sqrt(~x)), S(:(sqrt(x)))), :x => x)

        # wrong head
        @test isempty(eachm(:(log(~x)), S(:(sin(x)))))
        @test matchone(:(sin(~x)), S(:(sin(x)^2))) === nothing
    end

    @testset "repeated slot" begin
        @test binds(matchone(:((~x)^(~x)), S(:((x + a)^(x + a)))), :x => S(:(x + a)))
        @test matchone(:((~x)^(~x)), S(:((x + a)^(x + b)))) === nothing

        @test binds(matchone(:(sin(~x) * cos(~x)), S(:(sin(a) * cos(a)))), :x => a)
        @test matchone(:(sin(~x) * cos(~x)), S(:(sin(a) * cos(b)))) === nothing
    end

    @testset "literal terms in pattern" begin
        # numeric literals
        @test binds(matchone(:(~x + 2), S(:(x + 2))), :x => x)
        @test binds(matchone(:(2 * ~x), S(:(2 * x))), :x => x)
        @test matchone(:(~x + 3), S(:(x + 2))) === nothing

        # a symbol in the pattern matches a variable of the same name
        @test binds(matchone(:(sin(x)), S(:(sin(x)))))
        @test binds(matchone(:(x + sin(~y)), S(:(x + sin(a)))), :y => a)
        @test matchone(:(sin(y)), S(:(sin(x)))) === nothing
        @test matchone(:(sin(x)), S(:(sin(2)))) === nothing
    end

    @testset "commutative" begin
        @test binds(matchone(:(~x * sin(~y)), S(:(x * sin(x)))), :x => x, :y => x)
        @test binds(matchone(:(sin(~y) * ~x), S(:(x * sin(x)))), :x => x, :y => x)

        # both assignments are found
        @test (σs = eachm(:(~x * ~y), S(:(a * b)));
               length(σs) == 2 && has_match(σs, :x => a, :y => b) &&
                   has_match(σs, :x => b, :y => a))
        @test (σs = eachm(:(~x * ~y), S(:(2x)));
               length(σs) == 2 && has_match(σs, :x => 2, :y => x))

        @test binds(matchone(:(sin(~x) + cos(~y)), S(:(cos(a) + sin(b)))), :x => b, :y => a)
    end

    @testset "number of matches ($op)" for op ∈ (:+, :*)
        # see the table in src/rule2a.jl. Matching is commutative, not
        # associative, and multiple segments are filled greedily.
        sub = S(Expr(:call, op, :a, :b, :c))
        pat(u, v) = Expr(:call, op, u, v)

        @test length(eachm(:(~x), sub)) == 1
        @test length(eachm(pat(:(~x), :(~y)), sub)) == 0

        σs = eachm(pat(:(~x), :(~~y)), sub)
        @test length(σs) == 4
        @test binds_keys(σs, :x, :y)
        @test has_match(σs, :x => sub, :y => ())
        @test has_match(σs, :x => a, :y => (b, c))

        σs = eachm(pat(:(~x), :(~~~y)), sub)
        @test length(σs) == 3
        @test all(σ -> !isempty(σ[:y]), σs)
        @test has_match(σs, :x => c, :y => (a, b))

        σs = eachm(pat(:(~~x), :(~~y)), sub)
        @test length(σs) == 1
        @test binds_keys(σs, :x, :y)
        @test sum(σ -> length(σ[:x]) + length(σ[:y]), σs) == 3

        σs = eachm(pat(:(~~~x), :(~~~y)), sub)
        @test length(σs) == 1
        @test all(σ -> !isempty(σ[:x]) && !isempty(σ[:y]), σs)
    end

    @testset "multiple segments" begin
        sub = S(:(a + b + c + x^2))
        for pat ∈ (:(~~x + ~~y + ~~w), :(~~~x + ~~~y + ~~~w), :(~x + ~~y + ~~w))
            σs = eachm(pat, sub)
            @test !isempty(σs)
            @test binds_keys(σs, :w, :x, :y)
        end
        # not enough terms for three plus segments
        @test isempty(eachm(:(~~~x + ~~~y + ~~~w), S(:(a + b))))
    end

    @testset "lone segment" begin
        # a lone segment should bind to the tuple of arguments
        @test binds(matchone(:(+(~~a)), S(:(a + b + c))), :a => (a, b, c))
        @test binds(matchone(:(*(~~~a)), S(:(a * b * c))), :a => (a, b, c))
    end

    @testset "wrap_commutative" begin
        w = (; wrap_commutative = true)

        # ~~~ segments of a commutative operation bind to a term
        σs = eachm(:(~x + ~~~y), S(:(a + b + c)); w...)
        @test length(σs) == 3
        @test has_match(σs, :x => a, :y => S(:(b + c)))
        @test has_match(σs, :x => c, :y => S(:(a + b)))

        σs = eachm(:(~x * ~~~y), S(:(a * b * c)); w...)
        @test has_match(σs, :x => a, :y => S(:(b * c)))

        @test binds(matchone(:(+(~~~y)), S(:(a + b + c)); w...), :y => S(:(a + b + c)))
        # nested within another call
        @test has_match(eachm(:(sin(~x + ~~~y)), S(:(sin(a + b + c))); w...),
                        :x => a, :y => S(:(b + c)))
        # a single value is not wrapped
        @test binds(matchone(:(~~~x + ~~~y), S(:(a + b)); w...), :x => a, :y => b) ||
            binds(matchone(:(~~~x + ~~~y), S(:(a + b)); w...), :x => b, :y => a)

        # ~~ segments are wrapped too; an empty match stays ()
        σs = eachm(:(~x + ~~y), S(:(a + b + c)); w...)
        @test length(σs) == 4
        @test has_match(σs, :x => a, :y => S(:(b + c)))
        @test has_match(σs, :x => S(:(a + b + c)), :y => ())
        @test binds(matchone(:(*(~~y)), S(:(a * b * c)); w...), :y => S(:(a * b * c)))

        # repeated segments compare the wrapped terms
        @test binds(matchone(:(sin(+(~~~y)) + cos(+(~~~y))), S(:(sin(a + b) + cos(a + b))); w...),
                    :y => S(:(a + b)))
        @test matchone(:(sin(+(~~~y)) + cos(+(~~~y))), S(:(sin(a + b) + cos(a + c))); w...) === nothing

        # a guard on a segment is passed the tuple, not the wrapped term
        σs = eachm(:(~x + ~~~y::(u -> u isa Tuple && length(u) == 2)), S(:(a + b + c)); w...)
        @test length(σs) == 3
        @test has_match(σs, :x => a, :y => S(:(b + c)))
        @test isempty(eachm(:(~x + ~~~y::(u -> !isa(u, Tuple))), S(:(a + b + c)); w...))

        # default is a tuple
        @test has_match(eachm(:(~x + ~~~y), S(:(a + b + c))), :x => a, :y => (b, c))
    end

    @testset "segment guards ($(kw))" for kw ∈ ((;), (; wrap_commutative = true))
        sub = S(:(a + b + c))
        istup(n) = :(u -> u isa Tuple && length(u) == $n)

        # lone segment
        @test binds(matchone(:(+(~~y::$(istup(3)))), sub; kw...), :y => (kw == (;) ? (a, b, c) : sub))
        @test matchone(:(+(~~y::$(istup(2)))), sub; kw...) === nothing

        # with another argument
        @test length(eachm(:(~x + ~~y::$(istup(2))), sub; kw...)) == 3
        @test length(eachm(:(~x + ~~y::$(istup(0))), sub; kw...)) ≥ 1
        @test all(σ -> σ[:y] == (), eachm(:(~x + ~~y::$(istup(0))), sub; kw...))
        @test isempty(eachm(:(~x + ~~y::$(istup(4))), sub; kw...))

        # segments only, filled greedily
        @test binds(matchone(:(~~x + ~~y::$(istup(0))), sub; kw...),
                    :x => (kw == (;) ? (a, b, c) : sub), :y => ())
        @test matchone(:(~~x + ~~y::$(istup(1))), sub; kw...) === nothing
    end

    @testset "default slots" begin
        σ = matchone(:(~x + ~!y), S(:(a + b + c)))
        @test binds(σ, :x => S(:(a + b + c)), :y => 0)

        @test binds(matchone(:(~!a * (~x)^(~n)), S(:(x^2))), :a => 1, :x => x, :n => 2)
        @test binds(matchone(:(~!a * (~x)^(~n)), S(:(3 * x^2))), :a => 3, :x => x, :n => 2)

        pat = :((~!a) * sin(~x)^2 + (~!a) * cos(~x)^2 + ~!b)
        σ = matchone(pat, S(:(sin(2x)^2 + cos(2x)^2)))
        @test binds(σ, :a => 1, :b => 0, :x => S(:(2x)))
    end

    @testset "predicates" begin
        pat = :((~x)^(~n::iseven))
        @test binds(matchone(pat, S(:(x^2))), :x => x, :n => 2)
        @test matchone(pat, S(:(x^3))) === nothing

        # a predicate which errors is treated as false
        @test matchone(:(sin(~x::iseven)), S(:(sin(x)))) === nothing

        # anonymous predicates
        @test binds(matchone(:(~x::(u -> u isa Integer)), 3), :x => 3)
        @test matchone(:(sin(~x::(u -> u isa Integer))), S(:(sin(x)))) === nothing
    end

    @testset "operation slot" begin
        σ = matchone(:((~F)(~x)), S(:(sin(x))))
        @test opname(σ[:F]) == :sin
        @test same(σ[:x], x)

        σ = matchone(:((~F)(~x, ~y)), S(:(a^b)))
        @test opname(σ[:F]) == :^
        @test same(σ[:x], a) && same(σ[:y], b)
    end

    @testset "alternate forms of powers" begin
        @test binds(matchone(:(ℯ^(~n)), S(:(exp(x)))), :n => x)
        @test binds(matchone(:((~x)^(~n)), S(:(1 / x))), :x => x, :n => -1)
        @test binds(matchone(:((~x)^(~n)), S(:(sqrt(x)))), :x => x, :n => 1 // 2)
        @test binds(matchone(:(~a / ~b), S(:(a / b))), :a => a, :b => b)
    end

    @testset "_match" begin
        @test binds(CPM._match(:(sin(~x)), S(:(sin(a)))), :x => a)
        @test_throws Exception CPM._match(:(sin(~x)), S(:(cos(a))))
    end
end
