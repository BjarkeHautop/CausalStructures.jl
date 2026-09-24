# Separation distances (Wahl & Runge 2025): for each pair non-adjacent in cg2, pick
# a separator via a class-specific strategy and check it still separates the
# pair in cg1. Not symmetric in general; pass `symmetric = true` for the mean
# of both directions.

_separated(cg::Union{DAG,AbstractPDAG}, x, y, z) = d_separated(cg, x, y, z)
_separated(cg::Union{ADMG,AbstractAG,PAG}, x, y, z) = m_separated(cg, x, y, z)

function _nonadjacent_pairs(cg::CausalGraph)
    ns = nodes(cg)
    n = length(ns)
    prs = Tuple{Symbol,Symbol}[]
    for i = 1:n, j = (i+1):n
        has_edge(cg, ns[i], ns[j]) || push!(prs, (ns[i], ns[j]))
    end
    return prs
end

# Parent separation: pa(x) ∪ pa(y). Valid for DAGs only, not MAGs (Fig. 6).
_parent_separator(cg::DAG, x::Symbol, y::Symbol) = union(parents(cg, x), parents(cg, y))

# Ancestor separation: an(x) ∪ an(y), excluding x and y. Same DAG-only caveat.
function _ancestor_separator(cg::DAG, x::Symbol, y::Symbol)
    return setdiff(
        union(ancestors(cg, x; open = true), ancestors(cg, y; open = true)),
        (x, y),
    )
end

function _dag_strategy_separator(cg::DAG, strategy::Symbol, x::Symbol, y::Symbol)
    strategy === :parents && return _parent_separator(cg, x, y)
    strategy === :ancestors && return _ancestor_separator(cg, x, y)
    strategy === :zl && return _zl_separator(cg, x, y)
    throw(
        ArgumentError(
            "Unknown separation_distance strategy $(repr(strategy)) for DAG (expected :parents, :ancestors, or :zl)",
        ),
    )
end

# ZL-separation (van der Zander & Liśkiewicz 2020): the only known universal
# strategy for MAGs/PAGs (also valid on DAGs). `nothing` (no separator exists)
# becomes an empty separator, which never separates anything.
_zl_separator(cg::Union{DAG,AbstractAG,PAG}, x::Symbol, y::Symbol) =
    something(minimal_separator(cg, x, y), Symbol[])

# p-Parent separation: ppa(x) ∪ ppa(y), the union of pa(v) across every DAG in
# the equivalence class; MEC-invariant, unlike plain parents.
_possible_parents(cg::AbstractPDAG, x::Symbol) =
    reduce(union, possible_parent_sets(cg, x); init = Symbol[])

_possible_parent_separator(cg::AbstractPDAG, x::Symbol, y::Symbol) =
    union(_possible_parents(cg, x), _possible_parents(cg, y))

# MB-enhancement: use x's Markov blanket as the separator for every y not in
# it, falling back to the base strategy for the exceptions where y ∈ MB(x).
function _mb_enhanced(base_separator, cg::CausalGraph, x::Symbol, y::Symbol)
    mb = markov_blanket(cg, x)
    return y in mb ? base_separator(cg, x, y) : mb
end

function _separation_distance(
    cg1::CausalGraph,
    cg2::CausalGraph,
    separator;
    normalized::Bool,
    symmetric::Bool,
)
    if symmetric
        a = _separation_distance(cg1, cg2, separator; normalized, symmetric = false)
        b = _separation_distance(cg2, cg1, separator; normalized, symmetric = false)
        return (a + b) / 2
    end

    node_set = _check_same_nodes(cg1, cg2)
    d = 0
    for (x, y) in _nonadjacent_pairs(cg2)
        s = separator(cg2, x, y)
        _separated(cg1, x, y, s) || (d += 1)
    end
    normalized || return d
    mp = _max_pairs(length(node_set))
    return mp == 0 ? 0.0 : d / mp
end

