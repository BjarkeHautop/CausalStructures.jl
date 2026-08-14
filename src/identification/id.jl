
# `id` computes P(y | do(x)) and `idc` computes P(y | do(x), z).
#
# Returns the *closed* ancestor set of `vs`, which is what An(Y) denotes
# throughout Figure 4 of Shpitser & Pearl (2008).
function _ancestors_of(cg::ADMG, vs)
    acc = Set{Symbol}()
    for v in vs
        union!(acc, ancestors(cg, v; open = false))
    end
    return [v for v in nodes(cg) if v in acc]
end

# G_x̄ in the paper: delete every edge with an arrowhead at a member of `xs`.
# That covers both v --> x and v <-> x.
function _remove_incoming(cg::ADMG, xs)
    x_set = Set(xs)
    kept = CausalEdge[]
    for e in edges(cg)
        (e.dst in x_set && e.dst_end == Arrow) && continue
        (e.src in x_set && e.src_end == Arrow) && continue
        push!(kept, e)
    end
    # Deleting edges cannot introduce a cycle or otherwise break an ADMG.
    return ADMG(Set(nodes(cg)), kept; validate = false)
end

# G_z̲ in the paper: delete every directed edge out of a member of `zs`.
# Bidirected edges are left alone.
function _remove_outgoing(cg::ADMG, zs)
    z_set = Set(zs)
    kept = CausalEdge[]
    for e in edges(cg)
        (e.src in z_set && e.src_end == Tail && e.dst_end == Arrow) && continue
        (e.dst in z_set && e.dst_end == Tail && e.src_end == Arrow) && continue
        push!(kept, e)
    end
    return ADMG(Set(nodes(cg)), kept; validate = false)
end

function _topological_order(cg::ADMG)
    directed_edges = [e for e in edges(cg) if e.src_end == Tail && e.dst_end == Arrow]
    return topological_sort(DAG(Set(nodes(cg)), directed_edges; validate = false))
end

# The conditional of the i-th variable in `order` given its predecessors, taken
# with respect to the distribution `P` over `vs`.
function _conditional(P::Estimand, vs, order, i::Int)
    predecessors = order[1:(i-1)]

    if P isa Prob && isempty(P.given) && Set(P.vars) == Set(vs)
        return prob(order[i]; given = predecessors)
    end

    numerator = marginal(setdiff(vs, order[1:i]), P)

    # Every distribution reaching this point is normalized over its own domain
    # so the denominator for the first variable in the order is Σ_vs P = 1.
    isempty(predecessors) && return numerator

    return quotient(numerator, marginal(setdiff(vs, predecessors), P))
end

# ∏_{V_i ∈ s} P(v_i | v_π^(i-1)), the factorization used by lines 6 and 7.
function _factorize(P::Estimand, vs, order, s)
    s_set = Set(s)
    factors = Estimand[]
    for i in eachindex(order)
        order[i] in s_set || continue
        push!(factors, _conditional(P, vs, order, i))
    end
    return product(factors)
end

# The ID recursion. Line numbers refer to Figure 4 of Shpitser & Pearl (2008).
function _id(y::Vector{Symbol}, x::Vector{Symbol}, P::Estimand, cg::ADMG)
    vs = nodes(cg)

    # Line 1: nothing left to intervene on, so marginalize.
    isempty(x) && return marginal(setdiff(vs, y), P)

    # Line 2: nodes outside An(Y) are irrelevant; drop them and recurse.
    an_y = _ancestors_of(cg, y)
    if !isempty(setdiff(vs, an_y))
        return _id(
            y,
            intersect(x, an_y),
            marginal(setdiff(vs, an_y), P),
            subgraph(cg, an_y),
        )
    end

    # Line 3: intervening on W as well changes nothing, and may expose more
    # structure. W is the set of nodes that are not ancestors of Y once the
    # edges into X are cut.
    w = setdiff(setdiff(vs, x), _ancestors_of(_remove_incoming(cg, x), y))
    !isempty(w) && return _id(y, union(x, w), P, cg)

    # Lines 4-7 turn on the district structure of G \ X.
    components = districts(subgraph(cg, setdiff(vs, x)))

    # Line 4: the effect factorizes over the districts of G \ X.
    if length(components) > 1
        factors = Estimand[]
        for s in components
            factor = _id(s, setdiff(vs, s), P, cg)
            factor === nothing && return nothing
            push!(factors, factor)
        end
        return marginal(setdiff(vs, union(y, x)), product(factors))
    end

    s = components[1]
    cg_districts = districts(cg)

    # Line 5: G is a single district, so S and G form a hedge; the effect is
    # not identifiable.
    length(cg_districts) == 1 && return nothing

    order = _topological_order(cg)

    # Line 6: S is itself a district of G, so Q[S] factorizes directly.
    s_set = Set(s)
    any(c -> Set(c) == s_set, cg_districts) &&
        return marginal(setdiff(s, y), _factorize(P, vs, order, s))

    # Line 7: S sits strictly inside a district S' of G. Recurse into S' with
    # Q[S'] in place of P.
    idx = findfirst(c -> issubset(s_set, Set(c)), cg_districts)
    s_prime = cg_districts[idx]
    return _id(
        y,
        intersect(x, s_prime),
        _factorize(P, vs, order, s_prime),
        subgraph(cg, s_prime),
    )
end

