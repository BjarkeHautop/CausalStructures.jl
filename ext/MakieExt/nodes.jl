# Node geometry: shapes, boundary hit-testing, and label-fit sizing.
#
# A node is drawn either :round or as a :box, the latter being the usual mark
# for a variable that is conditioned on.

const _NODE_SHAPES = (:round, :box)

# How oblong a label must be before a node stretches rather than growing to
# equal sides.
const _NODE_ASPECT_CAP = 1.4f0

struct _NodeGeom
    center::Point2f
    shape::Symbol
    hw::Float32
    hh::Float32
end

# Grows the outline by `pad` on every side.
_inflate(g::_NodeGeom, pad::Float32) = _NodeGeom(g.center, g.shape, g.hw + pad, g.hh + pad)

# Edge routing treats nodes as circular obstacles, so a box gets its corner.
function _circumradius(g::_NodeGeom)
    g.shape === :round && return max(g.hw, g.hh)
    return sqrt(g.hw^2 + g.hh^2)
end

# Center-to-boundary distance along the unit vector `dir`, i.e. where an edge
# leaving in that direction starts.
function _boundary_distance(g::_NodeGeom, dir::Point2f)
    c, s = abs(dir[1]), abs(dir[2])
    if g.shape === :round
        denom = sqrt((g.hh * c)^2 + (g.hw * s)^2)
        return denom < 1.0f-6 ? min(g.hw, g.hh) : g.hw * g.hh / denom
    end
    tx = c < 1.0f-6 ? Inf32 : g.hw / c
    ty = s < 1.0f-6 ? Inf32 : g.hh / s
    return min(tx, ty)
end

# Distance to `p` as a fraction of the boundary in that direction: < 1 inside,
# > 1 outside, so one bisection clips a curve against either shape.
function _radial_fraction(g::_NodeGeom, p::Point2f)
    v = p - g.center
    n = _norm2(v)
    n < 1.0f-6 && return 0.0f0
    return n / _boundary_distance(g, Point2f(v[1] / n, v[2] / n))
end

function _shape_polygon(g::_NodeGeom; n::Int = 60)
    if g.shape === :box
        x, y = g.center[1], g.center[2]
        return [
            Point2f(x - g.hw, y - g.hh),
            Point2f(x + g.hw, y - g.hh),
            Point2f(x + g.hw, y + g.hh),
            Point2f(x - g.hw, y + g.hh),
            Point2f(x - g.hw, y - g.hh),
        ]
    end
    return [
        Point2f(
            g.center[1] + g.hw * cos(2.0f0 * Float32(π) * i / n),
            g.center[2] + g.hh * sin(2.0f0 * Float32(π) * i / n),
        ) for i = 0:n
    ]
end

# A dashed border is stroked separately, since `poly!`'s own stroke is solid.
function _draw_node!(
    ax,
    g::_NodeGeom;
    color = :white,
    strokecolor = :black,
    strokewidth = 1.5f0,
    linestyle = nothing,
)
    pts = _shape_polygon(g)
    if linestyle === nothing
        Makie.poly!(
            ax,
            pts;
            color = color,
            strokecolor = strokecolor,
            strokewidth = strokewidth,
        )
    else
        Makie.poly!(ax, pts; color = color, strokewidth = 0)
        Makie.lines!(
            ax,
            pts;
            color = strokecolor,
            linewidth = strokewidth,
            linestyle = linestyle,
        )
    end
    return nothing
end

# Rendered size (pixels) of a label. LaTeXStrings and `rich` text are measured
# through their string form, which is approximate but keeps sizing finite.
function _text_pixel_size(label, fontsize::Real, font)
    s = label isa AbstractString ? String(label) : string(label)
    lines = split(s, '\n')
    f = _resolve_font(font)
    w = 0.0f0
    h = 0.0f0
    for line in lines
        bb = try
            Makie.text_bb(isempty(line) ? " " : String(line), f, Float32(fontsize))
        catch
            nothing
        end
        lw, lh =
            bb === nothing ? (Float32(fontsize) * length(line) * 0.6f0, Float32(fontsize)) :
            (Float32(Makie.widths(bb)[1]), Float32(Makie.widths(bb)[2]))
        w = max(w, lw)
        h = max(h, lh)
    end
    # 1.2 line spacing, matching Makie's default `lineheight`.
    return w, h * (1.0f0 + 1.2f0 * (length(lines) - 1))
end

# Half-extents (pixels) fitting `label` inside a node of the given shape, with
# `padding` clear on every side, equalized while within `_NODE_ASPECT_CAP`.
# Pixels because text is fixed-pixel-sized; `Makie.plot` converts to data units
# once it picks the ratio.
function _text_fit_pixel_size(label, shape::Symbol, fontsize::Real, font, padding::Real)
    w, h = _text_pixel_size(label, fontsize, font)
    pad = Float32(padding)

    # A round node needs the text box inscribed in the ellipse, which
    # hw = w/sqrt(2), hh = h/sqrt(2) satisfies.
    hw, hh = if shape === :round
        w / sqrt(2.0f0) + pad, h / sqrt(2.0f0) + pad
    else
        0.5f0 * w + pad, 0.5f0 * h + pad
    end

    hi, lo = max(hw, hh), min(hw, hh)
    (lo <= 0.0f0 || hi / lo <= _NODE_ASPECT_CAP) && return hi, hi
    return hw, hh
end
