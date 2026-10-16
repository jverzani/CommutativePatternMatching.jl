using TermInterface
using Combinatorics

## ---- note -----
#=

This code is derived from, rule2.jl at https://github.com/JuliaSymbolics/SymbolicIntegration.jl/blob/main/src/methods/rule_based/rule2.jl

There are some modifications for commutivity following ideas from Krebber, which are also implemented in AssociativeCommutativePatternMatching.jl.

Using Krebber's language we have

* substitution (match) is σ a map between pattern terms and subject terms such that a substitution of the pattern terms returns the subject (σ(t) = s). This uses an ImmutableDict{Symbol, Any} to store a match or a partial match

* An empty substitution is partial match and a possible match, when there are not wild cards

* A sentinel is used to indicate *no possible substitution* and is here a FAIL_DICT

* A set of matches (`θ` or `σs`) allows for different matches due to commutivity/associativity. This set is empty if there are no matches. We use a vector to store this: MatchDict[MatchDict()] is an initial set with a initial partial match specified.


A pattern to match against has wildcards. We have:

* ~x: match one argument (a slot variable)
* ~!x: match one argument, possibly through a default (a defslot)
* ~~x: match 0, 1, or more arguments (returns a tuple); A segment (star) variable (`is_segment`)
* ~~~x: match 1 or more arguments (returns a tuple); A plus variable (`is_plus`)

With `wrap_commutative=true`, a segment of either kind within a commutative operation binds to a term (`a + b`) rather than a tuple (`(a, b)`); an empty match is still `()`.

A pattern can only have one wildcard of a given name (no ~x + ~~x, say).

# test cases -- AssociativeCommutativePatternMatching uses associativity in its considerations (2,4) and full enumeration when there are multiple segments (6, 7). The Rule1 (from SymbolicIntegration) doesn't do segments right (in my mind)

                                      # ACPM  | Rule2 | Rule1 (match only)
1. eachmatch(:(~x), a + b + c)        # 1 | 1 | yes
2. eachmatch(:(~x + ~y), a + b + c)   # 6 | 0 | no (not associative matching!)
3. eachmatch(:(~x + ~!y), a + b + c)  # 6 | 1 | yes
4. eachmatch(:(~x + ~~y), a+b+c)      # 7⁺| 4 | no # ⁺ ~x accts like ~~~x
5. eachmatch(:(~x + ~~~y), a+b+c)     # 6 | 3 | not
6. eachmatch(:(~~x + ~~y), a+b+c)     # 8 | 1 | no
7. eachmatch(:(~~~x + ~~~y), a+b+c)   # 6 | 1 | no

=#

## ----- rule2.jl -------

# This is derived from https://github.com/JuliaSymbolics/SymbolicIntegration.jl/tree/main/src/methods/rule_based/rule2.jl
# Licensed under MIT with Copyright (c) 2022 Harald Hofstätter, Mattia Micheletta Merlin, Chris Rackauckas, and other contributors


# TODO ~a*(~b*~c) currently will not match a*b*c . a fix is possible

# for when the rule contains a symbol, like ℯ, or a literal number
function check_expr_r(data, rule::Real, σs::𝑀; kwargs...)::𝑀
    eq_expr(rule, data) && return σs
    return NO_MATCH
end

function check_expr_r(data, rule::Symbol, σs::𝑀; kwargs...)::𝑀
    eq_expr(data, rule) && return σs
    return NO_MATCH
end

# main function
# wrap_commutative = true binds a segment (`~~x` or `~~~x`) within a
# commutative operation to a term, e.g. `a + b`, rather than a tuple, e.g.
# `(a, b)`. An empty match is still `()`.
check_expr_r(data, rule::Expr; wrap_commutative=false)::𝑀 =
    check_expr_r(data, rule, [MatchDict()]; wrap_commutative)

