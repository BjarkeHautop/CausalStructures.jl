"""
    Estimand

Abstract supertype for symbolic causal estimands: formulas expressed purely in
terms of the observational distribution.

The concrete subtypes are [`Prob`](@ref), [`Marginal`](@ref),
[`Product`](@ref), and [`Quotient`](@ref). Build them with the smart
constructors [`prob`](@ref), [`marginal`](@ref), [`product`](@ref), and
[`quotient`](@ref).

# Output formats

It can be rendered as text, rendered as LaTeX, or taken apart field by field:

```jldoctest
julia> e = marginal([:Z], product([prob(:Y; given = [:X, :Z]), prob(:Z)]));

julia> string(e)
"Σ_{Z} P(Y | X, Z) P(Z)"

julia> e.index
1-element Vector{Symbol}:
 :Z

julia> e.term.terms[1].given
2-element Vector{Symbol}:
 :X
 :Z
```

The LaTeX form comes from the `MIME"text/latex"` method, so
`repr(MIME("text/latex"), e)` gives `\$\\sum_{Z} P(Y \\mid X, Z) P(Z)\$`,
used for frontend documentation.
"""
abstract type Estimand end

"""
    Prob(vars, given)

A probability term `P(vars | given)`, the leaf of an [`Estimand`](@ref) tree.

Both variable lists are stored sorted, so that terms differing only in the
order the variables were listed compare equal. Use [`prob`](@ref) to construct.
"""
struct Prob <: Estimand
    vars::Vector{Symbol}
    given::Vector{Symbol}
end

"""
    Marginal(index, term)

The sum of `term` over all values of the variables in `index`. Use
[`marginal`](@ref) to construct.
"""
struct Marginal <: Estimand
    index::Vector{Symbol}
    term::Estimand
end

"""
    Product(terms)

The product of `terms`. An empty product is the multiplicative identity `1`.
Use [`product`](@ref) to construct.
"""
struct Product <: Estimand
    terms::Vector{Estimand}
end

"""
    Quotient(num, den)

The ratio `num / den`. Use [`quotient`](@ref) to construct.
"""
struct Quotient <: Estimand
    num::Estimand
    den::Estimand
end

# The multiplicative identity, produced by `product(Estimand[])` and by
# `marginal` when everything has been summed out.
const _ONE = Product(Estimand[])

Base.one(::Type{Estimand}) = _ONE
Base.isone(e::Estimand) = e isa Product && isempty(e.terms)

# --- equality and hashing ---------------------------------------------------

Base.:(==)(a::Prob, b::Prob) = a.vars == b.vars && a.given == b.given
Base.:(==)(a::Marginal, b::Marginal) = a.index == b.index && a.term == b.term
Base.:(==)(a::Product, b::Product) = a.terms == b.terms
Base.:(==)(a::Quotient, b::Quotient) = a.num == b.num && a.den == b.den
Base.:(==)(::Estimand, ::Estimand) = false

Base.hash(e::Prob, h::UInt) = hash(e.given, hash(e.vars, hash(:Prob, h)))
Base.hash(e::Marginal, h::UInt) = hash(e.term, hash(e.index, hash(:Marginal, h)))
Base.hash(e::Product, h::UInt) = hash(e.terms, hash(:Product, h))
Base.hash(e::Quotient, h::UInt) = hash(e.den, hash(e.num, hash(:Quotient, h)))

# --- free variables ---------------------------------------------------------

# The variables an expression is a function of. A summation index is bound by
# the sum that introduces it, so it is not free in that sum.
_free_vars(e::Prob) = Set{Symbol}(vcat(e.vars, e.given))
_free_vars(e::Marginal) = setdiff(_free_vars(e.term), Set(e.index))
_free_vars(e::Quotient) = union(_free_vars(e.num), _free_vars(e.den))
_free_vars(e::Product) =
    isempty(e.terms) ? Set{Symbol}() : union((_free_vars(t) for t in e.terms)...)

# The factors of an expression, as a fresh vector the caller may mutate.
_factors(e::Product) = copy(e.terms)
_factors(e::Estimand) = Estimand[e]

# --- smart constructors -----------------------------------------------------

