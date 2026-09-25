# Maps each adjacent pair, in sorted order, to its endpoint marks, oriented so
# the first mark belongs to the lexicographically smaller node.
function _pair_marks(cg::CausalGraph)
    marks = Dict{Tuple{Symbol,Symbol},Tuple{Endpoint,Endpoint}}()
    for e in cg.edges
        a, b = _ordered_pair(e.src, e.dst)
        marks[(a, b)] = e.src == a ? (e.src_end, e.dst_end) : (e.dst_end, e.src_end)
    end
    return marks
end

"""
    hd(cg1::CausalGraph, cg2::CausalGraph; normalized::Bool = false) -> Real

Skeleton Hamming distance between `cg1` and `cg2`. Counts the number of node pairs
on which the two graphs disagree about whether an edge is present, ignoring edge
type and orientation entirely. `cg1` and `cg2` must have the same node set;
they may be of different graph classes.

With `normalized = true`, divides by the number of node pairs
`n * (n - 1) / 2`, giving a value in `[0, 1]` (`0.0` when `cg1`/`cg2` have
fewer than two nodes).

# Examples

```jldoctest
julia> hd(DAG("A --> B --> C"), DAG("A --> B <-- C"))
0

julia> hd(DAG("A --> B, C"), DAG("A --> B --> C"))
1

julia> hd(DAG("A --> B"), ADMG("A <-> B"))
0

julia> hd(DAG("A --> B, C"), DAG("A --> B --> C"); normalized = true)
0.3333333333333333
```
"""
function hd(cg1::CausalGraph, cg2::CausalGraph; normalized::Bool = false)
    node_set = _check_same_nodes(cg1, cg2)
    m1, m2 = _pair_marks(cg1), _pair_marks(cg2)
    pairs = union(Set(keys(m1)), Set(keys(m2)))
    d = count(p -> haskey(m1, p) != haskey(m2, p), pairs)
    normalized || return d
    mp = _max_pairs(length(node_set))
    return mp == 0 ? 0.0 : d / mp
end

"""
    shd(cg1::CausalGraph, cg2::CausalGraph; normalized::Bool = false) -> Real

Structural Hamming Distance (SHD) [tsamardinos2006max](@cite) between `cg1`
and `cg2`. Counts the node pairs on which the two graphs disagree, weighting
skeleton and orientation mismatches equally. `cg1` and `cg2` must
have the same node set; they may be of different graph classes.

With `normalized = true`, divides by the number of node pairs
`n * (n - 1) / 2`, giving a value in `[0, 1]` (`0.0` when `cg1`/`cg2` have
fewer than two nodes).

The original paper only defined SHD for PDAGs, but we do the natural extension
of the metric to any pair of causal graphs.

# Examples

```jldoctest
julia> shd(DAG("A --> B --> C"), DAG("A --> B <-- C"))
1

julia> shd(DAG("A --> B"), DAG("B --> A"))
1

julia> shd(DAG("A --> B"), ADMG("A <-> B"))
1

julia> shd(DAG("A --> B --> C"), DAG("A --> B --> C"))
0
```

# References

- [tsamardinos2006max](@citet)
"""
function shd(cg1::CausalGraph, cg2::CausalGraph; normalized::Bool = false)
    node_set = _check_same_nodes(cg1, cg2)
    m1, m2 = _pair_marks(cg1), _pair_marks(cg2)
    pairs = union(Set(keys(m1)), Set(keys(m2)))
    d = count(p -> get(m1, p, nothing) != get(m2, p, nothing), pairs)
    normalized || return d
    mp = _max_pairs(length(node_set))
    return mp == 0 ? 0.0 : d / mp
end
