
# `cidp` computes P_x(y | z), the conditional causal effect, from a PAG.
#
# CIDP algorithm of [jaber2022causal](@citet) (Algorithm 2): Phase I and
# Phase II below flip pieces between X and the conditioning set, then
# Phase III hands the result to [`idp`](@ref).

# D = PossAn(Y ∪ Z) in the subgraph of `cg` induced on V \ X.
function _cidp_frontier(cg::PAG, x, target)
    minus_x = _induced_pag(cg, setdiff(nodes(cg), x))
    return _possible_ancestors_closed(minus_x, target)
end

# Phase I: flip bucket-pieces of X across the D boundary into Z, via
# Theorem 1 rule 2 in the reverse direction (Observation 3). Returns updated
# `(x, z)`, or `nothing` if some straddling bucket cannot be resolved.
function _cidp_phase1(
    cg::PAG,
    buckets,
    x::Vector{Symbol},
    y::Vector{Symbol},
    z::Vector{Symbol},
)
    d = _cidp_frontier(cg, x, union(y, z))
    progress = true
    while progress
        progress = false
        for bucket in buckets
            bset = Set(bucket)
            overlap = intersect(bset, d)
            (isempty(overlap) || issubset(bset, d)) && continue

            x_prime = sort!(collect(intersect(bset, Set(x))))
            isempty(x_prime) && return nothing  # straddling bucket has no X part to flip

            w = setdiff(x, x_prime)
            manip = _pag_upper_lower_manipulate(cg, w, x_prime)
            _definite_m_separated(manip, x_prime, y, union(w, z)) || return nothing

            x = w
            z = sort(union(z, x_prime))
            d = _cidp_frontier(cg, x, union(y, z))
            progress = true
            break
        end
    end
    return x, z
end

# Phase II: flip bucket-pieces of Z into X wherever rule 2 allows
# (Observation 2). Always succeeds (pieces that don't qualify simply stay in
# Z); returns updated `(x, z)`.
function _cidp_phase2(
    cg::PAG,
    buckets,
    x::Vector{Symbol},
    y::Vector{Symbol},
    z::Vector{Symbol},
)
    progress = true
    while progress
        progress = false
        for bucket in buckets
            z_i = sort!(collect(intersect(Set(bucket), Set(z))))
            isempty(z_i) && continue

            rest = setdiff(z, z_i)
            manip = _pag_upper_lower_manipulate(cg, x, z_i)
            _definite_m_separated(manip, z_i, y, union(x, rest)) || continue

            x = sort(union(x, z_i))
            z = rest
            progress = true
            break
        end
    end
    return x, z
end

"""
    cidp(cg::PAG, x, y; given) -> Union{Estimand,Nothing}

Return the conditional interventional distribution `P(y | do(x), given)` as an
[`Estimand`](@ref), or `nothing` if it is not identifiable from the PAG `cg`.

This is the CIDP algorithm of [jaber2022causal](@citet), complete for
identifying conditional effects from a partial ancestral graph, generalizing
[`idc`](@ref) from a single [`ADMG`](@ref) to the equivalence-class setting.

`x`, `y`, and `given` must be pairwise disjoint. With an empty `given` this
reduces to [`idp`](@ref).

# Examples

Effect identifiable through a witnessed backdoor, conditioning on the
confounder:

```jldoctest
julia> mag = MAG("B --> X, A <-> X, A --> Y, X --> Y");

julia> pag = mag_to_pag(mag);

julia> cidp(pag, :X, :Y; given = :A) === nothing
false
```

Effect not identifiable, for the same reason as in [`idp`](@ref)'s example:

```jldoctest
julia> pag = mag_to_pag(MAG("Z --> X, Z --> Y, X --> Y"));

julia> cidp(pag, :X, :Y; given = :Z) === nothing
true
```

# References

- [jaber2022causal](@citet)
"""
function cidp(cg::PAG, x, y; given = Symbol[])
    x0 = sort(unique(_as_symbols(x)))
    y0 = sort(unique(_as_symbols(y)))
    z0 = sort(unique(_as_symbols(given)))
    _check_pag_effect_args(cg, x0, y0, z0)

    buckets = _buckets(cg)

    phase1 = _cidp_phase1(cg, buckets, x0, y0, z0)
    phase1 === nothing && return nothing
    xs, zs = phase1

    xs, zs = _cidp_phase2(cg, buckets, xs, y0, zs)

    # Phase I can flip all of X into the conditioning set (Observation 3): with
    # nothing left to intervene on, the "marginal effect" of Phase III is just
    # the observational marginal of y0 ∪ zs, since do(∅) is not an
    # intervention at all. `idp` itself requires a non-empty treatment set, so
    # that degenerate case is handled directly here instead.
    e = if isempty(xs)
        marginal(setdiff(nodes(cg), union(y0, zs)), prob(nodes(cg)))
    else
        idp(cg, xs, union(y0, zs))
    end
    e === nothing && return nothing

    isempty(zs) && return e
    raw = quotient(e, marginal(y0, e))
    return _freshen(raw, Set{Symbol}(vcat(x0, y0, z0)))
end
