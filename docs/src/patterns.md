```@meta
CurrentModule = CommutativePatternMatching
DocTestSetup = quote
    using CommutativePatternMatching
    const CPM = CommutativePatternMatching
end
```

# Patterns

A pattern is an expression in which some parts are *wildcards*, written
with a `~`. Anything else in a pattern, such as a function name or a
number, must appear in the subject as written.

## Wildcards

| wildcard | matches                                                        |
|:---------|:---------------------------------------------------------------|
| `~x`     | one argument                                                   |
| `~!x`    | one argument, or a default value when there is none            |
| `~~x`    | zero or more arguments, bound as a tuple                       |
| `~~~x`   | one or more arguments, bound as a tuple                        |

A pattern can have only one wildcard of a given name, so `~x + ~~x` is not
allowed. A name may be repeated, though, in which case each occurrence must
match the same value.

### Slots

The slot `~x` matches a single argument, which may itself be an
expression:

```jldoctest
julia> CPM._match(:(~x + ~y), :(a + sin(b)))
Base.ImmutableDict{Symbol, Any} with 2 entries:
  :y => :(sin(b))
  :x => :a

julia> CPM._match(:(~x + ~x), :(a + a))
Base.ImmutableDict{Symbol, Any} with 1 entry:
  :x => :a

julia> CPM._match(:(~x + ~x), :(a + b)) === nothing
true
```

The pattern `~x + ~y` does not match `a + b + c`, as there are three terms
to match, not two. Use a segment for that.

### Default slots

The default slot `~!x` matches as `~x` does, but when there is no argument
to match it binds a default value: `0` within a sum, and `1` within a
product, or as an exponent or denominator.

```jldoctest
julia> CPM._match(:(~x + ~!y), :(a + b))
Base.ImmutableDict{Symbol, Any} with 2 entries:
  :y => :b
  :x => :a

julia> CPM._match(:(~x + ~!y), :a)
Base.ImmutableDict{Symbol, Any} with 2 entries:
  :y => 0
  :x => :a

julia> CPM._match(:((~x)^(~!n)), :a)
Base.ImmutableDict{Symbol, Any} with 2 entries:
  :n => 1
  :x => :a
```

### Segments

The segment `~~x` matches any number of arguments, including none, and
binds them as a tuple. The segment `~~~x` is the same, but must match at
least one argument.

```jldoctest
julia> CPM._eachmatch(:(~x + ~~y), :(a + b + c))
4-element Vector{Base.ImmutableDict{Symbol, Any}}:
 Base.ImmutableDict(:y => (:b, :c), :x => :a)
 Base.ImmutableDict(:y => (:a, :c), :x => :b)
 Base.ImmutableDict(:y => (:a, :b), :x => :c)
 Base.ImmutableDict(:x => :(a + b + c), :y => ())

julia> CPM._eachmatch(:(~x + ~~~y), :(a + b + c))
3-element Vector{Base.ImmutableDict{Symbol, Any}}:
 Base.ImmutableDict(:y => (:b, :c), :x => :a)
 Base.ImmutableDict(:y => (:a, :c), :x => :b)
 Base.ImmutableDict(:y => (:a, :b), :x => :c)
```

In an operation that is not commutative, a segment matches a run of
consecutive arguments:

```jldoctest
julia> CPM._match(:(f(~x, ~~y)), :(f(a)))
Base.ImmutableDict{Symbol, Any} with 2 entries:
  :y => ()
  :x => :a

julia> CPM._match(:(f(~x, ~~~y)), :(f(a))) === nothing
true
```

## Guards

A wildcard may have a guard, a predicate its value must satisfy, written
`~x::pred`. The match is made only when `pred(value)` returns `true`. A
guard which returns anything else, or throws an error, rejects the match.

```jldoctest
julia> CPM._match(:((~x)^(~n::isinteger)), :(x^2))
Base.ImmutableDict{Symbol, Any} with 2 entries:
  :n => 2
  :x => :x

julia> CPM._match(:((~x)^(~n::isinteger)), :(x^y)) === nothing
true
```

A guard may be the name of a function, or an expression which evaluates to
one, such as an anonymous function or a partially applied function:

```jldoctest
julia> CPM._match(:((~x)^(~n::(n -> n > 1))), :(x^2))
Base.ImmutableDict{Symbol, Any} with 2 entries:
  :n => 2
  :x => :x

julia> CPM._match(:((~x)^(~n::!=(-1))), :(x^3))
Base.ImmutableDict{Symbol, Any} with 2 entries:
  :n => 3
  :x => :x
```

As `y > 1` throws an error for the symbol `y`, the guard rejects `x^y`:

```jldoctest
julia> CPM._match(:((~x)^(~n::(n -> n > 1))), :(x^y)) === nothing
true
```

A guard on a segment is passed the tuple of matched values:

```jldoctest
julia> CPM._match(:(~x + ~~y::(u -> length(u) == 2)), :(a + b + c))
Base.ImmutableDict{Symbol, Any} with 2 entries:
  :y => (:b, :c)
  :x => :a
```

### Where a guard is found

In a quoted pattern, a guard given by name, or an expression for a guard, is
evaluated in `Main` (with names looked up in `Main`, then `Base`) when the
pattern is first matched. A predicate defined in a package or other module
will not be found there, and the match fails. To use such a predicate,
write the pattern with [`@pattern`](@ref) (or the left-hand side of
[`@rule`](@ref)), which evaluates each guard where the macro is called:

```jldoctest
julia> module M
           using CommutativePatternMatching
           const CPM = CommutativePatternMatching
           ispos(x) = x > 0
           quoted = CPM._match(:(f(~x::ispos)), :(f(2)))
           macroed = CPM._match(@pattern(f(~x::ispos)), :(f(2)))
       end;

julia> M.quoted === nothing
true

julia> M.macroed
Base.ImmutableDict{Symbol, Any} with 1 entry:
  :x => 2
```
