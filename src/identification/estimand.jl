"""
    Estimand

A symbolic causal estimand: a formula expressed purely in terms of the
observational distribution, as an immutable expression tree. Build one with
the smart constructors [`prob`](@ref), [`marginal`](@ref), [`product`](@ref),
and [`quotient`](@ref).

A single concrete type covers every node of the tree, tagged by `kind`; the
fields double up across kinds rather than one field per possible meaning:

# Fields
- `kind::Symbol`: one of `:prob`, `:marginal`, `:product`, `:quotient`.
- `vars::Vector{Symbol}`: a `:prob` node's head, or a `:marginal` node's
  summation index. Empty for `:product`/`:quotient`.
- `given::Vector{Symbol}`: a `:prob` node's conditioning set. Empty otherwise.
- `terms::Vector{Estimand}`: a `:marginal` node's single summand (as a
  one-element vector), a `:product` node's factors, or a `:quotient` node's
  `[numerator, denominator]`. Empty for `:prob`.

# Output formats

It can be rendered as text or as LaTeX:

```jldoctest
julia> e = marginal([:Z], product([prob(:Y; given = [:X, :Z]), prob(:Z)]));

julia> string(e)
"Σ_{Z} P(Y | X, Z) P(Z)"

julia> e.kind
:marginal

julia> e.vars
1-element Vector{Symbol}:
 :Z
```

The LaTeX form comes from the `MIME"text/latex"` method, so
`repr(MIME("text/latex"), e)` gives `\$\\sum_{Z} P(Y \\mid X, Z) P(Z)\$`,
used for frontend documentation.
"""
struct Estimand
    kind::Symbol
    vars::Vector{Symbol}
    given::Vector{Symbol}
    terms::Vector{Estimand}
end

# Low-level node builders, bypassing the smart constructors' simplification.
_prob_node(vars, given) = Estimand(:prob, vars, given, Estimand[])
_marginal_node(index, term) = Estimand(:marginal, index, Symbol[], Estimand[term])
_product_node(terms) = Estimand(:product, Symbol[], Symbol[], terms)
_quotient_node(num, den) = Estimand(:quotient, Symbol[], Symbol[], Estimand[num, den])

# A `:marginal` node's summand, or a `:quotient` node's numerator/denominator.
_term(e::Estimand) = e.terms[1]
_num(e::Estimand) = e.terms[1]
_den(e::Estimand) = e.terms[2]

# The multiplicative identity, produced by `product(Estimand[])` and by
# `marginal` when everything has been summed out.
const _ONE = _product_node(Estimand[])

Base.one(::Type{Estimand}) = _ONE
Base.isone(e::Estimand) = e.kind === :product && isempty(e.terms)

# --- equality and hashing ---------------------------------------------------

Base.:(==)(a::Estimand, b::Estimand) =
    a.kind == b.kind && a.vars == b.vars && a.given == b.given && a.terms == b.terms

Base.hash(e::Estimand, h::UInt) =
    hash(e.terms, hash(e.given, hash(e.vars, hash(e.kind, h))))

# --- free variables ---------------------------------------------------------

# The variables an expression is a function of. A summation index is bound by
# the sum that introduces it, so it is not free in that sum.
function _free_vars(e::Estimand)
    if e.kind === :prob
        return Set{Symbol}(vcat(e.vars, e.given))
    elseif e.kind === :marginal
        return setdiff(_free_vars(_term(e)), Set(e.vars))
    elseif e.kind === :quotient
        return union(_free_vars(_num(e)), _free_vars(_den(e)))
    else
        acc = Set{Symbol}()
        for t in e.terms
            union!(acc, _free_vars(t))
        end
        return acc
    end
end

# The factors of an expression, as a fresh vector the caller may mutate.
_factors(e::Estimand) = e.kind === :product ? copy(e.terms) : Estimand[e]

# --- smart constructors -----------------------------------------------------

