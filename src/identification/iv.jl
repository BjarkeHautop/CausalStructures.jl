# Instrumental Variables (Brito & Pearl 2002)

# G_{overline{X}}: G with all incoming directed edges to X removed (do(X) intervention).
# Works for both DAG and ADMG: bidirected edges in an ADMG are not incoming directed
# edges and are left intact.
function _build_g_do_x(cg::DAG, x::Symbol)
    return build_graph(
        DAG,
        Set(cg.backend.nodes),
        filter(e -> !(is_directed(e) && e.dst == x), cg.edges),
    )
end

function _build_g_do_x(cg::ADMG, x::Symbol)
    return build_graph(
        ADMG,
        Set(cg.backend.nodes),
        filter(e -> !(is_directed(e) && e.dst == x), cg.edges),
    )
end

# Checks (ii) before (i) to skip the more expensive graph-build when relevance fails.
function _check_iv(cg, x, y, z, g_do_x)
    all(zi -> m_separated(cg, zi, x), z) && return false   # (ii) relevance: z must reach x
    for zi in z
        m_separated(g_do_x, zi, y, [x]) || return false    # (i)  exclusion: z ⊥ y | x in G_{do_x}
    end
    return true
end

# Dispatch to the right single-seed REACHABLE routine so the buffer-reusing
# candidate loop in `all_iv_sets` below can stay backend-agnostic (it runs
# for both DAG and ADMG).
_reachable_single!(visited, q, reached, B::DAGBackend, seed, a_mask, z_mask) =
    _reachable_dag_single!(visited, q, reached, B, seed, a_mask, z_mask)
_reachable_single!(visited, q, reached, B::ADMGBackend, seed, a_mask, z_mask) =
    _reachable_admg_single!(visited, q, reached, B, seed, a_mask, z_mask)

"""
    is_valid_iv(cg::Union{DAG,ADMG}, x::Symbol, y::Symbol, z::AbstractVector{Symbol}) -> Bool

Return `true` if `z` is a valid instrumental set for the causal effect of `x` on `y`
in `cg`.

`z` is a valid instrumental set if:
1. Every `zi ∈ z` is d-/m-separated from `y` given `{x}` in the interventional graph
   `G_{overline{x}}` (obtained by deleting all incoming directed edges to `x`). This
   is the **exclusion restriction**: `z` can only affect `y` through `x`.
2. At least one `zi ∈ z` is d-/m-connected to `x` in `G`. This is the **relevance
   condition**: `z` must be associated with the treatment.

# Examples

```jldoctest
julia> # Classic IV graph: Z --> X --> Y with hidden confounder U --> X, U --> Y
       cg = cgraph(
           directed(:Z, :X), directed(:X, :Y),
           directed(:U, :X), directed(:U, :Y);
           class = DAG);

julia> is_valid_iv(cg, :X, :Y, [:Z])  # Z is a valid instrument
true

julia> is_valid_iv(cg, :X, :Y, [:U])  # U confounds X and Y; fails exclusion restriction
false
```

```jldoctest
julia> # ADMG: X <-> Y encodes the hidden confounder directly
       admg = cgraph(
           bidirected(:X, :Y),
           directed(:Z, :X), directed(:X, :Y);
           class = ADMG);

julia> is_valid_iv(admg, :X, :Y, [:Z])
true
```

# References

- [brito2002generalized](@cite)
- [pearl2009causality](@cite), Definition 7.4.1.
"""
function is_valid_iv(cg::Union{DAG,ADMG}, x::Symbol, y::Symbol, z::AbstractVector{Symbol})
    isempty(z) && return false
    any(zi -> zi === x || zi === y, z) && return false
    return _check_iv(cg, x, y, z, _build_g_do_x(cg, x))
end

"""
    all_iv_sets(cg::Union{DAG,ADMG}, x::Symbol, y::Symbol;
                minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid instrumental sets for the causal effect of `x` on `y` in `cg`,
up to size `max_size`.

Bruteforces over subsets of the allowed universe of nodes (nodes that are not `x` or `y`),
checking each for validity using [`is_valid_iv`](@ref). When `minimal = true` (default),
only inclusion-minimal sets are returned.

# Examples

```jldoctest
julia> cg = cgraph(
           directed(:Z1, :X), directed(:Z2, :X),
           directed(:X, :Y),
           directed(:U, :X), directed(:U, :Y);
           class = DAG);

julia> all_iv_sets(cg, :X, :Y)
2-element Vector{Vector{Symbol}}:
 [:Z1]
 [:Z2]
```

# References

- [brito2002generalized](@cite)
"""
function all_iv_sets(
    cg::Union{DAG,ADMG},
    x::Symbol,
    y::Symbol;
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)

    universe = [v for v = 1:n if v != x_idx && v != y_idx]
    g_do_x = _build_g_do_x(cg, x)  # built once; x/y already excluded from universe
    Bd = g_do_x.backend

    valid_sets = Vector{Vector{Symbol}}()
    cur = Int[]

    # Scratch buffers reused across every candidate and every element of z
    # instead of allocated fresh inside `m_separated` on every call: `_check_iv`
    # calls it up to 2*|z| times per candidate (once per element for relevance,
    # once per element for exclusion), so its allocations otherwise dominate.
    empty_zmask = falses(n)
    excl_zmask = falses(n)
    excl_zmask[x_idx] = true

    anc_mask = falses(n)
    anc_stack = Int[]
    visited = falses(n, 2)
    q = Tuple{Int,Int}[]
    reached = falses(n)
    seeds_buf = Int[]

    # a ⊥ b | ∅ in backend Bk
    function separated_empty(Bk, a, b)
        empty!(seeds_buf)
        push!(seeds_buf, a, b)
        _ancestors_bitmask!(anc_mask, anc_stack, Bk, seeds_buf)
        _reachable_single!(visited, q, reached, Bk, a, anc_mask, empty_zmask)
        return !reached[b]
    end

    # a ⊥ b | {x} in backend Bk
    function separated_given_x(Bk, a, b)
        empty!(seeds_buf)
        push!(seeds_buf, a, b, x_idx)
        _ancestors_bitmask!(anc_mask, anc_stack, Bk, seeds_buf)
        _reachable_single!(visited, q, reached, Bk, a, anc_mask, excl_zmask)
        return !reached[b]
    end

    function valid_candidate(z_idxs::Vector{Int})
        relevant = false
        for zi in z_idxs
            if !separated_empty(B, zi, x_idx)
                relevant = true
                break
            end
        end
        relevant || return false

        for zi in z_idxs
            separated_given_x(Bd, zi, y_idx) || return false
        end
        return true
    end

    function enumerate!(start, k_rem)
        if k_rem == 0
            if valid_candidate(cur)
                push!(valid_sets, sort([B.nodes[v] for v in cur]))
            end
            return
        end
        for i = start:length(universe)
            push!(cur, universe[i])
            enumerate!(i + 1, k_rem - 1)
            pop!(cur)
        end
    end

    for k = 1:min(max_size, length(universe))
        enumerate!(1, k)
    end

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end
