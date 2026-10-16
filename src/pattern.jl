## ---- @pattern -----

"""
    @pattern expr

Create a pattern from `expr`, as `:(expr)` would, except each guard of a
wildcard (`~x::pred`, `~~x::pred`, `~~~x::pred`) is evaluated where the
macro is called and spliced into the pattern as a value.

A guard in a quoted pattern, `:(~x::isfoo)`, is looked up by name in `Main`
and `Base` when the pattern is matched, so a predicate defined in another
package is not found. With `@pattern` the guard is resolved in the calling
module, as is any function a guard such as `(u -> isfoo(u))` refers to.

Values may be interpolated with `\$`, as with a quoted expression.

## Examples

```julia
julia> module Ext
           using CommutativePatternMatching
           isfoo(x) = x == :a
           pat = @pattern sin(~x::isfoo)
       end;

julia> CommutativePatternMatching._eachmatch(Ext.pat, :(sin(a)))
1-element Vector{Base.ImmutableDict{Symbol, Any}}:
 Base.ImmutableDict(:x => :a)
```
"""
macro pattern(ex)
    Expr(:quote, _splice_guards(ex, false))
end

# Walk the pattern. Within a wildcard (a call to `~`), replace the guard in
# `x::pred` with `$(esc(pred))`, so the quote evaluates it in the caller's
# scope. Interpolations by the user are escaped likewise.
_splice_guards(x, inslot) = x
function _splice_guards(ex::Expr, inslot)
    ex.head === :$ && return Expr(:$, map(esc, ex.args)...)
    if inslot && ex.head === :(::) && length(ex.args) == 2
        var, pred = ex.args
        return Expr(:(::), _splice_guards(var, inslot), Expr(:$, esc(pred)))
    end
    inslot = inslot || (ex.head === :call && first(ex.args) === :(~))
    Expr(ex.head, map(a -> _splice_guards(a, inslot), ex.args)...)
end
