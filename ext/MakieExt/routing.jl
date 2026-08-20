# Automatic edge routing: bends an edge around any non-incident node it would
# otherwise cross.
# Coordinates are axis data space; Makie draws with `aspect = DataAspect()`,
# so Euclidean distance there is already isotropic and needs no conversion.

_unit(p::Point2f) =
    (n = _norm2(p); n < 1.0f-6 ? Point2f(0, 0) : Point2f(p[1] / n, p[2] / n))

# Distance from point `p` to segment `a`--`b`, plus the clamped projection
# parameter t in [0, 1] locating the closest point on the segment.
function _point_segment_dist(p::Point2f, a::Point2f, b::Point2f)
    d = b - a
    l2 = d[1]^2 + d[2]^2
    if l2 <= 0
        return _norm2(p - a), 0.0f0
    end
    t = ((p[1] - a[1]) * d[1] + (p[2] - a[2]) * d[2]) / l2
    t = clamp(t, 0.0f0, 1.0f0)
    c = a + t * d
    return _norm2(p - c), t
end

# Locate the curve parameter where a monotone function f crosses target, via
# bisection on [0, 1]. When increasing = true, f grows from u = 0 and the
# smallest u with f(u) >= target is returned; when false, f grows toward
# u = 0 (i.e. decreases as u increases) and the largest such u is returned.
function _bisect_u(f, target::Float32, increasing::Bool)
    lo, hi = 0.0f0, 1.0f0
    for _ = 1:40
        mid = (lo + hi) / 2.0f0
        inside = f(mid) < target
        if increasing
            inside ? (lo = mid) : (hi = mid)
        else
            inside ? (hi = mid) : (lo = mid)
        end
    end
    return increasing ? hi : lo
end

function _cubic_bezier(p0::Point2f, p1::Point2f, p2::Point2f, p3::Point2f, t::Float32)
    u = 1.0f0 - t
    return u^3 * p0 + 3.0f0 * u^2 * t * p1 + 3.0f0 * u * t^2 * p2 + t^3 * p3
end

# Clip a cubic Bezier (control points p0,p1,p2c,p2) to the node boundaries at
# each end and sample it into `n` points, or return `nothing` if the curve
# doesn't clear both boundaries (e.g. a node large enough to swallow it).
# Shared by `_route_edge_path` and `_bowed_edge_path`.
function _clip_and_sample_bezier(
    p0::Point2f,
    p1::Point2f,
    p2c::Point2f,
    p2::Point2f,
    g_from::_NodeGeom,
    g_to::_NodeGeom,
    n::Int,
)
    q(t) = _cubic_bezier(p0, p1, p2c, p2, t)
    f_from(t) = _radial_fraction(g_from, q(t))
    f_to(t) = _radial_fraction(g_to, q(t))

    # If a node is large enough to swallow the whole curve, give up and let
    # the caller fall back to the straight (clipped) edge.
    (f_from(1.0f0) <= 1.0f0 || f_to(0.0f0) <= 1.0f0) && return nothing

    # The fraction grows monotonically away from each center along the curve,
    # so bisection locates the border crossing, whatever the node's shape.
    u_start = _bisect_u(f_from, 1.0f0, true)
    u_end = _bisect_u(f_to, 1.0f0, false)
    u_start >= u_end && return nothing

    return [q(Float32(u_start + (u_end - u_start) * i / (n - 1))) for i = 0:(n-1)]
end