"""
    prob(vars; given = Symbol[]) -> Estimand

Build the probability term `P(vars | given)`.

`vars` may be a single `Symbol` or a vector of them. Both lists are sorted and
de-duplicated, and any variable appearing in `given` is dropped from `vars`
(since `P(X, Y | X) = P(Y | X)`). A term left with an empty head is the
constant `1`.

# Examples

```jldoctest
julia> prob([:Y, :W]; given = [:X])
P(W, Y | X)
```

```jldoctest
julia> prob(:Y)
P(Y)
```
"""
function prob(vars; given = Symbol[])
    g = sort(unique(_as_symbols(given)))
    v = sort(setdiff(unique(_as_symbols(vars)), g))
    isempty(v) && return _ONE
    return Prob(v, g)
end

_as_symbols(s::Symbol) = [s]
_as_symbols(v::AbstractVector{Symbol}) = collect(v)
_as_symbols(v) = collect(Symbol, v)

"""
    marginal(index, term) -> Estimand

Sum `term` over the variables in `index`.

An empty `index` returns `term` unchanged, and nested sums are flattened into
a single one. Summing a probability term over part of its own head marginalizes
it directly: `Σ_a P(a, b | c)` becomes `P(b | c)`.

Sums over a product are narrowed as far as they go: factors that do not mention
the summation index are constants of the sum and are pulled out in front of it,
and a factor whose whole head is summed over, and whose head no other factor
under the sum mentions, sums to `1` and drops out. A denominator free of the
index is likewise pulled out of the sum.

# Examples

Here `W` is in the conditioning set rather than the head, so the sum stands:

```jldoctest
julia> marginal([:W], prob(:Y; given = [:W, :X]))
Σ_{W} P(Y | W, X)
```

Summing over a variable in the head marginalizes it away instead:

```jldoctest
julia> marginal([:W], prob([:W, :Y]; given = [:X]))
P(Y | X)
```

```jldoctest
julia> marginal(Symbol[], prob(:Y))
P(Y)
```

`P(Z | X)` does not mention `W`, so it leaves the sum, and what remains sums to
one:

```jldoctest
julia> marginal([:W], product([prob(:Z; given = [:X]), prob(:W; given = [:X, :Z])]))
P(Z | X)
```
"""
function marginal(index, term::Estimand)
    idx = sort(unique(_as_symbols(index)))
    isempty(idx) && return term

    # Σ_a P(a, b | c) == P(b | c).
    if term isa Prob && issubset(idx, term.vars)
        return prob(setdiff(term.vars, idx); given = term.given)
    end

    # Σ_a Σ_b f  ==  Σ_{a, b} f
    term isa Marginal && return marginal(union(idx, term.index), term.term)

    # Σ_a (f / g) == (Σ_a f) / g, when g is a constant of the sum.
    if term isa Quotient && isdisjoint(idx, _free_vars(term.den))
        return quotient(marginal(idx, term.num), term.den)
    end

    if term isa Product
        outside, inside, rest = _narrow_sum(term.terms, idx)
        # Anything pulled out or dropped shrinks the summand, so re-entering
        # `marginal` here terminates.
        length(inside) == length(term.terms) ||
            return _rebuild_sum(term.terms, outside, inside, rest)
    end

    return Marginal(idx, term)
end

# Sort the positions of a summed product's factors into those that can leave the
# sum and those that must stay, along with the summation index the latter still
# need.
#
# The two rewrites feed each other, so they run to a fixpoint: pulling a factor
# out cannot free an index, but dropping one that sums to one can leave further
# factors constant in what is left of the index.
function _narrow_sum(terms::Vector{Estimand}, index::Vector{Symbol})
    outside = Int[]
    inside = collect(eachindex(terms))
    rest = index

    while true
        changed = false

        # A factor mentioning none of the remaining indices is constant across
        # the sum, so it can sit outside it.
        keep = Int[]
        for p in inside
            if isdisjoint(rest, _free_vars(terms[p]))
                push!(outside, p)
                changed = true
            else
                push!(keep, p)
            end
        end
        inside = keep

        # Σ_a P(a | c) == 1, provided nothing else under the sum mentions `a`.
        for (k, p) in pairs(inside)
            t = terms[p]
            t isa Prob && issubset(t.vars, rest) || continue
            all(q -> q == p || isdisjoint(t.vars, _free_vars(terms[q])), inside) || continue
            rest = setdiff(rest, t.vars)
            deleteat!(inside, k)
            changed = true
            break
        end

        changed || break
    end

    return sort!(outside), inside, rest
end

