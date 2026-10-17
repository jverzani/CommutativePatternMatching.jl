```@meta
CurrentModule = CommutativePatternMatching
```

# CommutativePatternMatching

[CommutativePatternMatching](https://github.com/jverzani/CommutativePatternMatching.jl)
matches patterns against expressions, taking into account that `+` and
`*` are commutative. It extends the pattern matcher used for the
rule-based methods of
[SymbolicIntegration](https://github.com/JuliaSymbolics/SymbolicIntegration.jl),
and was written to see if more rule-based integration patterns could be
matched (cf.
[RUBISymbolicIntegration](https://github.com/jverzani/RUBISymbolicIntegration.jl)).

A subject to match against may be a Julia `Expr` or a term from a
symbolic package implementing
[TermInterface](https://github.com/JuliaSymbolics/TermInterface.jl), such
as SymEngine, SymbolicUtils, or SimpleExpressions. The examples here mostly
use `Expr` subjects, so need nothing but this package.

## Matching

A pattern is an expression with *wildcards*, such as `~x`. (See
[Patterns](@ref) for the kinds of wildcards and their guards.) The
pattern language is very similar to that of the
[rule-based rewriting](https://docs.sciml.ai/SymbolicUtils/stable/manual/rewrite/)
in SymbolicUtils; see [Differences from SymbolicUtils](@ref) for where
they differ. The
function `_match` returns the first match of a pattern to a subject, or
`nothing`; `_eachmatch` returns a vector of all the matches found. A match
is a dictionary from the names of the wildcards to the values they bind.

```jldoctest index
julia> using CommutativePatternMatching

julia> const CPM = CommutativePatternMatching;

julia> CPM._match(:(sin(~x)), :(sin(a + b)))
Base.ImmutableDict{Symbol, Any} with 1 entry:
  :x => :(a + b)

julia> CPM._match(:(sin(~x)), :(cos(a))) === nothing
true
```

As `+` and `*` are commutative, the arguments of a sum or product may
be matched in any order:

```jldoctest index
julia> CPM._eachmatch(:(~x + ~y), :(a + b))
2-element Vector{Base.ImmutableDict{Symbol, Any}}:
 Base.ImmutableDict(:y => :b, :x => :a)
 Base.ImmutableDict(:y => :a, :x => :b)

julia> CPM._match(:(~x * sin(~y)), :(sin(b) * a))
Base.ImmutableDict{Symbol, Any} with 2 entries:
  :x => :a
  :y => :b
```

The same holds for a symbolic subject:

```julia
julia> using SymEngine

julia> @vars x y;

julia> CPM._match(:(sin(~x)), sin(x + y))
Base.ImmutableDict{Symbol, Any} with 1 entry:
  :x => x + y
```

## The `@pattern` macro

A pattern may be written as a quoted expression, as above, or with the
[`@pattern`](@ref) macro. The two differ in how a guard, such as
`isinteger` in `~n::isinteger`, is found. In a quoted pattern, a guard
given by name is looked up in `Main` and `Base` when the pattern is
matched. With `@pattern`, the guard is evaluated where the macro is
called, so a function defined in a package or a module can be used:

```jldoctest index
julia> module M
           using CommutativePatternMatching
           const CPM = CommutativePatternMatching
           ispos(x) = x > 0
           quoted = CPM._match(:(f(~x::ispos)), :(f(2)))
           macroed = CPM._match(@pattern(f(~x::ispos)), :(f(2)))
       end;

julia> M.quoted === nothing # `ispos` is not found in `Main`
true

julia> M.macroed
Base.ImmutableDict{Symbol, Any} with 1 entry:
  :x => 2
```

Values may be interpolated into a pattern with `$`:

```jldoctest index
julia> n = 3;

julia> pat = @pattern (~x)^$n
:((~x) ^ 3)

julia> CPM._match(pat, :(y^3))
Base.ImmutableDict{Symbol, Any} with 1 entry:
  :x => :y
```

## The `@rule` macro

The [`@rule`](@ref) macro creates a rule, `lhs => rhs`. The left-hand side is
a pattern, as for `@pattern`. Calling the rule on a subject returns `rhs`,
with each wildcard replaced by its value in the first match, or `nothing`
when the subject does not match.

```jldoctest index
julia> r = @rule sin(2 * ~x) => 2 * sin(~x) * cos(~x)
@rule sin(2 * ~x) => 2 * sin(~x) * cos(~x)

julia> r(:(sin(2t)))
:(2 * sin(t) * cos(t))

julia> r(:(cos(2t))) === nothing
true
```

For an `Expr` subject, as above, the values are substituted into `rhs` and
an `Expr` is returned. For a symbolic subject, `rhs` is Julia code that is
run, so the result is computed:

```julia
julia> using SymEngine

julia> @vars x y;

julia> r = @rule (~x)^(~n::isinteger) => (~x)^(~n + 1) / (~n + 1);

julia> r(x^2)
(1/3)*x^3

julia> r(x^y) === nothing
true
```

The right-hand side is compiled where `@rule` is called, so it may use the
functions and variables of the calling module. A segment (`~~x`, see
[Segments](@ref)) is replaced by its tuple of values, which may be splatted
into a call:

```julia
julia> r = @rule ~x + ~~y => +(~~y...);

julia> r(x + y + 2) # drops one term of the sum
x + y
```

As this substitutes a tuple into an `Expr` for an `Expr` subject, a segment
on the right-hand side is best used with symbolic subjects.

## Differences from SymbolicUtils

The wildcards `~x`, `~!x` and `~~x`, guards written `~x::pred`, and the
form `@rule lhs => rhs` are as in SymbolicUtils, and both try the
arguments of `+` and `*` in different orders. Compared with SymbolicUtils
(v4.51), this package differs in that:

* A subject may be an `Expr`, as well as a symbolic term from any package
  implementing TermInterface.
* `_eachmatch` returns every match of a pattern, not just the first.
* A segment `~~x` binds to a tuple, rather than an array (a view of the
  arguments), and a guard on a segment is passed that tuple.
* There is a segment `~~~x` which matches one or more arguments.
* A default slot `~!x` may be used in a denominator, defaulting to `1`, as
  well as in `+`, `*` and an exponent.
* A guard which returns anything but `true`, or which throws an error,
  rejects the match. In SymbolicUtils, the rule throws an error.
* A guard in a quoted pattern is looked up in `Main` (see
  [Where a guard is found](@ref)). Guards in `@pattern` and `@rule` are
  evaluated in the calling module, as with SymbolicUtils' `@rule`.

Some features of SymbolicUtils' rules are not supported:

* a predicate over the whole rule, `@rule lhs => rhs where pred`. For a
  symbolic subject, the same effect comes from a right-hand side such as
  `pred ? rhs : nothing`, as a rule returns whatever `rhs` evaluates to;
* `~` alone on the right-hand side, to return the match;
* contextual predicates, and the macros `@capture` and `@acrule`.
