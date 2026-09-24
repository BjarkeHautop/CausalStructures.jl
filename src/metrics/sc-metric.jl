# s/c-metric and its one-sided relatives (Wahl & Runge 2025, Sec. 4 & Appendix D.1):
# unlike hd/shd (edges only) or separation_distance (one separator per pair),
# these compare every separation/connection statement (X, Y, S) up to a given
# conditioning-set order. Exponential in the number of nodes.

_separation_family(::Union{DAG,AbstractPDAG}) = :d
_separation_family(::Union{ADMG,AbstractAG,PAG}) = :m

function _check_same_separation_family(cg1::CausalGraph, cg2::CausalGraph)
    _separation_family(cg1) == _separation_family(cg2) || throw(
        ArgumentError(
            "cg1 and cg2 must use the same separation notion: both from " *
            "{DAG, AbstractPDAG} (d-separation) or both from " *
            "{ADMG, AbstractAG, PAG} (m-separation); got $(typeof(cg1)) and $(typeof(cg2))",
        ),
    )
end

function _validate_max_order(n::Int, max_order::Union{Nothing,Int})
    full_order = max(n - 2, 0)
    K = max_order === nothing ? full_order : max_order
    (0 <= K <= full_order) || throw(
        ArgumentError(
            "max_order must be between 0 and $(full_order) (n - 2) for $(n) nodes, got $(K)",
        ),
    )
    return K
end

# Checks node sets and separation family agree; returns the sorted node list
# and the highest conditioning-set order to average over.
function _sc_metric_setup(cg1::CausalGraph, cg2::CausalGraph, max_order::Union{Nothing,Int})
    node_set = _check_same_nodes(cg1, cg2)
    _check_same_separation_family(cg1, cg2)
    ns = sort(collect(node_set))
    K = _validate_max_order(length(ns), max_order)
    return ns, K
end

# Calls `f(x, y, s)` for every ordered pair of distinct nodes `(x, y)` and every
# k-subset `s` of the remaining nodes. Uses `Ref`s below to avoid boxing
# captured variables in the closures.
function _for_each_statement(f, ns::Vector{Symbol}, k::Int)
    n = length(ns)
    for i = 1:n, j = 1:n
        i == j && continue
        x, y = ns[i], ns[j]
        rest = [ns[m] for m = 1:n if m != i && m != j]
        for s_idx in _all_subsets(collect(1:length(rest)), k, k)
            f(x, y, rest[s_idx])
        end
    end
end

function _sc_metric_order(cg1::CausalGraph, cg2::CausalGraph, ns::Vector{Symbol}, k::Int)
    total = Ref(0)
    count = Ref(0)
    _for_each_statement(ns, k) do x, y, s
        total[] += _separated(cg1, x, y, s) != _separated(cg2, x, y, s)
        count[] += 1
    end
    return count[] == 0 ? 0.0 : total[] / count[]
end

"""
    sc_metric(cg1::CausalGraph, cg2::CausalGraph; max_order::Union{Nothing,Int} = nothing) -> Float64

The s/c-metric [wahlrunge2025separation](@cite): the (normalized) fraction of
separation/connection statements `(X, Y, S)` on which `cg1` and `cg2` disagree,
graded by the order (size) of `S`. For each order `k = 0, ..., K`, averages
disagreement over every ordered pair of distinct nodes `(X, Y)` and every
`k`-subset `S` of the remaining nodes; the result is the mean over `k` of
those per-order averages.

`cg1` and `cg2` must have the same node set, and must use the same separation
notion: both from `{DAG, AbstractPDAG}` (d-separation) or both from `{ADMG,
AbstractAG, PAG}` (m-separation). See [`markov_metric`](@ref)/
[`faithfulness_metric`](@ref) for one-sided variants against a fixed
ground-truth graph.

By default (`max_order = nothing`), computes the full s/c-metric (`K = n - 2`),
which is a proper metric (`sc_metric(cg1, cg2) == 0` iff `cg1` and `cg2` are Markov
equivalent) but exponential in the number of nodes. Pass `max_order` to bound
the conditioning-set size, e.g. `max_order = 0` for pairwise marginal
(in)dependence alone.

# Examples

```jldoctest
julia> g = DAG("A --> B --> C --> D");

julia> sc_metric(g, g)
0.0

julia> cg1 = DAG("A --> B --> C --> D"); cg2 = DAG("A --> B <-- C --> D");

julia> sc_metric(cg1, cg2)
0.24999999999999997

julia> sc_metric(cg1, cg2; max_order = 0)
0.3333333333333333

julia> sc_metric(cg1, cg2; max_order = 1)
0.29166666666666663
```

# References

- [wahlrunge2025separation](@citet)
"""
function sc_metric(
    cg1::CausalGraph,
    cg2::CausalGraph;
    max_order::Union{Nothing,Int} = nothing,
)
    ns, K = _sc_metric_setup(cg1, cg2, max_order)
    return sum(k -> _sc_metric_order(cg1, cg2, ns, k), 0:K) / (K + 1)