# Reassemble a narrowed sum, leaving the factors that came out of it where they
# were and putting what remains of the sum where its first factor stood.
function _rebuild_sum(
    terms::Vector{Estimand},
    outside::Vector{Int},
    inside::Vector{Int},
    rest::Vector{Symbol},
)
    summed = marginal(rest, product(terms[inside]))
    at = isempty(inside) ? typemax(Int) : first(inside)

    factors = Estimand[]
    placed = false
    for p in outside
        if !placed && p > at
            push!(factors, summed)
            placed = true
        end
        push!(factors, terms[p])
    end
    placed || push!(factors, summed)

    return product(factors)
end

"""
    product(terms) -> Estimand

Multiply `terms` together.

Nested products are flattened and factors equal to `1` are dropped. A
single-factor product collapses to that factor, and an empty product is `1`.
The order of the remaining factors is preserved.

# Examples

```jldoctest
julia> product([prob(:W; given = [:X]), prob(:Y; given = [:W, :X])])
P(W | X) P(Y | W, X)
```

```jldoctest
julia> product([prob(:Y)])
P(Y)
```
"""
function product(terms)
    flat = Estimand[]
    for t in terms
        if t isa Product
            append!(flat, t.terms)
        else
            push!(flat, t)
        end
    end
    filter!(!isone, flat)
    length(flat) == 1 && return flat[1]
    return Product(flat)
end

"""
    quotient(num, den) -> Estimand

Form the ratio `num / den`.

A denominator of `1` returns `num` unchanged, and a factor appearing on both
sides cancels. When both sides are probability terms sharing the same
conditioning set, and the denominator's variables are a subset of the
numerator's, the ratio collapses to a conditional: `P(a, b | c) / P(b | c)`
becomes `P(a | b, c)`. That is what turns the ratios of marginals produced by
the ID recursion back into ordinary conditionals.

Cancellation assumes the cancelled factor is non-zero, which is the positivity
assumption the identification results are stated under anyway.

# Examples

```jldoctest
julia> quotient(prob([:Y, :Z]; given = [:X]), prob(:Z; given = [:X]))
P(Y | X, Z)
```

The ratio is kept when it is not a conditional, here because the two terms
condition on different things:

```jldoctest
julia> quotient(prob([:Y, :Z]; given = [:X]), prob(:Z))
P(Y, Z | X) / P(Z)
```
"""
function quotient(num::Estimand, den::Estimand)
    isone(den) && return num

    # A factor shared by both sides cancels. Re-entering with one factor fewer
    # on each side lets the remaining rules see through the cancellation.
    nf = _factors(num)
    df = _factors(den)
    for i in eachindex(nf)
        j = findfirst(isequal(nf[i]), df)
        j === nothing && continue
        deleteat!(nf, i)
        deleteat!(df, j)
        return quotient(product(nf), product(df))
    end

    # P(a, b | c) / P(b | c) == P(a | b, c).
    if num isa Prob &&
       den isa Prob &&
       num.given == den.given &&
       issubset(den.vars, num.vars)
        return prob(setdiff(num.vars, den.vars); given = vcat(den.vars, den.given))
    end

    return Quotient(num, den)
end

# --- bound-variable renaming ------------------------------------------------
#
# A summation index that collides with a variable of the surrounding expression
# is ambiguous. We follow convetion and use prime notation.

# Every symbol occurring anywhere, bound or free. Used to pick replacement
# names that cannot collide with anything already in the tree.
_vars_used(e::Prob) = Set{Symbol}(vcat(e.vars, e.given))
_vars_used(e::Marginal) = union(Set{Symbol}(e.index), _vars_used(e.term))
_vars_used(e::Quotient) = union(_vars_used(e.num), _vars_used(e.den))
_vars_used(e::Product) =
    isempty(e.terms) ? Set{Symbol}() : union((_vars_used(t) for t in e.terms)...)

_rename(e::Prob, m::Dict{Symbol,Symbol}) =
    prob([get(m, v, v) for v in e.vars]; given = [get(m, v, v) for v in e.given])
_rename(e::Product, m::Dict{Symbol,Symbol}) =
    Product(Estimand[_rename(t, m) for t in e.terms])
_rename(e::Quotient, m::Dict{Symbol,Symbol}) =
    Quotient(_rename(e.num, m), _rename(e.den, m))

function _rename(e::Marginal, m::Dict{Symbol,Symbol})
    # A nested sum over the same symbol rebinds it, so substitution stops there.
    active = Dict{Symbol,Symbol}(k => v for (k, v) in m if !(k in e.index))
    isempty(active) && return e
    return Marginal(e.index, _rename(e.term, active))
