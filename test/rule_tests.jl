## Rules written outside of `Main`, as a package using this one would

module RulesA
    using CommutativePatternMatching

    double(u) = 2u
    g(u) = 2u # also defined in RulesB
    k = 3

    r_fn  = @rule sin(~x) => double(~x)
    r_int = @rule (~x)^(~n::isinteger) => (~x)^(~n + 1) / (~n + 1)
    r_def = @rule ~!a * (~x)^(~n) => ~a * ~n * (~x)^(~n - 1)
    r_op  = @rule (~F)(~x) => (~F)(2 * ~x)
    r_k   = @rule (~x)^2 => (~x)^$k
    r_seg = @rule ~x + ~~y => ~x * length(~~y)
    r_g   = @rule sin(~x::(u -> string(u) == "a")) => g(~x)
    r_wrap = @rule ~x + ~~~y => ~~~y
end

module RulesB
    using CommutativePatternMatching
    g(u) = 3u
    r_g = @rule sin(~x) => g(~x)
end

function rule_tests()
    @testset "@rule ($B)" for B ∈ BACKENDS
        S = B.build
        isExpr = B.name == "Expr"
        a, b, c, x = S(:a), S(:b), S(:c), S(:x)
        expect(ex, val) = expected(B, ex, val)

        # functions and variables of the calling module
        @test same(RulesA.r_fn(S(:(sin(a)))), expect(:(double(a)), :(2a)))
        @test RulesA.r_fn(S(:(cos(a)))) === nothing
        @test same(RulesA.r_k(S(:(x^2))), S(:(x^3)))
        @test same(RulesA.r_g(S(:(sin(a)))), expect(:(g(a)), :(2a)))
        @test RulesA.r_g(S(:(sin(b)))) === nothing
        @test same(RulesB.r_g(S(:(sin(a)))), expect(:(g(a)), :(3a)))

        @test same(RulesA.r_int(S(:(x^2))), expect(:(x^(2 + 1) / (2 + 1)), :(x^3 / 3)))
        @test same(RulesA.r_def(S(:(3 * x^2))), expect(:(3 * 2 * x^(2 - 1)), :(6x)))
        @test same(RulesA.r_def(S(:(x^2))), expect(:(1 * 2 * x^(2 - 1)), :(2x)))
        @test same(RulesA.r_op(S(:(sin(a)))), S(:(sin(2a))))

        if !isExpr
            # rhs is Julia code, run on the matched values
            out = RulesA.r_seg(S(:(a + b + c)))
            @test any(u -> same(out, S(u)), (:(2a), :(2b), :(2c)))

            # a segment is replaced by its tuple
            @test RulesA.r_wrap(S(:(a + b + c))) isa Tuple
        end
    end

    @testset "_rewrite ($B)" for B ∈ BACKENDS
        S = B.build
        isExpr = B.name == "Expr"
        a, x = S(:a), S(:x)

        σ = CPM._match(:(sin(~x)), S(:(sin(a))))
        @test same(CPM._rewrite(σ, :(sin(~x)^2)), S(:(sin(a)^2)))
        @test same(CPM._rewrite(σ, :(~x + 1)), S(:(a + 1)))
        @test same(CPM._rewrite(σ, :(π * ~x)), isExpr ? :(π * a) : π * a)
        @test same(CPM._rewrite(σ, :(~x)), a)
        @test same(CPM._rewrite(σ, u -> u[:x]), a)
        # the subject type may be given; with `Expr`, nothing is evaluated
        out = CPM._rewrite(σ, :(sin(~x)), Expr)
        @test out isa Expr && out.args[1] == :sin && same(out.args[2], a)

        # a name from another module is not found; a spliced function is
        if isExpr
            @test CPM._rewrite(σ, :(double(~x))) == :(double(a))
        else
            @test_throws ArgumentError CPM._rewrite(σ, :(double(~x)))
        end
        @test same(CPM._rewrite(σ, :($(RulesA.double)(~x))), expected(B, :(double(a)), :(2a)))

        # operation slots and powers are treated like any other call
        σ = CPM._match(:((~F)(~x)), S(:(sin(a))))
        @test same(CPM._rewrite(σ, :((~F)(~x + 1))), S(:(sin(a + 1))))
        σ = CPM._match(:((~x)^(~n)), S(:(x^2)))
        out = CPM._rewrite(σ, :((~x)^(~n + 1)))
        @test same(out, expected(B, :(x^(2 + 1)), :(x^3)))
        @test (out isa Expr) == isExpr
    end
end

# an `Expr` subject is rewritten by substitution, others are evaluated
expected(B, ex, val) = B.name == "Expr" ? ex : B.build(val)