# Shared argument checking for `id` and `idc`.
function _check_effect_args(
    cg::ADMG,
    x::Vector{Symbol},
    y::Vector{Symbol},
    z::Vector{Symbol},
)
    all_ns = Set(nodes(cg))
    for (name, vs) in (("x", x), ("y", y), ("z", z))
        for v in vs
            v in all_ns || error("Unknown node in $(name): $(v)")
        end
    end

    isempty(y) && error("y must be non-empty")
    isempty(x) && error("x must be non-empty")

    !isempty(intersect(x, y)) && error("x and y must be disjoint")
    !isempty(intersect(x, z)) && error("x and z must be disjoint")
    !isempty(intersect(y, z)) && error("y and z must be disjoint")

    return nothing
end

"""
    id(cg::Union{DAG,ADMG}, x, y) -> Union{Estimand,Nothing}

Return the interventional distribution `P(y | do(x))` as an [`Estimand`](@ref),
or `nothing` if the effect is not identifiable.

This is the ID algorithm of [shpitser2008complete](@cite).

`x` and `y` may each be a `Symbol` or a vector of them, and must be disjoint.

Bidirected edges represent latent confounders. To identify an effect in a
[`DAG`](@ref) with unobserved variables, project them out first with
[`latent_project`](@ref).

!!! note "Extra free variables"
    The returned formula may mention variables outside `x` and `y`. Line 3 of
    the algorithm enlarges the intervention set by a set `W` whenever
    intervening on `W` provably changes nothing, and the resulting expression
    is then a function of those values too.

# Examples

Back-door adjustment is recovered as the g-formula:

```jldoctest
julia> dag = cgraph("Z --> X + Y, X --> Y"; class = DAG);

julia> id(dag, :X, :Y)
Σ_{Z} P(Y | X, Z) P(Z)
```

The front-door graph, where `X` and `Y` are confounded but the effect is still
identifiable through the mediator `M`:

```jldoctest
julia> admg = cgraph("X --> M, M --> Y, X <-> Y"; class = ADMG);

julia> id(admg, :X, :Y)
Σ_{M} P(M | X) (Σ_{X'} P(X') P(Y | M, X'))
```

The inner sum ranges over a value of `X` distinct from the one intervened on, so
it is printed under a primed name; summation indices are always renamed away
from the variables of the query.

The bow arc, the canonical unidentifiable effect:

```jldoctest
julia> bow = cgraph("X --> Y, X <-> Y"; class = ADMG);

julia> id(bow, :X, :Y) === nothing
true
```

# References

- [shpitser2008complete](@cite)
- [tian2002general](@cite)
"""
function id(cg::ADMG, x, y)
    xs = _as_symbols(x)
    ys = _as_symbols(y)
    _check_effect_args(cg, xs, ys, Symbol[])

    result = _id(sort(unique(ys)), sort(unique(xs)), prob(nodes(cg)), cg)
    return result === nothing ? nothing : _freshen(result, Set{Symbol}(vcat(xs, ys)))
end

id(cg::DAG, x, y) = id(reclass(cg, ADMG), x, y)

"""
    idc(cg::Union{DAG,ADMG}, x, y; given) -> Union{Estimand,Nothing}

Return the conditional interventional distribution `P(y | do(x), given)` as an
[`Estimand`](@ref), or `nothing` if it is not identifiable.

This is the IDC algorithm of [shpitser2008complete](@cite). Each variable in
`given` that satisfies rule 2 of do-calculus is moved from the conditioning set
into the intervention set; whatever remains is handled by [`id`](@ref) and
normalized:

```math
P(y | do(x), z) = ID(y ∪ z, x) / Σ_y ID(y ∪ z, x)
```

`x`, `y`, and `given` must be pairwise disjoint. With an empty
`given` this reduces to [`id`](@ref).

# Examples

```jldoctest
julia> dag = cgraph("Z --> X + Y, X --> Y"; class = DAG);

julia> idc(dag, :X, :Y; given = :Z)
P(Y | X, Z)
```

Conditioning on the mediator of the front-door graph leaves an effect that no
longer depends on the intervened value at all:

```jldoctest
julia> admg = cgraph("X --> M, M --> Y, X <-> Y"; class = ADMG);

julia> idc(admg, :X, :Y; given = :M)
Σ_{X'} P(X') P(Y | M, X')
```

# References

- [shpitser2008complete](@cite)
"""
function idc(cg::ADMG, x, y; given = Symbol[])
    xs = sort(unique(_as_symbols(x)))
    ys = sort(unique(_as_symbols(y)))
    zs = sort(unique(_as_symbols(given)))
    _check_effect_args(cg, xs, ys, zs)

    result = _idc(ys, xs, zs, cg)
    return result === nothing ? nothing : _freshen(result, Set{Symbol}(vcat(xs, ys, zs)))
end

idc(cg::DAG, x, y; given = Symbol[]) = idc(reclass(cg, ADMG), x, y; given)

function _idc(y::Vector{Symbol}, x::Vector{Symbol}, z::Vector{Symbol}, cg::ADMG)
    # Rule 2 of do-calculus: if Y is m-separated from Z_i given the rest, in
    # the graph with edges into X and out of Z_i cut, then conditioning on Z_i
    # is the same as intervening on it. Moving it across shrinks the
    # conditioning set, so the loop terminates.
    for z_i in z
        rest = setdiff(z, [z_i])
        mutilated = _remove_outgoing(_remove_incoming(cg, x), [z_i])
        if m_separated(mutilated, y, [z_i], vcat(x, rest))
            return _idc(y, sort(union(x, [z_i])), rest, cg)
        end
    end

    # Once rule 2 has emptied the conditioning set, Σ_y ID(y, x) is identically
    # 1, so there is nothing left to normalize by.
    isempty(z) && return _id(y, x, prob(nodes(cg)), cg)

    joint = _id(sort(union(y, z)), x, prob(nodes(cg)), cg)
    joint === nothing && return nothing

    return quotient(joint, marginal(y, joint))
end
