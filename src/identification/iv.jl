# Instrumental Variables (Brito & Pearl 2002)

# G_{overline{X}}: G with all incoming directed edges to X removed (do(X)).
# Bidirected edges in an ADMG are left intact.
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

# Dispatch to the right single-seed REACHABLE routine so `all_iv_sets`'s
# candidate loop stays backend-agnostic.
_reachable_single!(visited, q, reached, B::DAGBackend, seed, a_mask, z_mask) =
    _reachable_dag_single!(visited, q, reached, B, seed, a_mask, z_mask)
_reachable_single!(visited, q, reached, B::ADMGBackend, seed, a_mask, z_mask) =
    _reachable_admg_single!(visited, q, reached, B, seed, a_mask, z_mask)

"""
    is_valid_iv(cg::Union{DAG,ADMG}, x::Symbol, y, z::AbstractVector{Symbol}) -> Bool

Return `true` if `z` is a valid instrumental set for the causal effect of `x` on `y`
in `cg`.

`y` may be a single `Symbol` or an `AbstractVector{Symbol}` (multiple outcomes
of the same treatment `x`); `x` must be a single `Symbol`, since the
instrumental-set criterion is defined for one structural coefficient `x -> y`.

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

```jldoctest
julia> # Z instruments X, which affects two outcomes Y1 and Y2
       cg2 = cgraph(
           directed(:Z, :X), directed(:X, :Y1), directed(:X, :Y2),
           directed(:U, :X), directed(:U, :Y1), directed(:U, :Y2);
           class = DAG);

julia> is_valid_iv(cg2, :X, [:Y1, :Y2], [:Z])
true
```

# References

- [brito2002generalized](@cite)
- [pearl2009causality](@cite), Definition 7.4.1.
"""
function is_valid_iv(
    cg::Union{DAG,ADMG},
    x::Symbol,
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol},
)
    isempty(z) && return false
    ys_syms = _as_symbol_set(y)
    any(zi -> zi === x || zi in ys_syms, z) && return false
    return _check_iv(cg, x, y, z, _build_g_do_x(cg, x))
end

"""
    all_iv_sets(cg::Union{DAG,ADMG}, x::Symbol, y;
                minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid instrumental sets for the causal effect of `x` on `y` in `cg`,
up to size `max_size`.

`y` may be a single `Symbol` or an `AbstractVector{Symbol}`; `x` must be a
single `Symbol` (see [`is_valid_iv`](@ref)).

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

julia> cg2 = cgraph(
           directed(:Z1, :X), directed(:Z2, :X),
           directed(:X, :Y1), directed(:X, :Y2),
           directed(:U, :X), directed(:U, :Y1), directed(:U, :Y2);
           class = DAG);

julia> all_iv_sets(cg2, :X, [:Y1, :Y2])
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
    y::Union{Symbol,AbstractVector{Symbol}};
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    ys_idx = _node_indices(cg, y)
    ys_mask = falses(n)
    for yi in ys_idx
        ys_mask[yi] = true
    end

    universe = [v for v = 1:n if v != x_idx && !ys_mask[v]]
    g_do_x = _build_g_do_x(cg, x)  # built once; x/y already excluded from universe
    Bd = g_do_x.backend

    function make_checker()
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

        # a ⊥ Y | {x} in backend Bk, for the (possibly multi-node) target set `bs`
        function separated_given_x(Bk, a, bs)
            empty!(seeds_buf)
            push!(seeds_buf, a, x_idx)
            append!(seeds_buf, bs)
            _ancestors_bitmask!(anc_mask, anc_stack, Bk, seeds_buf)
            _reachable_single!(visited, q, reached, Bk, a, anc_mask, excl_zmask)
            return !any(reached[bi] for bi in bs)
        end

        return function valid_candidate(z_idxs::Vector{Int})
            relevant = false
            for zi in z_idxs
                if !separated_empty(B, zi, x_idx)
                    relevant = true
                    break
                end
            end
            relevant || return false

            for zi in z_idxs
                separated_given_x(Bd, zi, ys_idx) || return false
            end
            return true
        end
    end

    to_symbols(cur) = sort([B.nodes[v] for v in cur])

    valid_sets = _search_subsets(universe, 1, max_size, make_checker, to_symbols)

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end