# Routed edge path avoiding obstructing nodes, or `nothing` when no obstacle
# comes within `orad + clearance` of the straight center-to-center segment. The
# cubic Bezier is built between the node *centers* so that, once clipped to the
# borders, it appears to project radially from each.
function _route_edge_path(
    p0::Point2f,
    p2::Point2f,
    g_from::_NodeGeom,
    g_to::_NodeGeom,
    obstacles::AbstractVector{Tuple{Point2f,Float32}},
    clearance::Float32;
    n::Int = 40,
)
    isempty(obstacles) && return nothing

    diff = p2 - p0
    seg_len = _norm2(diff)
    seg_len < 1.0f-6 && return nothing

    # Worst violator: the obstacle whose required clearance is most exceeded
    # by its proximity to the center-to-center segment.
    worst_violation = 0.0f0
    worst_side = 1.0f0
    found = false

    for (o, orad) in obstacles
        dist, _ = _point_segment_dist(o, p0, p2)
        violation = (orad + clearance) - dist
        if violation > worst_violation
            worst_violation = violation
            # Signed side of the obstacle relative to the directed chord
            # p0->p2 (cross product z-component): +1 left, -1 right.
            side = sign(diff[1] * (o[2] - p0[2]) - diff[2] * (o[1] - p0[1]))
            worst_side = side == 0.0f0 ? 1.0f0 : Float32(side)
            found = true
        end
    end

    found || return nothing

    # Unit perpendicular to the chord, pointing away from the obstacle.
    bend = -worst_side
    nperp = Point2f(bend * -diff[2] / seg_len, bend * diff[1] / seg_len)

    # Placing the control handles only partway along the chord (handle_frac)
    # makes the curve leave each node at a steeper angle, so it reads as
    # projecting from the center.
    handle_frac = 0.2f0
    curve_at(h, t) = _cubic_bezier(
        p0,
        p0 + handle_frac * diff + h * nperp,
        p0 + (1.0f0 - handle_frac) * diff + h * nperp,
        p2,
        t,
    )
    # Closest approach of the curve (bowed by h) to obstacle o, over a coarse
    # sampling - accurate enough to size h and cheap to evaluate.
    min_dist(h, o) = minimum(_norm2(curve_at(h, Float32(k) / 24.0f0) - o) for k = 0:24)
    worst_at(h) = maximum((orad + clearance) - min_dist(h, o) for (o, orad) in obstacles)

    h_max = 2.0f0 * seg_len
    best_h, best_violation = 0.0f0, worst_at(0.0f0)
    for k = 1:60
        h = k / 60.0f0 * h_max
        v = worst_at(h)
        if v < best_violation
            best_h, best_violation = h, v
        end
        v <= 0.0f0 && break
    end
    # Bow at least a little
    h = max(best_h, 0.06f0 * seg_len)

    p1 = p0 + handle_frac * diff + h * nperp
    p2c = p0 + (1.0f0 - handle_frac) * diff + h * nperp
    return _clip_and_sample_bezier(p0, p1, p2c, p2, g_from, g_to, n)
end

# Bows the chord perpendicular by the signed offset `h`, positive being to the
# left of `p0 --> p2`. Same control-point construction as `_route_edge_path`,
# with `h` given directly instead of sized to clear an obstacle. Serves both an
# explicit `curvature` and the automatic fanning apart of edges that share a
# node pair (which would otherwise draw as overlapping lines).
function _bowed_edge_path(
    p0::Point2f,
    p2::Point2f,
    g_from::_NodeGeom,
    g_to::_NodeGeom,
    h::Float32;
    n::Int = 40,
)
    diff = p2 - p0
    seg_len = _norm2(diff)
    seg_len < 1.0f-6 && return nothing

    nperp = Point2f(-diff[2] / seg_len, diff[1] / seg_len)

    handle_frac = 0.2f0
    p1 = p0 + handle_frac * diff + h * nperp
    p2c = p0 + (1.0f0 - handle_frac) * diff + h * nperp

    return _clip_and_sample_bezier(p0, p1, p2c, p2, g_from, g_to, n)
end

# Shortens a sampled polyline by trim_start/trim_end of arc length at each
# end (interpolating a new endpoint rather than just dropping sample
# points), so a shaft can be trimmed back from an arrowhead's base the same
# way for both straight (2-point) and routed (n-point) paths.
function _trim_polyline(
    pts::AbstractVector{Point2f},
    trim_start::Float32,
    trim_end::Float32,
)
    n = length(pts)
    cum = Vector{Float32}(undef, n)
    cum[1] = 0.0f0
    for i = 2:n
        cum[i] = cum[i-1] + _norm2(pts[i] - pts[i-1])
    end
    total = cum[end]

    function interp_at(s)
        s = clamp(s, 0.0f0, total)
        i = something(findlast(<=(s), cum), 1)
        i >= n && return pts[n]
        seg_total = cum[i+1] - cum[i]
        frac = seg_total > 0 ? (s - cum[i]) / seg_total : 0.0f0
        return pts[i] + frac * (pts[i+1] - pts[i])
    end

    s_lo = trim_start
    s_hi = total - trim_end
    if s_hi < s_lo
        mid = (s_lo + s_hi) / 2.0f0
        s_lo = mid
        s_hi = mid
    end

    keep = [pts[i] for i = 1:n if cum[i] > s_lo && cum[i] < s_hi]
    return vcat([interp_at(s_lo)], keep, [interp_at(s_hi)])
end
