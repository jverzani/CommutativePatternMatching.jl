# Handoff: using CommutativePatternMatching for an integration rule set

Notes for the next piece of work: a separate package that turns several
thousand `Expr => Expr` integration rules into rules for this package and
applies them. Written 2026-10-16, on branch `test-suite`.

## State of this package

- Branch `test-suite`, not yet merged to `main`. Commits:
  - `3b1fba5` matcher code from SimpleExpressions, the shared test suite,
    and bug fixes
  - `246138e` ignore `Manifest*.toml` and IDE files
  - `b678a2e` `@pattern`; guards resolved without `eval`
  - then `@rule`/`Rule` and `_rewrite` without `eval` (`src/rule.jl`),
    `_match` returning `nothing` on no match, `test/rule_tests.jl`, and
    these notes
- `Pkg.test()` passes (648 tests) against `Expr`, SymEngine,
  SymbolicUtils v4 and SimpleExpressions subjects.

## API

All in `src/`. `_eachmatch`, `_match` and `_rewrite` are not exported;
`@pattern` and `@rule` are.

| | |
|---|---|
| `_eachmatch(pat, sub; wrap_commutative=false)` | all matches, a `Vector{ImmutableDict{Symbol,Any}}`; empty if none |
| `_match(pat, sub; kwargs...)` | first match, or `nothing` |
| `@pattern ex` | a quoted pattern, with guards resolved in the calling module |
| `@rule lhs => rhs` | a `Rule`; `rule(sub; kwargs...)` gives the rewrite or `nothing` |
| `_rewrite(σ, rhs, [S])` | apply a match to a template (`Expr`) or a function of the match |

Wildcards:

- `~x`: one argument. `~!x`: one argument, or a default (0 for `+`, 1 for
  `*` and `^`).
- `~~x`: 0 or more arguments. `~~~x`: 1 or more. Both bind to a tuple.
  With `wrap_commutative=true`, a segment directly inside `+` or `*` binds
  to a term (`a + b`) instead. A single value stays bare, and an empty
  match stays `()`.
- `(~F)(~x)`: binds the operation.
- `~x::pred`: a guard. A segment's guard always gets the tuple, even when
  the bound value is wrapped. A guard which can not be resolved, throws,
  or does not return exactly `true` fails the match.

How matching behaves:

- Matching is commutative, not associative: `~x + ~y` does not match
  `a + b + c`. The counts are in the table at the top of `src/rule2a.jl`
  and are tested.
- When the pattern has several segments, they are filled greedily: one
  valid way to split the arguments is returned, not every way.
- A plain symbol in a pattern (`:(sin(x))`) matches a variable whose name
  prints the same. This is a heuristic in `eq_expr(a, b::Symbol)`.

## Generating rules in the other package

A macro sees only the syntax it is given, so `@rule $r` in a comprehension
does not work. Build each call from the data and evaluate it at the
package's top level:

```julia
module IntegrationRules
using CommutativePatternMatching

include("rule_data.jl")   # const expr_expr_rules = [:(lhs) => :(rhs), ...]

const rs = [@eval(@rule $(r.first) => $(r.second)) for r in expr_expr_rules]
end
```

- This runs during precompilation, in the package's own module. Guards
  and right-hand-side functions therefore resolve there, so the rules can
  use the package's own predicates and helpers without exporting them.
- If the rule data is read from a non-Julia file, mark it with
  `include_dependency` so that editing it triggers recompilation.
- `@rule`'s right-hand side is ordinary Julia code. It becomes a closure
  `σ -> ...`, with each `~x` replaced by `σ[:x]`.
- For an `Expr` subject, `rule(sub)` returns an `Expr`, built by
  substituting the matched values into the right-hand side; nothing is
  evaluated. For symbolic subjects, the right-hand side is evaluated.