end

function _one_sided_metric_order(
    cg_truth::CausalGraph,
    cg_test::CausalGraph,
    ns::Vector{Symbol},
    k::Int,
    truth_separated::Bool,
)
    total = Ref(0)
    count = Ref(0)
    _for_each_statement(ns, k) do x, y, s
        _separated(cg_truth, x, y, s) == truth_separated || return
        count[] += 1
        total[] += _separated(cg_test, x, y, s) != truth_separated
    end
    return count[] == 0 ? 0.0 : total[] / count[]
end

"""
    markov_metric(cg_truth::CausalGraph, cg_test::CausalGraph;
                  max_order::Union{Nothing,Int} = nothing) -> Float64

The Markov metric (c-metric) of `cg_test` relative to `cg_truth`
[wahlrunge2025separation](@cite). The proportion of order-graded connection
statements `(X, Y, S)` that are connected in `cg_truth` but separated in
`cg_test`, the false-negative rate for connections, i.e. how far `cg_test` is
from satisfying the causal Markov condition relative to `cg_truth`.

Unlike [`sc_metric`](@ref), which compares graphs symmetrically, this treats
`cg_truth` as a fixed reference (e.g. ground truth in a simulation). Same
node-set/separation-notion requirements and `max_order` handling as
[`sc_metric`](@ref).

`0.0` means `cg_test` is at least as connected as `cg_truth` for every statement
considered (in particular whenever the graphs are Markov equivalent). An order
`k` with no connection statements in `cg_truth` contributes `0.0` rather than
being skipped, so every one of the `K + 1` orders counts toward the mean. See
[`faithfulness_metric`](@ref) for the complementary false-positive rate.

# Examples

```jldoctest
julia> g = DAG("A --> B --> C --> D");

julia> markov_metric(g, g)
0.0

julia> cg_truth = DAG("A --> B --> C --> D"); cg_test = DAG("A --> B <-- C --> D");

julia> markov_metric(cg_truth, cg_test)
0.15277777777777776

julia> markov_metric(cg_truth, cg_test; max_order = 0)
0.3333333333333333
```

# References

- [wahlrunge2025separation](@citet)
"""
function markov_metric(
    cg_truth::CausalGraph,
    cg_test::CausalGraph;
    max_order::Union{Nothing,Int} = nothing,
)
    ns, K = _sc_metric_setup(cg_truth, cg_test, max_order)
    return sum(k -> _one_sided_metric_order(cg_truth, cg_test, ns, k, false), 0:K) / (K + 1)
end

"""
    faithfulness_metric(cg_truth::CausalGraph, cg_test::CausalGraph;
                        max_order::Union{Nothing,Int} = nothing) -> Float64

The faithfulness metric (s-metric) of `cg_test` relative to `cg_truth`
[wahlrunge2025separation](@cite). The proportion of order-graded separation
statements `(X, Y, S)` that are separated in `cg_truth` but connected in
`cg_test`, the false-positive rate for separations, i.e. how many spurious
connections `cg_test` introduces relative to `cg_truth`.

Unlike [`sc_metric`](@ref), which compares graphs symmetrically, this treats
`cg_truth` as a fixed reference (e.g. ground truth in a simulation). Same
node-set/separation-notion requirements and `max_order` handling as
[`sc_metric`](@ref).

`0.0` means `cg_test` is at least as separated as `cg_truth` for every statement
considered (in particular whenever the graphs are Markov equivalent). An order
`k` with no separation statements in `cg_truth` contributes `0.0` rather than
being skipped, so every one of the `K + 1` orders counts toward the mean. See
[`markov_metric`](@ref) for the complementary false-negative rate.

# Examples

```jldoctest
julia> g = DAG("A --> B --> C --> D");

julia> faithfulness_metric(g, g)
0.0

julia> cg_truth = DAG("A --> B --> C --> D"); cg_test = DAG("A --> B <-- C --> D");

julia> faithfulness_metric(cg_truth, cg_test)
0.27777777777777773

julia> faithfulness_metric(cg_truth, cg_test; max_order = 0)
0.0
```

# References

- [wahlrunge2025separation](@citet)
"""
function faithfulness_metric(
    cg_truth::CausalGraph,
    cg_test::CausalGraph;
    max_order::Union{Nothing,Int} = nothing,
)
    ns, K = _sc_metric_setup(cg_truth, cg_test, max_order)
    return sum(k -> _one_sided_metric_order(cg_truth, cg_test, ns, k, true), 0:K) / (K + 1)
end