end

# Rename summation indices so that no sum binds a variable that is also used in
# its surrounding context. The result is alpha-equivalent to `e`.
#
# `reserved` names symbols that must not be bound anywhere in the result even if
# they do not occur free in it. Callers pass the variables of the query, whose
# values the estimand is a function of: a sum over `X` reads as ambiguous when
# `X` is the variable being intervened on, whether or not the expression happens
# to be constant in it.
function _freshen(e::Estimand, reserved = Set{Symbol}())
    return _freshen_walk(e, union(_free_vars(e), reserved))
end

# The walk carries `outer`, the names visible from the enclosing context.
_freshen_walk(e::Prob, ::Set{Symbol}) = e
_freshen_walk(e::Product, outer::Set{Symbol}) =
    Product(Estimand[_freshen_walk(t, outer) for t in e.terms])
_freshen_walk(e::Quotient, outer::Set{Symbol}) =
    Quotient(_freshen_walk(e.num, outer), _freshen_walk(e.den, outer))

function _freshen_walk(e::Marginal, outer::Set{Symbol})
    # A replacement name has to avoid capturing something inside this sum's own
    # subtree, and has to stay distinct from the context. Nothing further out
    # matters.
    taken = union(outer, _vars_used(e.term))

    mapping = Dict{Symbol,Symbol}()
    new_index = Symbol[]

    for v in e.index
        if v in outer
            w = Symbol(string(v, "'"))
            while w in taken
                w = Symbol(string(w, "'"))
            end
            mapping[v] = w
            push!(new_index, w)
            push!(taken, w)
        else
            push!(new_index, v)
        end
    end

    term = isempty(mapping) ? e.term : _rename(e.term, mapping)
    return Marginal(sort(new_index), _freshen_walk(term, union(outer, Set(new_index))))
end

# --- printing ---------------------------------------------------------------

# A term is atomic if it never needs parentheses when embedded in a larger
# expression. Only probability terms and the literal 1 qualify.
_is_atomic(::Prob) = true
_is_atomic(e::Product) = isempty(e.terms)
_is_atomic(::Estimand) = false

_wrap(s::AbstractString, e::Estimand) = _is_atomic(e) ? s : "(" * s * ")"

_estimand_str(e::Prob) =
    isempty(e.given) ? "P(" * join(e.vars, ", ") * ")" :
    "P(" * join(e.vars, ", ") * " | " * join(e.given, ", ") * ")"

function _estimand_str(e::Product)
    isempty(e.terms) && return "1"
    return join((_wrap(_estimand_str(t), t) for t in e.terms), " ")
end

function _estimand_str(e::Marginal)
    inner = _estimand_str(e.term)
    # A product under a sum needs no parentheses
    # but a quotient does, to keep the summed factor out of the denominator.
    body = e.term isa Quotient ? "(" * inner * ")" : inner
    return "Σ_{" * join(e.index, ", ") * "} " * body
end

_estimand_str(e::Quotient) =
    _wrap(_estimand_str(e.num), e.num) * " / " * _wrap(_estimand_str(e.den), e.den)

Base.show(io::IO, e::Estimand) = print(io, _estimand_str(e))
Base.show(io::IO, ::MIME"text/plain", e::Estimand) = print(io, _estimand_str(e))

# LaTeX rendering, for documentation.

_latex_wrap(s::AbstractString, e::Estimand) = _is_atomic(e) ? s : "\\left(" * s * "\\right)"

_estimand_latex(e::Prob) =
    isempty(e.given) ? "P(" * join(e.vars, ", ") * ")" :
    "P(" * join(e.vars, ", ") * " \\mid " * join(e.given, ", ") * ")"

function _estimand_latex(e::Product)
    isempty(e.terms) && return "1"
    return join((_latex_wrap(_estimand_latex(t), t) for t in e.terms), " ")
end

function _estimand_latex(e::Marginal)
    inner = _estimand_latex(e.term)
    body = e.term isa Quotient ? "\\left(" * inner * "\\right)" : inner
    return "\\sum_{" * join(e.index, ", ") * "} " * body
end

# \frac already groups both arguments, so neither side needs extra parentheses.
_estimand_latex(e::Quotient) =
    "\\frac{" * _estimand_latex(e.num) * "}{" * _estimand_latex(e.den) * "}"

Base.show(io::IO, ::MIME"text/latex", e::Estimand) =
    print(io, "\$", _estimand_latex(e), "\$")