"""
    prob(vars; given = Symbol[]) -> Estimand

Build the probability term `P(vars | given)`.

`vars` may be a single `Symbol` or a vector of them. Both lists are sorted and
de-duplicated, and any variable appearing in `given` is dropped from `vars`
(since `P(X, Y | X) = P(Y | X)`). A term left with an empty head is the
constant `1`.

# Arguments
- `vars`: a single `Symbol` or a vector of them, the head of the probability term.

# Keywords
- `given = Symbol[]`: the conditioning variable(s).

# Returns
An [`Estimand`](@ref).

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
    return _prob_node(v, g)
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
under the sum mentions, sums to `1` and drops out. Under a ratio, the part of
the index the denominator does not mention is summed in the numerator alone.

# Arguments
- `index`: the variable(s) to sum over.
- `term::Estimand`: the expression being summed.

# Returns
An [`Estimand`](@ref).

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
    if term.kind === :prob && issubset(idx, term.vars)
        return prob(setdiff(term.vars, idx); given = term.given)
    end

    # Σ_a Σ_b f  ==  Σ_{a, b} f
    term.kind === :marginal && return marginal(union(idx, term.vars), _term(term))

    # Σ_{a, b} (f / g) == Σ_b ((Σ_a f) / g), when g does not mention a.
    if term.kind === :quotient
        den_vars = _free_vars(_den(term))
        inner = filter(v -> !(v in den_vars), idx)
        if !isempty(inner)
            outer = filter(in(den_vars), idx)
            return marginal(outer, quotient(marginal(inner, _num(term)), _den(term)))
        end
    end

    if term.kind === :product
        outside, inside, rest = _narrow_sum(term.terms, idx)
        # Anything pulled out or dropped shrinks the summand, so re-entering
        # `marginal` here terminates.
        length(inside) == length(term.terms) ||
            return _rebuild_sum(term.terms, outside, inside, rest)
    end

    return _marginal_node(idx, term)
end

# Sort the positions of a summed product's factors into those that can leave the
# sum and those that must stay, along with the summation index the latter still
# need. The two rewrites run to a fixpoint: dropping a factor that sums to one
# can leave further factors constant in what remains of the index.
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
            t.kind === :prob && issubset(t.vars, rest) || continue
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

# Arguments
- `terms`: the factors to multiply.

# Returns
An [`Estimand`](@ref).

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
        if t.kind === :product
            append!(flat, t.terms)
        else
            push!(flat, t)
        end
    end
    filter!(!isone, flat)
    length(flat) == 1 && return flat[1]
    return _product_node(flat)
end

"""
    quotient(num, den) -> Estimand

Form the ratio `num / den`.

A denominator of `1` returns `num` unchanged. When the denominator is itself
`a / b` and the numerator is exactly `a`, the ratio collapses to `b`; this is
what most often turns the divisions performed while identifying a PAG effect
back into something readable. Otherwise, a factor appearing on both sides
cancels, and a numerator factor and a denominator factor related by the chain
rule `P(a, b | c) = P(a | b, c) P(b | c)` divide out: `P(a, b | c) / P(b | c)`
becomes `P(a | b, c)`, and `P(a, b | c) / P(a | b, c)` becomes `P(b | c)`.
That is what turns the ratios of marginals produced by the ID recursion back
into ordinary conditionals.

Cancellation assumes the cancelled factor is non-zero, which is the positivity
assumption the identification results are stated under anyway.

# Arguments
- `num::Estimand`: the numerator.
- `den::Estimand`: the denominator.

# Returns
An [`Estimand`](@ref).

# Examples

```jldoctest
julia> quotient(prob([:Y, :Z]; given = [:X]), prob(:Z; given = [:X]))
P(Y | X, Z)
```

```jldoctest
julia> quotient(prob([:W, :Y, :Z]), prob(:W; given = [:Y, :Z]))
P(Y, Z)
```

