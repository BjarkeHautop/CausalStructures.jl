# Convert layout output (Vector of NTuple) to the Point2f positions
# used by Makie drawing primitives.
function _positions(cg::CausalGraph, method::Symbol, kwargs)
    tuples = CausalStructures.layout(cg, method; kwargs...)
    return [Point2f(x, y) for (x, y) in tuples]
end

# Accept a pre-computed positions vector (e.g. from layout() after manual tweaks).
function _positions(cg::CausalGraph, positions::AbstractVector, ::Any)
    n = length(cg.backend.nodes)
    length(positions) == n ||
        error("positions length ($(length(positions))) must match node count ($n)")
    return [Point2f(p[1], p[2]) for p in positions]
end

# Layout methods (:spring, :stress, ...) each produce coordinates on their own
# arbitrary scale, so rescale to a common bounding-box extent (diameter 2)
# before figure sizing is computed from it in Makie.plot - otherwise the same
# graph renders at a different figure size depending only on which layout
# algorithm was used.
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
