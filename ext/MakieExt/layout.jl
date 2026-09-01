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
#
# Split into params + apply (rather than one function) so that `Makie.plot`
# can compute the transform once from node positions and then apply the
# identical affine map to `edge_paths` waypoints too, keeping them aligned
# with the (rescaled/stretched) node positions they were computed alongside.
function _unit_extent_params(positions::AbstractVector{Point2f})
    n = length(positions)
    n <= 1 && return (0.0f0, 0.0f0, 1.0f0)
    xs = [p[1] for p in positions]
    ys = [p[2] for p in positions]
    cx = sum(xs) / n
    cy = sum(ys) / n
    extent = max(maximum(xs) - minimum(xs), maximum(ys) - minimum(ys), 1.0f-3)
    return (cx, cy, 2.0f0 / extent)
end

_apply_unit_extent(p::Point2f, cx, cy, scale) =
    Point2f(cx + (p[1] - cx) * scale, cy + (p[2] - cy) * scale)

function _rescale_to_unit_extent(positions::Vector{Point2f})
    length(positions) <= 1 && return positions
    cx, cy, scale = _unit_extent_params(positions)
    return [_apply_unit_extent(p, cx, cy, scale) for p in positions]
end

function _aspect_stretch_params(positions::AbstractVector{Point2f}, target_aspect::Real)
    n = length(positions)
    n <= 1 && return (0.0f0, 0.0f0, 1.0f0, 1.0f0)
    xs = [p[1] for p in positions]
    ys = [p[2] for p in positions]
    cx = sum(xs) / n
    cy = sum(ys) / n
    bbox_w = max(maximum(xs) - minimum(xs), 1.0f-3)
    bbox_h = max(maximum(ys) - minimum(ys), 1.0f-3)
    current_aspect = bbox_w / bbox_h
    sx, sy = if current_aspect < target_aspect
        Float32(target_aspect / current_aspect), 1.0f0
    else
        1.0f0, Float32(current_aspect / target_aspect)
    end
    return (cx, cy, sx, sy)
end

_apply_aspect_stretch(p::Point2f, cx, cy, sx, sy) =
    Point2f(cx + (p[1] - cx) * sx, cy + (p[2] - cy) * sy)

function _stretch_to_aspect(positions::Vector{Point2f}, target_aspect::Real)
    length(positions) <= 1 && return positions
    cx, cy, sx, sy = _aspect_stretch_params(positions, target_aspect)
    return [_apply_aspect_stretch(p, cx, cy, sx, sy) for p in positions]
end
