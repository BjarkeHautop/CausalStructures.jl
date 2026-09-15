
# `idp` computes P_x(y), the marginal causal effect of x on y, from a PAG.
#
# This is the IDP algorithm of [jaber2022causal](@citet) (Algorithm 1),
# generalizing Tian & Pearl's Q-factorization from ADMGs (`id.jl`) to Markov
# equivalence classes via pc-components (`_pc_component_bitmask`) and regions
# (`_region`), both in `query/buckets.jl`.

# Shared argument checking for `idp` and `cidp`.
function _check_pag_effect_args(
    cg::PAG,
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

function _possible_descendants_closed(cg::PAG, vs)
    acc = Set{Symbol}()
    for v in vs
        union!(acc, possible_descendants(cg, v; open = false))
    end
    return acc
end

function _possible_ancestors_closed(cg::PAG, vs)
    acc = Set{Symbol}()
    for v in vs
        union!(acc, possible_ancestors(cg, v; open = false))
    end
    return acc
end

# Q[T \ B] from Q[T] (Proposition 2). The paper's Eq. 1 writes this as
# `Q[T \ B] = Q[T] / Q[T](T \ PossDe(B))`, but the appendix proof (Eq. 6)
# spells the denominator out as the conditional `Q[T](B | T \ PossDe(B))`:
# restrict Q[T] to `S = B ∪ (T \ PossDe(B))`, condition B on the rest of S,
# then divide Q[T] by that.
function _reduce_bucket(Q::Estimand, T::Vector{Symbol}, bucket::Vector{Symbol}, de_b)
    s = union(bucket, setdiff(T, de_b))
    q_s = marginal(setdiff(T, s), Q)
    cond = quotient(q_s, marginal(bucket, q_s))
    return quotient(Q, cond)
end

# IDENTIFY(C, T, Q), Algorithm 1 lines 3-11.
function _identify(P::PAG, C::Vector{Symbol}, T::Vector{Symbol}, Q::Estimand)
    isempty(C) && return one(Estimand)
    Set(C) == Set(T) && return Q

    induced_T = _induced_pag(P, T)
    C_set = Set(C)
    T_minus_C = setdiff(T, C)

    # Line 6: a bucket B ⊆ T\C whose pc-component in P_T doesn't reach beyond
    # B's own possible descendants can be split off Q[T] directly.
    for bucket in _buckets(induced_T)
        issubset(bucket, T_minus_C) || continue

        b_idx = [node_index(induced_T, v) for v in bucket]
        pc = _pc_component_bitmask(P, induced_T, b_idx)
        Bi = induced_T.backend
        pc_nodes = Set(Bi.nodes[v] for v in eachindex(pc) if pc[v])
        de_b = _possible_descendants_closed(induced_T, bucket)
        issubset(intersect(pc_nodes, de_b), Set(bucket)) || continue

        Qnew = _reduce_bucket(Q, T, bucket, de_b)
        return _identify(P, C, setdiff(T, bucket), Qnew)
    end

    # Line 9: split C through the region of one of P_C's buckets.
    induced_C = _induced_pag(P, C)
    for bucket in _buckets(induced_C)
        r_b = _region(P, bucket, C)
        Set(r_b) == C_set && continue

        rest = setdiff(C, r_b)
        r_rest = _region(P, rest, C)

        num1 = _identify(P, r_b, T, Q)
        num1 === nothing && return nothing
        num2 = _identify(P, r_rest, T, Q)
        num2 === nothing && return nothing
        overlap = sort!(collect(intersect(Set(r_b), Set(r_rest))))
        den = _identify(P, overlap, T, Q)
        den === nothing && return nothing

        return quotient(product(Estimand[num1, num2]), den)
    end

    return nothing
end

"""
    idp(cg::PAG, x, y) -> Union{Estimand,Nothing}

Return the interventional distribution `P(y | do(x))` as an [`Estimand`](@ref),
or `nothing` if the effect is not identifiable from the PAG `cg`.

This is the IDP algorithm of [jaber2022causal](@citet), complete for
identifying marginal effects from a partial ancestral graph (a Markov
equivalence class of causal diagrams), generalizing [`id`](@ref) from a single
[`ADMG`](@ref) to the equivalence-class setting.

`x` and `y` may each be a `Symbol` or a vector of them, and must be disjoint.

# Examples

Effect identifiable through a witnessed backdoor:

```jldoctest
julia> mag = MAG("B --> X, A <-> X, A --> Y, X --> Y");

julia> pag = mag_to_pag(mag);

julia> idp(pag, :X, :Y) === nothing
false
```

Effect not identifiable, since the PAG has no orientable structure at all
(every conditional independence in the underlying equivalence class is
consistent with several different causal directions):

```jldoctest
julia> pag = mag_to_pag(MAG("Z --> X, Z --> Y, X --> Y"));

julia> idp(pag, :X, :Y) === nothing
true
```

# References

- [jaber2022causal](@citet)
- [tian2002general](@citet)
"""
function idp(cg::PAG, x, y)
    xs = sort(unique(_as_symbols(x)))
    ys = sort(unique(_as_symbols(y)))
    _check_pag_effect_args(cg, xs, ys, Symbol[])

    minus_x = _induced_pag(cg, setdiff(nodes(cg), xs))
    d = sort!(collect(_possible_ancestors_closed(minus_x, ys)))

    result = _identify(cg, d, sort(nodes(cg)), prob(nodes(cg)))
    result === nothing && return nothing
    return _freshen(marginal(setdiff(d, ys), result), Set{Symbol}(vcat(xs, ys)))
end