```jldoctest
julia> a = quotient(prob([:Y, :Z]), prob(:X));

julia> b = marginal(:W, quotient(prob([:W, :Y, :Z]), prob(:W; given = [:X])));

julia> quotient(a, quotient(a, b))
Σ_{W} (P(W, Y, Z) / P(W | X))
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

    # a / (a / b) == b.
    den.kind === :quotient && num == _num(den) && return _den(den)

    # A factor shared by both sides cancels, and a pair of probability terms
    # related by the chain rule divides out. Re-entering with one factor fewer
    # in the denominator lets the remaining rules see through the result.
    nf = _factors(num)
    df = _factors(den)
    for i in eachindex(nf), j in eachindex(df)
        r = _divide_factors(nf[i], df[j])
        r === nothing && continue
        nf[i] = r
        deleteat!(df, j)
        return quotient(product(nf), product(df))
    end

    return _quotient_node(num, den)
end

# The ratio `n / d` of two factors when it simplifies to a single factor, or
# `nothing`. Both simplifications are the chain rule
# `P(a, b | c) = P(a | b, c) P(b | c)`, read with either factor as divisor.
function _divide_factors(n::Estimand, d::Estimand)
    n == d && return _ONE
    (n.kind === :prob && d.kind === :prob) || return nothing

    issubset(d.vars, n.vars) || return nothing

    # P(a, b | c) / P(b | c) == P(a | b, c).
    d.given == n.given &&
        return prob(setdiff(n.vars, d.vars); given = vcat(d.vars, d.given))

    # P(a, b | c) / P(a | b, c) == P(b | c).
    rest = setdiff(n.vars, d.vars)
    d.given == sort(vcat(rest, n.given)) && return prob(rest; given = n.given)

    return nothing
end

# --- bound-variable renaming ------------------------------------------------
#
# A summation index colliding with a variable of the surrounding expression is
# ambiguous; renamed with prime notation.

# Every symbol occurring anywhere, bound or free. Used to pick replacement
# names that cannot collide with anything already in the tree.
function _vars_used(e::Estimand)
    if e.kind === :prob
        return Set{Symbol}(vcat(e.vars, e.given))
    elseif e.kind === :marginal
        return union(Set{Symbol}(e.vars), _vars_used(_term(e)))
    elseif e.kind === :quotient
        return union(_vars_used(_num(e)), _vars_used(_den(e)))
    else
        acc = Set{Symbol}()
        for t in e.terms
            union!(acc, _vars_used(t))
        end
        return acc
    end
end

function _rename(e::Estimand, m::Dict{Symbol,Symbol})
    if e.kind === :prob
        return prob([get(m, v, v) for v in e.vars]; given = [get(m, v, v) for v in e.given])
    elseif e.kind === :product
        return _product_node(Estimand[_rename(t, m) for t in e.terms])
    elseif e.kind === :quotient
        return _quotient_node(_rename(_num(e), m), _rename(_den(e), m))
    else
        # A nested sum over the same symbol rebinds it, so substitution stops there.
        active = Dict{Symbol,Symbol}(k => v for (k, v) in m if !(k in e.vars))
        isempty(active) && return e
        return _marginal_node(e.vars, _rename(_term(e), active))
    end
end

# Rename summation indices so that no sum binds a variable also used in its
# surrounding context. The result is alpha-equivalent to `e`.
#
# `reserved` names symbols that must not be bound anywhere in the result even
# if they do not occur free in it: callers pass the query variables, since a
# sum over `X` reads as ambiguous whenever `X` is the intervened-on variable.
function _freshen(e::Estimand, reserved = Set{Symbol}())
    return _freshen_walk(e, union(_free_vars(e), reserved))
end

# The walk carries `outer`, the names visible from the enclosing context.
function _freshen_walk(e::Estimand, outer::Set{Symbol})
    if e.kind === :prob
        return e
    elseif e.kind === :product
        return _product_node(Estimand[_freshen_walk(t, outer) for t in e.terms])
    elseif e.kind === :quotient
        return _quotient_node(_freshen_walk(_num(e), outer), _freshen_walk(_den(e), outer))
    else
        # A replacement name must avoid capturing something inside this sum's
        # own subtree and stay distinct from the context.
        taken = union(outer, _vars_used(_term(e)))

        mapping = Dict{Symbol,Symbol}()
        new_index = Symbol[]

        for v in e.vars
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

        term = isempty(mapping) ? _term(e) : _rename(_term(e), mapping)
        return _marginal_node(
            sort(new_index),
            _freshen_walk(term, union(outer, Set(new_index))),
        )
    end
end

# --- printing ---------------------------------------------------------------

# A term is atomic if it never needs parentheses when embedded in a larger
# expression. Only probability terms and the literal 1 qualify.
_is_atomic(e::Estimand) = e.kind === :prob || (e.kind === :product && isempty(e.terms))

_wrap(s::AbstractString, e::Estimand) = _is_atomic(e) ? s : "(" * s * ")"

function _estimand_str(e::Estimand)
    if e.kind === :prob
        return isempty(e.given) ? "P(" * join(e.vars, ", ") * ")" :
               "P(" * join(e.vars, ", ") * " | " * join(e.given, ", ") * ")"
    elseif e.kind === :product
        isempty(e.terms) && return "1"
        return join(String[_wrap(_estimand_str(t), t) for t in e.terms], " ")
    elseif e.kind === :marginal
        inner = _estimand_str(_term(e))
        # A product under a sum needs no parentheses
        # but a quotient does, to keep the summed factor out of the denominator.
        body = _term(e).kind === :quotient ? "(" * inner * ")" : inner
        return "Σ_{" * join(e.vars, ", ") * "} " * body
    else
        return _wrap(_estimand_str(_num(e)), _num(e)) *
               " / " *
               _wrap(_estimand_str(_den(e)), _den(e))
    end
end

Base.show(io::IO, e::Estimand) = print(io, _estimand_str(e))
Base.show(io::IO, ::MIME"text/plain", e::Estimand) = print(io, _estimand_str(e))

# LaTeX rendering, for documentation.

_latex_wrap(s::AbstractString, e::Estimand) = _is_atomic(e) ? s : "\\left(" * s * "\\right)"

function _estimand_latex(e::Estimand)
    if e.kind === :prob
        return isempty(e.given) ? "P(" * join(e.vars, ", ") * ")" :
               "P(" * join(e.vars, ", ") * " \\mid " * join(e.given, ", ") * ")"
    elseif e.kind === :product
        isempty(e.terms) && return "1"
        return join(String[_latex_wrap(_estimand_latex(t), t) for t in e.terms], " ")
    elseif e.kind === :marginal
        inner = _estimand_latex(_term(e))
        body = _term(e).kind === :quotient ? "\\left(" * inner * "\\right)" : inner
        return "\\sum_{" * join(e.vars, ", ") * "} " * body
    else
        # \frac already groups both arguments, so neither side needs extra parentheses.
        return "\\frac{" * _estimand_latex(_num(e)) * "}{" * _estimand_latex(_den(e)) * "}"
    end
end

Base.show(io::IO, ::MIME"text/latex", e::Estimand) =
    print(io, "\$", _estimand_latex(e), "\$")
