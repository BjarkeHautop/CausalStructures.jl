# Definition 4.2 needs a MAG R in the equivalence class of the PAG with the
# same number of edges into x as the PAG itself; Lemma 7.6 guarantees at
# least one exists (by resolving every circle at x to a tail), and Theorem 4.1
# holds for *any* admissible R.

"""
    backdoor_set(cg::PAG, x::Symbol, y::Symbol) -> Union{Vector{Symbol},Nothing}

Return a generalized back-door set relative to `(x, y)` and `cg` using the
Generalized Backdoor Criterion (GBC; Maathuis & Colombo 2015, Theorem 4.1), or
`nothing` if none exists.

Let `R` be any MAG in the Markov equivalence class of `cg` with the same
number of edges into `x` as `cg` (Definition 4.2; such an `R` always exists,
Lemma 7.6), and let `R_X` be `R` with every directed edge out of `x` that is
visible in `cg` removed. A generalized back-door set exists if and only if `y`
is not adjacent to `x` in `R_X` and `D-SEP(x, y, R_X)` does not intersect the
possible descendants of `x` in `cg`; when it exists, `D-SEP(x, y, R_X)` is
such a set (not necessarily minimal; Theorem 4.1 shows the result does not
depend on which admissible `R` is used).

# Examples

```jldoctest
julia> mag = cgraph("B --> X, A <-> X, A --> Y, X --> Y"; class = MAG);

julia> pag = mag_to_pag(mag);  # A o-> X, A --> Y, B o-> X, X --> Y

julia> sort(backdoor_set(pag, :X, :Y))
2-element Vector{Symbol}:
 :A
 :B
```

# References

- [maathuiscolombo2015gbc](@citet)
"""
function backdoor_set(cg::PAG, x::Symbol, y::Symbol)
    B = cg.backend
    _check_no_selection_variables(cg)
    xi = node_index(cg, x)
    # "Edges into x" (Definition 4.2): includes circle_parents, since o->
    # still has a definite arrowhead at x even though the far mark is a circle.
    k =
        length(_parents_slice(B, xi)) +
        length(_spouses_slice(B, xi)) +
        length(_circle_parents_slice(B, xi))

    visible_children = _visible_children_symbols(B, xi)
    poss_de = Set(possible_descendants(cg, x))

    for m in enumerate_mags(cg)
        any(is_undirected, m.edges) && continue  # only classical (no-selection-variable) MAGs are in R*
        mb = m.backend
        mxi = node_index(m, x)
        length(_parents_slice(mb, mxi)) + length(_spouses_slice(mb, mxi)) == k || continue

        n = length(mb.nodes)
        excluded = falses(n)
        for vs in visible_children
            excluded[node_index(m, vs)] = true
        end

        myi = node_index(m, y)
        y_adjacent_rx = (myi in _all_nbrs_slice(mb, mxi)) && !excluded[myi]
        y_adjacent_rx && return nothing

        dsep = _d_sep_mask(mb, mxi, [myi]; excluded_children = excluded)
        for v = 1:n
            (dsep[v] && mb.nodes[v] in poss_de) && return nothing
        end

        return sort([mb.nodes[v] for v = 1:n if dsep[v]])
    end

    # Unreachable: Lemma 7.6 guarantees an admissible R always exists.
    error("no admissible MAG found in the equivalence class of $(x)'s PAG")
end