"""
    separation_distance(cg1::DAG, cg2::DAG; strategy::Symbol = :parents,
                         mb_enhanced::Bool = false, symmetric::Bool = false,
                         normalized::Bool = false) -> Real
    separation_distance(cg1::AbstractAG, cg2::AbstractAG; mb_enhanced::Bool = false,
                         symmetric::Bool = false, normalized::Bool = false) -> Real
    separation_distance(cg1::AbstractPDAG, cg2::AbstractPDAG; mb_enhanced::Bool = false,
                         symmetric::Bool = false, normalized::Bool = false) -> Real
    separation_distance(cg1::PAG, cg2::PAG; mb_enhanced::Bool = false,
                         symmetric::Bool = false, normalized::Bool = false) -> Real

Separation distance (SD) from `cg1` to `cg2` [wahlrunge2025separation](@cite). For
every pair of nodes non-adjacent in `cg2`, picks a separator in `cg2` (per
`strategy`, where applicable) and checks whether it still separates the pair
in `cg1`, returning the number of pairs where it does not.

**Not symmetric in general** (separators are read off `cg2`, then verified in
`cg1`); pass `symmetric = true` for the mean of both directions (zero iff `cg1`
and `cg2` are Markov equivalent, for `mb_enhanced = false`).

The separator is class-specific:

- For a [`DAG`](@ref), `strategy` is `:parents` (default,
  `parents(cg2, x) ∪ parents(cg2, y)`), `:ancestors`
  (`ancestors(cg2, x) ∪ ancestors(cg2, y)`), or `:zl` ([`minimal_separator`](@ref)).
- For an [`AbstractAG`](@ref) (`AG`/`MAG`) or [`PAG`](@ref), ZL-separation is
  the only strategy proven valid, so there is no `strategy` keyword there; it
  also works on `DAG`s, just usually more expensive than
  `:parents`/`:ancestors`.
- For an [`AbstractPDAG`](@ref) (`PDAG`/`CPDAG`/`MPDAG`), **p-parent
  separation** is used: `ppa(cg2, x) ∪ ppa(cg2, y)`, where `ppa(v)` is the union
  of `v`'s parents across every DAG consistent with `cg2`'s edges (via
  [`possible_parent_sets`](@ref)). Unlike plain [`parents`](@ref), this is
  invariant under Markov equivalence, matching what an `AbstractPDAG` fixes.

`mb_enhanced = true` uses `x`'s [`markov_blanket`](@ref) as the separator for
every `y` not already in it (falling back to the base strategy otherwise);
often cheaper on sparse graphs.

`normalized = true` divides by `n * (n - 1) / 2`, giving a value in `[0, 1]`.

# Examples

```jldoctest
julia> separation_distance(DAG("A --> B --> C"), DAG("A --> B --> C"))
0

julia> separation_distance(DAG("A --> C <-- B"), DAG("A --> B --> C"))
1

julia> separation_distance(DAG("A --> C <-- B"), DAG("A --> B --> C"); symmetric = true)
1.0

julia> cg1 = DAG("A --> B --> C, A --> C, C --> D"); cg2 = DAG("A --> B --> C --> D");

julia> separation_distance(cg1, cg2)
1

julia> separation_distance(cg1, cg2; strategy = :zl)
2

julia> separation_distance(cg1, cg2; mb_enhanced = true)
2

julia> separation_distance(cg1, cg2; normalized = true)
0.16666666666666666

julia> separation_distance(MAG("A <-> B, C --> B --> D"), MAG("A <-> B, C --> B --> D"))
0

julia> cpdag1 = dag_to_cpdag(DAG("A --> B --> C, A --> C"));

julia> cpdag2 = dag_to_cpdag(DAG("A --> B --> C"));

julia> separation_distance(cpdag1, cpdag2)
1

julia> pag1 = mag_to_pag(MAG("A --> X --> M --> Y, A --> Y"));

julia> pag2 = mag_to_pag(MAG("A --> X --> M --> Y"));

julia> separation_distance(pag1, pag2)
2
```

# References

- [wahlrunge2025separation](@citet)
- [vanderzander2020finding](@citet)
- [maathuis2009estimating](@citet)
"""
function separation_distance(
    cg1::DAG,
    cg2::DAG;
    strategy::Symbol = :parents,
    mb_enhanced::Bool = false,
    symmetric::Bool = false,
    normalized::Bool = false,
)
    base(cg, x, y) = _dag_strategy_separator(cg, strategy, x, y)
    sep = mb_enhanced ? (cg, x, y) -> _mb_enhanced(base, cg, x, y) : base
    return _separation_distance(cg1, cg2, sep; normalized, symmetric)
end

function separation_distance(
    cg1::AbstractAG,
    cg2::AbstractAG;
    mb_enhanced::Bool = false,
    symmetric::Bool = false,
    normalized::Bool = false,
)
    sep = mb_enhanced ? (cg, x, y) -> _mb_enhanced(_zl_separator, cg, x, y) : _zl_separator
    return _separation_distance(cg1, cg2, sep; normalized, symmetric)
end

function separation_distance(
    cg1::AbstractPDAG,
    cg2::AbstractPDAG;
    mb_enhanced::Bool = false,
    symmetric::Bool = false,
    normalized::Bool = false,
)
    sep =
        mb_enhanced ? (cg, x, y) -> _mb_enhanced(_possible_parent_separator, cg, x, y) :
        _possible_parent_separator
    return _separation_distance(cg1, cg2, sep; normalized, symmetric)
end

function separation_distance(
    cg1::PAG,
    cg2::PAG;
    mb_enhanced::Bool = false,
    symmetric::Bool = false,
    normalized::Bool = false,
)
    sep = mb_enhanced ? (cg, x, y) -> _mb_enhanced(_zl_separator, cg, x, y) : _zl_separator
    return _separation_distance(cg1, cg2, sep; normalized, symmetric)
end
