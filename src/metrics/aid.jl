# Adjustment Identification Distance (Henckel, Würtzen & Weichwald 2024): for
# each ordered pair (T, Y), an adjustment-based identification strategy is
# applied to cg_guess to obtain a claim about the effect of T on Y, which is
# then checked against cg_true using the Generalized Adjustment Criterion.

_poss_descendants(cg::DAG, t::Symbol) = descendants(cg, t)
_poss_descendants(cg::AbstractPDAG, t::Symbol) = possible_descendants(cg, t)

_poss_ancestors(cg::DAG, t::Symbol) = ancestors(cg, t)
_poss_ancestors(cg::AbstractPDAG, t::Symbol) = possible_ancestors(cg, t)

# (G, T, Y) is amenable if no proper possibly directed path from T to Y starts
# with an undirected edge (Perkovic et al. 2018); DAGs have no undirected
# edges and so are always amenable. Identifiability coincides with
# amenability (Henckel, Würtzen & Weichwald 2024, Proposition 16).
_amenable(::DAG, ::Symbol, ::Symbol) = true

function _amenable(cg::AbstractPDAG, t::Symbol, y::Symbol)
    B = cg.backend
    # Excluding every node from the directed-first-step branch leaves only
    # paths whose first edge out of t is undirected.
    reach = _b_possibly_causal_reachable(
        B,
        node_index(cg, t),
        _children_slice;
        excluded = trues(length(B.nodes)),
    )
    return !reach[node_index(cg, y)]
end

# The adjustment set cg_guess proposes for the effect of t on y, or `nothing`
# if it claims a zero effect instead. Parent-AID's branch condition is
# whether y is literally a parent of t (Henckel, Würtzen & Weichwald 2024,
# Example 2): unlike the other two strategies, it is not keyed on whether y is
# a possible descendant of t, since Pa(t) is used as the adjustment set for
# every y that is not itself a parent of t, descendant or not.
function _aid_claimed_set(type::Symbol, cg::CausalGraph, t::Symbol, y::Symbol)
    if type === :parent
        pa = parents(cg, t)
        return y in pa ? nothing : pa
    elseif type === :ancestor
        return y in _poss_descendants(cg, t) ? _poss_ancestors(cg, t) : nothing
    elseif type === :oset
        y in _poss_descendants(cg, t) || return nothing
        return something(adjustment_set(cg, t, y; type = :optimal), Symbol[])
    end
    throw(
        ArgumentError(
            "Unknown aid type $(repr(type)) (expected :parent, :ancestor, or :oset)",
        ),
    )
end

# Whether the guess's identification claim for (t, y) is wrong in cg_true.
function _aid_mistake(
    type::Symbol,
    cg_true::Union{DAG,AbstractPDAG},
    cg_guess::Union{DAG,AbstractPDAG},
    t::Symbol,
    y::Symbol,
)
    if !_amenable(cg_guess, t, y)
        # Guess claims the effect is not identifiable; correct iff it truly isn't.
        return _amenable(cg_true, t, y)
    end
    z = _aid_claimed_set(type, cg_guess, t, y)
    if z === nothing
        # Guess claims a zero effect; correct iff y truly cannot be affected by t.
        return y in _poss_descendants(cg_true, t)
    end
    return !is_valid_adjustment(cg_true, t, y, z)
end

"""
    aid(cg_true::Union{DAG,AbstractPDAG}, cg_guess::Union{DAG,AbstractPDAG};
        type::Symbol = :oset, normalized::Bool = false) -> Real

Adjustment Identification Distance (AID) [henckel2024aid](@cite) from
`cg_guess` to `cg_true`. For every ordered pair of distinct nodes `(T, Y)`, an
adjustment-based identification strategy applied to `cg_guess` is checked
against `cg_true` and counted as a mistake if it is wrong there. `cg_true` and
`cg_guess` must have the same node set; they may be of different graph classes
([`DAG`](@ref) or any [`AbstractPDAG`](@ref)).

`type` selects the identification strategy:

- `:parent` (Parent-AID): proposes `parents(cg_guess, T)`, coinciding with the
  structural intervention distance (SID) for `DAG`s.
- `:ancestor` (Ancestor-AID): proposes the ancestors of `T`, which makes the
  distance zero whenever `cg_guess` respects the causal order of `cg_true`.
- `:oset` (Oset-AID, default): proposes the statistically optimal adjustment
  set ([`adjustment_set`](@ref) with `type = :optimal`).

Outside the pairs its adjustment set applies to (`Y` not a possible descendant
of `T` in `cg_guess`, or, for `:parent`, `Y` itself a parent of `T`), the
strategy instead claims a zero effect, correct iff `Y` is not a possible
descendant of `T` in `cg_true`. For an `AbstractPDAG` guess where `(cg_guess, T,
Y)` is not amenable, the strategy claims the effect is not identifiable,
correct iff `(cg_true, T, Y)` is not amenable either.

With `normalized = true`, divides by the number of ordered pairs
`n * (n - 1)`, giving a value in `[0, 1]` (`0.0` when `cg_true`/`cg_guess` have
fewer than two nodes).

!!! tip "Comparing CPDAG-producing algorithms"
    When comparing several CPDAG-producing causal discovery algorithms
    against each other using a known true DAG, one should preferably first
    convert `cg_true` to its CPDAG with [`dag_to_cpdag`](@ref) and compare
    CPDAG to CPDAG, so that non-identifiability in `cg_guess` is judged
    against what is identifiable in the true equivalence class rather than
    in the true DAG itself. If `cg_guess` is an [`MPDAG`](@ref) built from
    background knowledge, apply the same
    [`apply_background_knowledge`](@ref) to the converted true CPDAG before
    comparing, so both sides reflect the same knowledge.

# Examples

```jldoctest
julia> aid(DAG("A --> B --> C"), DAG("A --> B --> C"))
0

julia> aid(DAG("A --> B --> C"), DAG("A --> B <-- C"))
4

julia> aid(DAG("A --> B --> C"), DAG("A --> B <-- C"); normalized = true)
0.6666666666666666

julia> aid(DAG("A --> B --> C, A --> C"), DAG("A --> B --> C"); type = :parent)
1

julia> aid(DAG("A --> B --> C, A --> C"), DAG("A --> B --> C"); type = :ancestor)
0
```

# References

- [henckel2024aid](@citet)
- [perkovic2018complete](@citet)
"""
function aid(
    cg_true::Union{DAG,AbstractPDAG},
    cg_guess::Union{DAG,AbstractPDAG};
    type::Symbol = :oset,
    normalized::Bool = false,
)
    type in (:parent, :ancestor, :oset) || throw(
        ArgumentError(
            "Unknown aid type $(repr(type)) (expected :parent, :ancestor, or :oset)",
        ),
    )
    node_set = _check_same_nodes(cg_true, cg_guess)
    mistakes = 0
    for t in node_set, y in node_set
        t === y && continue
        mistakes += _aid_mistake(type, cg_true, cg_guess, t, y)
    end
    normalized || return mistakes
    n = length(node_set)
    denom = n * (n - 1)
    return denom == 0 ? 0.0 : mistakes / denom
end