function check_expr_r(data, rule::Expr, σs::𝑀; wrap_commutative=false)::𝑀
    # @show :cer, data, rule
    if !iscall(rule)
        #@show :what_is, rule
    end

    opᵣ = operation(rule)

    if is_𝑋(opᵣ)
        # @show :is_𝑋, data, rule
        # peel off hope for single argument!
        !iscall(data) && return MatchDict[] # XXX <---

        value = iscall(data) ? operation(data) : identity
        σ′ = match_dict(varname(opᵣ) => value)
        σs = union_merge(σs, σ′)
        arg_data, arg_rule = arguments(data), arguments(rule)
        if length(arg_data) > 1
            if iscommutative(opᵣ)
                return check_commutative(arg_data, arg_rule, σs; wrap_commutative)
            else
                return ceoaa(arg_data, arg_rule, σs; wrap_commutative)
            end
        else
            data, rule = (isempty(arg_data) ? arg_data : only(arg_data)), only(arg_rule)
        end
    end

    # rule is a single variable
    if is_𝑋(rule)
        return just_variable(data, rule, σs)
    end

    # if there is a deflsot in the arguments
    i = findfirst(is_defslot, arguments(rule))
    if i !== nothing
        return has_defslot(i, data, rule, σs; wrap_commutative)
    end

    # if there is a segment in the (only) argument
    if (iscall(rule) &&
        length(arguments(rule)) == 1 &&
#        is_segment(first(arguments(rule)))
        (is_segment(first(arguments(rule))) ||
         is_plus(first(arguments(rule))))
        )
        # @show :hi
        return only_argument_is_segment(data, rule, σs; wrap_commutative)
    end

    # rule is a normal call, check operation and arguments
    if (operation(rule) == ://) && _is_rational(data)
        return has_rational(data, rule, σs)
    end

    !iscall(data) && return NO_MATCH

    # check opᵣ for special cases where
    # powers are represented differently
    opᵣ, 𝑜𝑝ₛ = operation(rule), Symbol(operation(data))

    if opᵣ ∈ (:^, :sqrt, :exp) ||
        (opᵣ, 𝑜𝑝ₛ) ∈ ((:/,:^),
                      (:/,:*),
                      )

        return different_powers(data, rule, σs; wrap_commutative)
    end


    # gimmick to make Neim work in some cases:
    # * if data is a division transform it to a multiplication
    # (the final solution would be remove divisions form rules)
    # * if the rule is a product, at least one of the factors is a power, and data is a division
    neim_pass, arg_data, arg_rule = neim_rewrite(data, rule)
    𝑜𝑝ₛ != opᵣ && !neim_pass && return NO_MATCH

    # segments variables means number of arguments might not match
    if (any(is_segment, arg_rule))
        # @show :has_any
        return has_any_segment(𝑜𝑝ₛ, arg_data, opᵣ, arg_rule,  σs; wrap_commutative)
    end

    if (any(is_plus, arg_rule))
        # @show :has_plus, arg_data, arg_rule
        return has_any_plus(𝑜𝑝ₛ, arg_data, opᵣ, arg_rule,  σs; wrap_commutative)
    end


    (length(arg_data) != length(arg_rule)) && return MatchDict[]
    if iscommutative(opᵣ)
        σ′s = check_commutative(arg_data, arg_rule, σs; wrap_commutative)
        return isempty(σ′s) ? NO_MATCH : σ′s
    end
    # normal checks
    return ceoaa(arg_data, arg_rule, σs; wrap_commutative)
end

# check expression of all arguments
# elements of arg_rule can be Expr or Real
function ceoaa(arg_data, arg_rule, σs::𝑀; wrap_commutative=false)::𝑀
    if all(is_𝑋, arg_rule) && !any(is_op, arg_rule)
        nseg = count(is_segment, arg_rule) # no segment? need same wild
        iszero(nseg) && count(is_slot, arg_rule) != length(arg_data) &&
            return NO_MATCH
    end
    σs == NO_MATCH && return NO_MATCH
    if (any(is_segment, arg_rule))
        return has_any_segment(nothing, arg_data, nothing, arg_rule,  σs; wrap_commutative)
    end
    if (any(is_plus, arg_rule))
        return has_any_plus(nothing, arg_data, nothing, arg_rule,  σs; wrap_commutative)
    end
    σ′s = σs
    for (a, b) in zip(arg_data, arg_rule)
        σ′s = check_expr_r(a, b, σ′s; wrap_commutative)
        σ′s == NO_MATCH && return NO_MATCH
    end
    return σ′s
end

# match a single variable
function just_variable(data, rule, σs::𝑀)::𝑀
    #@show :jv, data, rule
    @assert is_𝑋(rule)
    var = varname(rule)
    val = (is_segment(rule) || is_plus(rule)) ? (data,) : data
    isempty(σs) && return NO_MATCH
    ms = MatchDict[]
    for σ ∈ σs
        if haskey(σ, var) # if the slot has already been matched
            σvar = σ[var]
            isequal(σvar, val) && push!(ms, σ)
        else
            # if never been matched
            if has_predicate(rule)
                pred = get_predicate(rule)
                !_evalguard(pred, val) && continue
            end
            push!(ms, match_dict(σ, var=> val))
        end
    end
    return isempty(ms) ? NO_MATCH : ms
end

# expression has defslot
function has_defslot(i, data, rule, σs; wrap_commutative=false)
    # @show :has_defslot, data, rule
    op = operation(rule)
    if op ∈ (:^, :/)
        i == 1 && return MatchDict[]
    end
    ps = copy(arguments(rule))
    pᵢ = ps[i]
    qᵢ = :(~$(pᵢ.args[2].args[2]))
    ps[i] = qᵢ

    # build rule expr without defslot and check it
    newr = Expr(:call, operation(rule), ps...) # not pterm here!
    σ′s = check_expr_r(data, newr, σs; wrap_commutative)
    σ′s != MatchDict[] && return σ′s # had a match

    # if no normal match, check only the non-defslot part of the rule
    deleteat!(ps, i)
    tmp = pterm(operation(rule), ps)
    σs = check_expr_r(data, tmp, σs; wrap_commutative)
    σs == MatchDict[] && return MatchDict[]

    var = varname(qᵢ)
    value = get(defslot_op_map, operation(rule), -1)
    _merge_single_expr(σs, var, value)

end

function only_argument_is_segment(data, rule, σs, op=nothing; wrap_commutative=false)
    # @show :only_argument_is_segment, data, rule
    !iscall(data) && return MatchDict[]
    opₛ, opᵣ = Symbol(operation(data)), operation(rule)
    opₛ == opᵣ || return MatchDict[]

    # a segment binds to the tuple of arguments, as in has_any_segment
    seg = only(arguments(rule))
    var = varname(seg)
    args = tuple(arguments(data)...)
    is_plus(seg) && isempty(args) && return MatchDict[]
    _segment_guard(seg, args) || return MatchDict[]
    val = _segment_value(args, opₛ, opᵣ; wrap_commutative)
    _merge_single_expr(σs, var, val)
end

function has_rational(data, rule, σs)
    # @show :has_rational, data, rule
    # rational is a special case, in the integration rules is present only in between numbers, like 1//2
    as = arguments(rule)
    data = _unwrap_const(data)
    data.num == first(as) && data.den == last(as) && return σs
    # r.num == rule.args[2] && r.den == rule.args[3] && return matches::MatchDict
    return MatchDict[]
end


# make powers equivalent for checking
# e.g. sqrt(x) --> x^(1//2)
function different_powers(data, rule, σs::𝑀; wrap_commutative=false)::𝑀
    # @show :different_powers, data, rule
    opᵣ, opₛ = operation(rule), Symbol(operation(data))
    arg_data = arguments(data)
    arg_rule = arguments(rule)
    b = first(arg_data)

    if opᵣ === :^
        # try first normal checks
        if (opₛ === :^)
            σ′s = ceoaa(arg_data, arg_rule, σs; wrap_commutative)
            !isempty(σ′s) && return σ′s
        end

        # try building frankestein arg_data (fad)
        fad = Vector{Any}(undef, 2)
        is1divsmth = (opₛ == :/) && isequal(1, _unwrap_const(first(arg_data)))
        if is1divsmth && _is_operation(^)(arg_data[2]) #iscall(arg_data[2]) && (Symbol(operation(arg_data[2])) == :^)

            # if data is of the alternative form 1/(...)^(...)
            m = arg_data[2]
            fad[1] = arguments(m)[1]
            fad[2] = -1*arguments(m)[2]

        elseif is1divsmth && _is_operation(sqrt)(arg_data[2]) #iscall(arg_data[2]) && (Symbol(operation(arg_data[2])) == :sqrt)
            # if data is of the alternative form 1/sqrt(...),
            # it might match with exponent -1//2
            m = arg_data[2] # like b^m
            fad[1] = arguments(m)[1]
            fad[2] = -1//2

        elseif is1divsmth && _is_operation(exp)(arg_data[2]) #iscall(arg_data[2]) &&
            #(Symbol(operation(arg_data[2])) === :exp)
            # if data is of the alternative form 1/exp(...),
            # it might match ℯ ^ -...
            m = arg_data[2] # like b^m
            pow = first(arguments(m))

            fad[1] = ℯ
            fad[2] = sterm(-, (pow,))

        elseif is1divsmth
            # if data is of the alternative form 1/(...),
            # it might match with exponent = -1
            m = arg_data[2] # like b^m
            fad[1] = m
            fad[2] = -1
        elseif (opₛ  === :^) && iscall(b) &&
            (Symbol(operation(b)) === :/) &&
            _isone(arguments(b)[1])

            # if data is of the alternative form (1/...)^(...)
            m = arg_data[2] # like b^m
            fad[1] = arguments(b)[2]
            fad[2] = -1*m

        elseif opₛ === :exp

            # if data is a exp call, it might match with base e
            fad[1] = ℯ
            fad[2] = b

        elseif opₛ === :sqrt
            # if data is a sqrt call, it might match with exponent 1//2
            fad[1] = b
            fad[2] = 1//2
#        elseif opₛ === :/
#            # rule is ^ we have /, turn into ^-1
#            #push!(fad, arguments(m)[1], -1*arguments(m)[2])
        else
            return MatchDict[]

        end
        return ceoaa(fad, arg_rule, σs; wrap_commutative)

    elseif opᵣ === :sqrt
        if (opₛ === :sqrt)
            tocheck = arg_data # normal checks
        # `isequal`, not `∈`: `==` need not return a Bool for a symbolic exponent
        elseif (opₛ === :^) && any(isequal(_unwrap_const(arg_data[2])), (1//2, :(1//2)))
            tocheck = (b,)
        else
            return MatchDict[]
        end

        return ceoaa(tocheck, arg_rule, σs; wrap_commutative)

    elseif opᵣ === :exp
        if (opₛ === :exp)
            tocheck = arg_data # normal checks
        elseif (opₛ === :^) && (_unwrap_const(b) ∈ (ℯ,:ℯ))
            m = arg_data[2]
            tocheck = (m,)
        else
            return MatchDict[]
        end

        return ceoaa(tocheck, arg_rule, σs; wrap_commutative)
    elseif (opᵣ, opₛ) == (:/, :*)
        # rule is / but may be canonicalized to
        # turn rule into ^-1 terms and check commutatively

        u,v = arguments(rule)
        vs = _is_operation(*)(v) ? arguments(v) : (v,)
        vs′ = map(_invert_expr, vs)
        arg_rule′ = if u == 1
            vs′
        else
            Any[u, vs′...]
        end
        return check_commutative(arg_data, arg_rule′, σs; wrap_commutative)

    elseif (opᵣ, opₛ) == (:/, :^)
        # :(1/~x^~n) ~ x^(-n)
        # rewrite rule as a * b^(-1)
        a, b = arguments(rule)
        if is_operation(:^)(b) # combine exponents
            u, v = arguments(b)
            if is_operation(:(//))(v)
                n,d = arguments(v)
                v′ = pterm(:(//), (-n, d))
            elseif !isa(u, Integer) && isa(v, Number)
                v′ = -v
            else
                v′ = pterm(:*, (v, -1.0))
            end

            b′ = pterm(:^, (u, v′))
            if a == 1
                rule′ = b′
            else
                rule′ = pterm(:*, (a, b′))
            end
        else
            rule′ = Expr(:call, :^, b, -1)
        end
        if !(isa(a, Number) && isone(a))
            rule′ = Expr(:call, :*, a, rule′)
        end
        return check_expr_r(data, rule′, σs; wrap_commutative)

    #end
    elseif (opᵣ, opₛ) == (:*, :/)
        u, v = arg_data
        v′ = sterm(^, [v, -1])
        return check_commutative((u, v′), arg_rule,  σs; wrap_commutative)
    end
end

function neim_rewrite(data, rule)
    neim_pass = false
    arg_rule, arg_data = arguments(rule), arguments(data)
    opᵣ, opₛ = operation(rule), Symbol(operation(data))
    if (opᵣ === :*) && opₛ === :/ && any(is_operation(:^), arg_rule)

        neim_pass = true

        n = arg_data[1]
        d = arg_data[2]
        # then push the denominator of data up with negative power
        sostituto = Any[]
        if iscall(d) && opₛ == :^ #(operation(d)==^)

            a, b, c... =  arg_data
            val = sterm(^, (a,b))
            push!(sostituto, val)

        elseif iscall(d) && opₛ == :*
            # push!(sostituto, map(x->x^-1,arguments(d))...)
            for factor in arguments(d)
                val = sterm(^, (factor, -1))
                push!(sostituto, val)
            end
        elseif iscall(d) && Symbol(operation(d)) == :^
            a,b = arguments(d)
            m = sterm(-, (b,))
            val = sterm(^, (a, m))
            push!(sostituto, val)
        else
            val = sterm(^, (d, -1))
            push!(sostituto, val)
        end

        new_arg_data = Any[]

        if iscall(n)
            if Symbol(operation(n)) === :*
                append!(new_arg_data, arguments(n))
            else
                push!(new_arg_data, n)
            end
        elseif !_isone(n)
            push!(new_arg_data, n)
            # else dont push anything bc *1 gets canceled
        end

        append!(new_arg_data, sostituto)

        arg_data = new_arg_data

        # printdb(4,"Applying neim trick, new arg_data is $arg_data")
    end
    return (neim_pass, arg_data, arg_rule)

end

# The value bound to a segment. With `wrap_commutative`, a segment within
# a commutative operation binds to a term, e.g. `a + b`, rather than the
# tuple `(a, b)`. A single value is not wrapped and an empty match stays `()`.
#
# A guard on a segment (`~~x::pred`) is always passed the tuple, even when
# the bound value is wrapped.
_segment_guard(segpat, vals::Tuple) =
    !has_predicate(segpat) || _evalguard(get_predicate(segpat), vals)

function _segment_value(vals::Tuple, opₛ, opᵣ; wrap_commutative=false)
    (wrap_commutative && iscommutative(opᵣ)) || return vals
    length(vals) ≤ 1 && return isempty(vals) ? vals : only(vals)
    sterm(opₛ, collect(vals))
end

function has_any_segment(𝑜𝑝ₛ, arg_data,
                         opᵣ, arg_rule, σs; wrap_commutative=false)
    # @show :has_any_segment, arg_data, arg_rule
    σs == NO_MATCH && return NO_MATCH
    seg, notseg, seg_positions = _split_segments(arg_rule)
    # @show seg, notseg, seg_positions
    n,m = length(arg_data), length(notseg)
    if m > n
        return MatchDict[]
    elseif m == 0
        σ′s = MatchDict[]
        if length(seg) == 1
            # fast path for the overwhelmingly common single-segment case:
            # avoid the general (and slightly more allocating) machinery
            # below when there is nothing to distribute among multiple
            # segments
            v = first(seg)
            is_plus(v) && isempty(arg_data) && return MatchDict[]
            var = varname(v)
            vals = tuple(arg_data...)
            _segment_guard(v, vals) || return MatchDict[]
            val = _segment_value(vals, 𝑜𝑝ₛ, opᵣ; wrap_commutative)
            for σ ∈ σs
                if haskey(σ, var)
                    isequal(val, σ[var]) && push!(σ′s, σ)
                else
                    push!(σ′s, match_dict(σ, var => val))
                end
            end
            return σ′s
        end
        # distribute all of arg_data among the segment variables: each
        # `~~~`-style (is_plus) segment needs at least one value, so we
        # greedily give one value to each plus segment and dump the rest
        # into the first segment (see `_assign_segments_greedy`)
        seg_is_plus = is_plus.(seg)
        assignment = _assign_segments_greedy(tuple(arg_data...), seg_is_plus)
        isnothing(assignment) && return MatchDict[]
        for σ ∈ σs
            σ′ = σ
            ok = true
            for i ∈ eachindex(seg)
                var = varname(seg[i])
                _segment_guard(seg[i], assignment[i]) || (ok = false; break)
                val = _segment_value(assignment[i], 𝑜𝑝ₛ, opᵣ; wrap_commutative)
                if haskey(σ′, var)
                    isequal(val, σ′[var]) || (ok = false; break)
                else
                    σ′ = match_dict(σ′, var => val)
                end
            end
            ok && push!(σ′s, σ′)
        end# XXX?
        return σ′s
    elseif 0 < m ≤ n
        σ′′s = MatchDict[]
        if iscommutative(opᵣ)
            # these only depend on opᵣ/notseg/seg, not on the subset `ind`
            # chosen below, so compute them once rather than once per
            # combination (there are C(n,m) combinations, which can be
            # large)
            pat′ = pterm(opᵣ, notseg) # can be an issue!
            seg_varnames = varname.(seg)
            seg_is_plus = is_plus.(seg)
            # when there is more than one segment pattern (e.g.
            # `~x + ~~y + ~~w`), the "leftover" values (`val` below) must be
            # distributed among *all* of the segments, not just dumped into
            # the first one with the rest forced to `()` -- that forced
            # `()` is invalid whenever a later segment is `~~~`-style
            # (is_plus, "one or more"). `_assign_segments_greedy` picks one
            # valid distribution (not a full enumeration of every possible
            # split) honoring each plus segment's "at least one" minimum.
            for ind ∈ combinations(1:n, m)
                # take m of the values and match
                sub′ = sterm(𝑜𝑝ₛ, arg_data[ind])
                # `val` depends only on `ind`/`arg_data`/`n`, not on σ or σ′,
                # so compute it once per combination rather than once per
                # (σ, σ′) pair below
                val = length(ind) < n ?
                    _tuple_without_indices(arg_data, ind, n) :
                    ()
                assignment = _assign_segments_greedy(val, seg_is_plus)
                assignment === nothing && continue
                for σ ∈ σs
                    σ′s = check_expr_r(sub′, pat′, [σ]; wrap_commutative)
                    if σ′s != NO_MATCH
                        # we found a match, assign the rest across the segments
                        for σ′ ∈ σ′s
                            τ = σ′
                            ok = true
                            for i ∈ eachindex(seg)
                                svar = seg_varnames[i]
                                sval = _segment_value(assignment[i], 𝑜𝑝ₛ, opᵣ; wrap_commutative)
                                if haskey(τ, svar)
                                    isequal(sval, τ[svar]) || (ok = false; break)
                                else
                                    _segment_guard(seg[i], assignment[i]) ||
                                        (ok = false; break)
                                    τ = match_dict(τ, svar => sval)
                                end
                            end
                            ok && push!(σ′′s, τ)
                        end
                    end
                end
            end
        else
            # march over, use segment to slurp rest
            # this takes some thinking.
            # match ~a,~~b,~c,~~d against say l,m,n,o,p,q
            # has l|()|m|(nopq) # n - nontsegs + 1 choices for first
            #     l|(m)|n|(opq) # then ,,, + 1 for second (if more)
            #     l|(mn)|o|(pq) # then ... + 1 for third (if more)
            #     l|(mno)|p|(q)
            #     l|(mnop)|q|()
            nsegs = length(seg_positions)
            k = length(arg_rule) - nsegs
            n = length(arg_data) - k

            σ′′s =  MatchDict[]
            for α ∈ _compositions(n, nsegs)
                σ′s = σs
                j = 1 # index in data_rule
                l = 1 # index in itr,
                nomatch = false
                for (i,pat) ∈ enumerate(arg_rule)
                    nomatch && continue
                    if l > nsegs || i != seg_positions[l]
                        σ′s = check_expr_r(arg_data[j], pat, σ′s; wrap_commutative)
                        σ′s == NO_MATCH && (nomatch = true)
                        j = j + 1
                    else
                        a = α[l]
                        l = l + 1
                        # `~~~`-style (is_plus, "one or more") segments can
                        # never be validly bound to an empty selection
                        if a == 0 && is_plus(pat)
                            nomatch = true
                            continue
                        end
                        var = varname(pat)
                        #value = view(arg_data,j:(j+a-1))
                        value = tuple(arg_data[j:(j+a-1)]...)
                        if !_segment_guard(pat, value)
                            nomatch = true
                            continue
                        end
                        σ′ = match_dict(var => value)
                        σ′s = _merge_single(σ′s, σ′)
                        σ′s == NO_MATCH && (nomatch = true)
                        j = j + a
                    end
                end
                σ′s == NO_MATCH && continue
                !nomatch && append!(σ′′s, σ′s)
            end
            return isempty(σ′′s) ? NO_MATCH : σ′′s
        end
        if length(seg) > 0
            # match all segments with (), then match the rest
            σ′′′ = match_dict()
            for v ∈ seg
                if is_plus(v)
                    σ′′′ = FAIL_DICT
                    break
                elseif !_segment_guard(v, ())
                    σ′′′ = FAIL_DICT
                    break
                else
                    σ′′′ = match_dict(σ′′′, varname(v) => ())
                end
            end
            σ′′′s = union_merge(σs, σ′′′)
            sub′ = sterm(𝑜𝑝ₛ, arg_data)
            pat′ = pterm(opᵣ, notseg)
            σ′′′s = check_expr_r(sub′, pat′, σ′′′s; wrap_commutative)
            σ′′′s != NO_MATCH && append!(σ′′s, σ′′′s)
        end

        return isempty(σ′′s) ? NO_MATCH : σ′′s
    end
end

# Given a tuple/vector of leftover values and the precomputed `is_plus`
# flags for a list of segment patterns (each either a "star" segment --
# `~~x`, matches 0 or more -- or a "plus" segment -- `~~~x`, matches 1 or
# more), find a single valid way to distribute the values among the
# segments: give one value to each plus segment (to satisfy its "at least
# one" requirement), then dump everything left over into the first
# segment. Returns `nothing` if there are not enough values to give each
# plus segment its required element.
#
# This is a cheap "first valid assignment" heuristic, not a full
# enumeration of every possible split. When several segments appear
# together there are in general many valid ways to distribute the values
# (e.g. for `~~~x + ~~~y + ~~~w` against 3 values, any assignment of the
# three values to the three variables, one each, is valid) but only one
# such split is returned here.
#
# `is_plus_flags` is passed in (rather than recomputed from `segs` here)
# since it is invariant across repeated calls in a hot loop (one call per
# subset `ind` in `has_any_segment`'s commutative branch); the result is a
# plain `Vector{Any}` of assigned values, positionally matching `segs`/
# `is_plus_flags` (not `var => val` pairs), so the caller can reuse its
# own precomputed segment varnames without recomputing them here.
function _assign_segments_greedy(vals, is_plus_flags)
    k = length(is_plus_flags)
    n = length(vals)
    p = 0
    for f ∈ is_plus_flags
        f && (p += 1)
    end
    p > n && return nothing

    assigned = Vector{Any}(undef, k)
    idx = 1
    for i ∈ 1:k
        if is_plus_flags[i]
            assigned[i] = (vals[idx],)
            idx += 1
        else
            assigned[i] = ()
        end
    end
    if idx ≤ n
        rest = vals[idx:end]
        assigned[1] = (assigned[1]..., rest...)
    end
    return assigned
end



function has_any_plus(𝑜𝑝ₛ, arg_data,
                      opᵣ, arg_rule, σs; wrap_commutative=false)
    # @show :has_any_plus, arg_data, arg_rule
    has_any_segment(𝑜𝑝ₛ, arg_data,
                      opᵣ, arg_rule, σs; wrap_commutative)
end
@inline function _commutative_priority(pat)
    is_defslot(pat) && return 3
    has_predicate(pat) && return 2
    is_slot(pat) && return 4
    has_𝑋(pat) && return 1
    return 0
end

function _append_unique!(out, σs)
    for σ ∈ σs
        any(τ -> _isequal_match(τ, σ), out) || push!(out, σ)
    end
    return out
end

# cheap, allocation-avoiding equality check used only to detect/prune
# duplicate-valued arguments below. Falls back to `isequal` only when the
# concrete types already match, since comparing mismatched concrete types
# (e.g. a literal `1` against a symbolic expression) can otherwise fall
# through to generic, allocating promotion machinery for what can never be
# a duplicate for pruning purposes.
@inline _cheap_isequal(a, b) = a === b || (typeof(a) === typeof(b) && isequal(a, b))

function _check_commutative!(out, used, arg_data, arg_rule, order, k, σs::𝑀; wrap_commutative=false)::𝑀
    # @show :check_commutative
    σs == NO_MATCH && return out
    k > length(order) && return _append_unique!(out, σs)

    pat = arg_rule[order[k]]
    for j ∈ eachindex(arg_data)
        used[j] && continue
        val = arg_data[j]

        # When several unused data elements are equal (a common case:
        # repeated terms like x + x + y), trying each of them for the
        # *current* pattern slot explores symmetric branches whose eventual
        # results are identical (matching only depends on the *value*,
        # never on which physical index produced it, and the multiset of
        # values left over for the remaining patterns is the same no matter
        # which equal-valued index is consumed now). So only the first
        # unused occurrence of each distinct value needs to be tried at
        # this level. Detect "already tried at this level" by scanning
        # backwards for an earlier still-unused index with an equal value;
        # this needs no extra allocation (arg_data/used are already
        # available) and is cheap since argument lists are small.
        isdup = false
        for jj ∈ 1:(j - 1)
            if !used[jj] && _cheap_isequal(arg_data[jj], val)
                isdup = true
                break
            end
        end
        isdup && continue

        σ′s = check_expr_r(val, pat, σs; wrap_commutative)
        σ′s == NO_MATCH && continue
        used[j] = true
        _check_commutative!(out, used, arg_data, arg_rule, order, k + 1, σ′s; wrap_commutative)
        used[j] = false
    end
    return out
end

function check_commutative(arg_data, arg_rule, σs::𝑀; wrap_commutative=false)::𝑀
    # commutative checks
    length(arg_data) != length(arg_rule) && return NO_MATCH

    order = sortperm(collect(eachindex(arg_rule)); by = i -> _commutative_priority(arg_rule[i]))
    used = falses(length(arg_data))
    σ′′s = MatchDict[]
    _check_commutative!(σ′′s, used, arg_data, arg_rule, order, 1, σs; wrap_commutative)
    return isempty(σ′′s) ? NO_MATCH : σ′′s
end