Avoid quoted rules passed to `_rewrite` for this. Names in a quoted
template are looked up only in `Main` and `Base`, so a function from the
rules package raises an `ArgumentError`. That path exists for one-off
templates.

## Performance (measured)

A throwaway package with 3000 generated rules, matching an `Expr` subject
that only the last rule matches:

| | |
|---|---|
| precompile | 2.7 s |
| load | 0.24 s |
| first pass over all rules | 1.5 s |
| each pass after that | 5.5 ms (about 2 μs per rule) |

- `Rule` is deliberately not parametric. With `Rule{F}`, Julia compiled a
  method for calling every rule: the first pass took 8.2 s and each later
  pass 10 ms. Keep it that way.
- Most of the 1.5 s first pass is compiling the matcher, which all rules
  share. A `PrecompileTools` workload that runs a few matches should move
  that into precompilation. Each rule's right-hand side also compiles the
  first time that rule fires, which costs a few ms once per rule.
- A pass is a linear scan. Grouping `rs` in a `Dict` keyed by the outer
  operation of each left-hand side, and only trying that group, is the
  obvious next step. This has not been measured: the synthetic rules all
  had the same outer operation.
- After its first call, a rule's right-hand side costs about 0.9 μs, against
  3.5 μs for a quoted template through `_rewrite` and 86 μs for the old
  approach of calling `eval` on every rewrite.

## Subject types

The matcher uses TermInterface (`iscall`, `operation`, `arguments`,
`maketerm`), so any type implementing it should work. Each type needs two
pieces of glue:

- `unwrap_const(x)` converts a numeric term to a Julia number, so that a
  `2` in a pattern equals a `2` in the subject. These methods are
  currently in `test/backends.jl` and should become package extensions:
  - SimpleExpressions: `unwrap_const(x::SymbolicNumber) = x()`
  - SymbolicUtils v4, which wraps numbers as constants:
    `unwrap_const(x::BasicSymbolic) = SymbolicUtils.unwrap_const(x)`
  - SymEngine needs none.
- `symtype(x)` gives the type used to build new terms. The default is
  `typeof(x)`, with `Expr` for plain Julia numbers, symbols and
  expressions.

Things to know about the types:

- SimpleExpressions' `AbstractSymbolic <: Function`, and SymEngine's
  `Basic <: Number`. Code that tests `isa Function` or `isa Number` gets
  these wrong. `_symtype` in `src/rule.jl` already works around the first.
- SymbolicUtils' `==` returns a symbolic value. Compare with `isequal`.
- SymbolicUtils v4 restricts Combinatorics to 1.0.x. Without a compat bound
  the resolver picks SymbolicUtils v3 instead, so `test/Project.toml` pins
  `SymbolicUtils = "4"`.

## Open issues

- The `unwrap_const` glue is not yet in package extensions (see above).
- `~a*(~b*~c)` does not match `a*b*c` (a TODO in `src/rule2a.jl`).
- A match is an `ImmutableDict{Symbol,Any}`, so code in a right-hand side
  is not type-stable. This has been fine so far.
- `PREDICATE_FN_CACHE` (`src/utils.jl`) caches guards that are written as
  expressions in quoted patterns, keyed by the identity of the expression.
  Patterns built repeatedly at run time make it grow. `@pattern` and
  `@rule` do not use it.
- The `wrap_commutative` keyword of `only_argument_is_segment` was
  removed; the value is now wrapped in `_segment_value`.

## Tests

- Run `julia --project=. -e 'using Pkg; Pkg.test()'`. The test
  dependencies are in `test/Project.toml`.
- `test/backends.jl` builds a subject for each backend from an `Expr`, so
  most tests (`test/shared_tests.jl`) are written once. Behavior that
  depends on how a type stores terms is in `test/backend_tests.jl`.
- `test/guard_tests.jl` and `test/rule_tests.jl` define their rules and
  predicates in separate modules, to check that names resolve in the
  module that wrote them. Do the same for the integration rule package.
