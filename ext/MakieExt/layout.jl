# Convert layout output to the Point2f positions used by the drawing
# primitives.
function _positions(cg::CausalGraph, method::Symbol, kwargs)
    return _positions(cg, CausalStructures.layout(cg, method; kwargs...), nothing)
end

# Accept a pre-computed positions vector (e.g. from layout() after manual tweaks).
function _positions(cg::CausalGraph, positions::AbstractVector, ::Any)
    n = length(cg.backend.nodes)
    length(positions) == n ||
        error("positions length ($(length(positions))) must match node count ($n)")
    return [Point2f(p[1], p[2]) for p in positions]
end

# Accept positions keyed by node name, rather than in `nodes(cg)` order.
function _positions(cg::CausalGraph, positions::AbstractDict, ::Any)
    out = Vector{Point2f}(undef, length(cg.backend.nodes))
    for (i, nd) in enumerate(cg.backend.nodes)
        haskey(positions, nd) ||
            error("`layout` Dict is missing a position for node $(repr(nd)).")
        p = positions[nd]
        out[i] = Point2f(p[1], p[2])
    end
    return out
end

# Layout methods each produce coordinates on their own arbitrary scale, so
# rescale to a common bounding-box extent (diameter 2) before Makie.plot sizes
# the figure from it.
function _rescale_to_unit_extent(positions::Vector{Point2f})
    n = length(positions)
    n <= 1 && return positions
    xs = [p[1] for p in positions]
    ys = [p[2] for p in positions]
    cx = sum(xs) / n
    cy = sum(ys) / n
    extent = max(maximum(xs) - minimum(xs), maximum(ys) - minimum(ys), 1.0f-3)
    scale = 2.0f0 / extent
    return [Point2f(cx + (p[1] - cx) * scale, cy + (p[2] - cy) * scale) for p in positions]
end
