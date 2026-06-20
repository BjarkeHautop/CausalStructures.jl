# Drawing primitives and the cgraph_plot implementation.
#
# Endpoint semantics per CausalEdge:
#   src_end / dst_end : Tail | Arrow | Circle
#
# Edge type - endpoint marks:
#   -->   Tail  - Arrow   : line + arrowhead at dst
#   ---   Tail  - Tail    : plain line
#   <->   Arrow - Arrow   : line + arrowheads at both ends
#   o->   Circle- Arrow   : open circle at src + arrowhead at dst
#   o--   Circle- Tail    : open circle at src + line
#   o-o   Circle- Circle  : open circles at both ends

const _Tail = CausalStructures.Tail
const _Arrow = CausalStructures.Arrow
const _Circle = CausalStructures.Circle

function _norm2(p::Point2f)
    sqrt(p[1]^2 + p[2]^2)
end

# Filled circle polygon in data coordinates (used for both node bodies and
# open-circle endpoint markers).
function _draw_filled_circle!(
    ax,
    center::Point2f,
    radius::Float32;
    color = :white,
    strokecolor = :black,
    strokewidth = 1.5f0,
)
    n = 60
    θ = (2.0f0 * Float32(π) * i / n for i = 0:n)
    pts = [Point2f(center[1] + radius * cos(t), center[2] + radius * sin(t)) for t in θ]
    Makie.poly!(
        ax,
        pts;
        color = color,
        strokecolor = strokecolor,
        strokewidth = strokewidth,
    )
end

# Solid filled triangle arrowhead.
#   tip : the point of the arrow (on the node boundary)
#   dir : unit vector in the direction the arrow points (toward tip)
#   size: length of the arrowhead
function _draw_arrowhead!(ax, tip::Point2f, dir::Point2f, size::Float32; color = :black)
    perp = Point2f(-dir[2], dir[1])
    base = tip - size * dir
    pts = [tip, base + 0.5f0 * size * perp, base - 0.5f0 * size * perp]
    Makie.poly!(ax, pts; color = color, strokecolor = color, strokewidth = 0.0f0)
end

# Sample a quadratic Bezier B(t) = (1-t)^2 p0 + 2(1-t)t c + t^2 p1.
function _bezier(p0::Point2f, c::Point2f, p1::Point2f, t::Float32)
    u = 1.0f0 - t
    return u * u * p0 + 2.0f0 * u * t * c + t * t * p1
end

# Unit tangent of the quadratic Bezier at t (derivative 2(1-t)(c-p0) + 2t(p1-c)).
function _bezier_tangent(p0::Point2f, c::Point2f, p1::Point2f, t::Float32)
    u = 1.0f0 - t
    d = 2.0f0 * u * (c - p0) + 2.0f0 * t * (p1 - c)
    n = _norm2(d)
    return n < 1.0f-6 ? Point2f(0, 0) : Point2f(d[1] / n, d[2] / n)
end

# Draw one edge with the correct endpoint decorations.
#
# `curvature` bows the edge perpendicular to the chord: 0 is a straight line,
# positive curves to the left of the src->dst direction, negative to the right.
# The control point is offset from the chord midpoint by `curvature * len`.
function _draw_edge!(
    ax,
    e::CausalEdge,
    p_src::Point2f,
    p_dst::Point2f,
    r_node::Float32,
    r_arrow::Float32,
    r_circle::Float32;
    color = :black,
    linewidth = 1.5f0,
    curvature = 0.0f0,
)
    diff = p_dst - p_src
    len = _norm2(diff)
    len < 1.0f-6 && return
    dir = Point2f(diff[1] / len, diff[2] / len)

    # Points on the node boundaries along the (straight) edge direction.
    src_bnd = p_src + r_node * dir
    dst_bnd = p_dst - r_node * dir

    has_arrow_src = e.src_end === _Arrow
    has_arrow_dst = e.dst_end === _Arrow
    has_circle_src = e.src_end === _Circle
    has_circle_dst = e.dst_end === _Circle

    # Control point: chord midpoint offset perpendicular to the chord.
    perp = Point2f(-dir[2], dir[1])
    mid = 0.5f0 * (src_bnd + dst_bnd)
    ctrl = mid + curvature * len * perp

    # Endpoint tangents follow the curve, not the chord, so decorations line up.
    tan_src = _bezier_tangent(src_bnd, ctrl, dst_bnd, 0.0f0)
    tan_dst = _bezier_tangent(src_bnd, ctrl, dst_bnd, 1.0f0)

    # Pull the shaft ends back along the local tangent to leave room for heads.
    line_start = has_arrow_src ? src_bnd + r_arrow * tan_src : src_bnd
    line_end = has_arrow_dst ? dst_bnd - r_arrow * tan_dst : dst_bnd

    if _norm2(line_end - line_start) > 1.0f-6
        if abs(curvature) < 1.0f-6
            Makie.lines!(ax, [line_start, line_end]; color = color, linewidth = linewidth)
        else
            nseg = 32
            pts = [_bezier(line_start, ctrl, line_end, Float32(i) / nseg) for i = 0:nseg]
            Makie.lines!(ax, pts; color = color, linewidth = linewidth)
        end
    end

    has_arrow_dst && _draw_arrowhead!(ax, dst_bnd, tan_dst, r_arrow; color = color)
    has_arrow_src && _draw_arrowhead!(
        ax,
        src_bnd,
        Point2f(-tan_src[1], -tan_src[2]),
        r_arrow;
        color = color,
    )

    # Open circles: centered one radius out from the node boundary so the
    # inner edge of the circle sits flush against the node.
    if has_circle_src
        _draw_filled_circle!(
            ax,
            src_bnd + r_circle * tan_src,
            r_circle;
            strokecolor = color,
        )
    end
    if has_circle_dst
        _draw_filled_circle!(
            ax,
            dst_bnd - r_circle * tan_dst,
            r_circle;
            strokecolor = color,
        )
    end
end

function _edge_type(e::CausalEdge)
    s, d = e.src_end, e.dst_end
    s === _Tail && d === _Arrow && return :directed
    s === _Tail && d === _Tail && return :undirected
    s === _Arrow && d === _Arrow && return :bidirected
    s === _Circle && d === _Arrow && return :partially_directed
    s === _Circle && d === _Tail && return :partially_undirected
    s === _Circle && d === _Circle && return :partial
    return :unknown
end

# Resolve a per-edge style attribute.
#
# `val` may be:
#   - a scalar  --> applied to all edges
#   - a Dict keyed by any mix of:
#       (Symbol, Symbol)  specific edge, e.g. (:X, :Y) => :red
#       Symbol            edge type,     e.g. :directed => :blue
#       :default          fallback inside the dict
#
# Lookup precedence: specific edge > edge type > :default > `fallback`.
function _resolve_edge(val, e::CausalEdge, fallback)
    val isa AbstractDict || return val
    key = (e.src, e.dst)
    haskey(val, key) && return val[key]
    key = _edge_type(e)
    haskey(val, key) && return val[key]
    haskey(val, :default) && return val[:default]
    return fallback
end

# Resolve a per-node style attribute.
#
# `val` may be a scalar or a Dict{Symbol, <value>} keyed by node name.
# Dict may also contain :default as a fallback.
function _resolve_node(val, node::Symbol, fallback)
    val isa AbstractDict || return val
    haskey(val, node) && return val[node]
    haskey(val, :default) && return val[:default]
    return fallback
end

"""
    Makie.plot(cg; kwargs...) -> Figure

Visualize a [`CausalGraph`](@ref) using Makie. Requires loading a Makie backend
(e.g. `using CairoMakie`) before calling.

## Geometry keyword arguments

| Keyword        | Default                              | Description                        |
|----------------|--------------------------------------|------------------------------------|
| `node_radius`  | `max(0.12, 0.4 sin(π/n))`            | Radius of each node circle         |
| `arrow_size`   | `0.4 x node_radius`                  | Length of arrowhead triangles      |
| `circle_size`  | `0.28 x node_radius`                 | Radius of open-circle endpoints    |

## Style keyword arguments

Each style argument accepts either a **scalar** (applied to all elements) or a
**`Dict`** for fine-grained control. Defaults marked † are configurable via
`Preferences.jl`; see the [Preferences](@ref) page.

### Node styles

| Keyword             | Default †  | Dict key type |
|---------------------|------------|---------------|
| `node_color`        | `"white"`  | `Symbol` (node name) |
| `node_strokecolor`  | `"black"`  | `Symbol` (node name) |
| `node_strokewidth`  | `2.0`      | `Symbol` (node name) |

### Edge styles

| Keyword       | Default †  | Dict key type                                  |
|---------------|------------|------------------------------------------------|
| `edge_color`  | `"black"`  | `Symbol` (edge type) or `(Symbol, Symbol)` (src, dst) |
| `linewidth`   | `1.5`      | `Symbol` (edge type) or `(Symbol, Symbol)` (src, dst) |
| `curvature`   | `0.0`      | `Symbol` (edge type) or `(Symbol, Symbol)` (src, dst) |

`curvature` bows each edge perpendicular to the straight `src --> dst` chord:
`0.0` draws a straight line, positive values bend to the left of that direction
and negative to the right.

**Edge-type symbols:** `:directed`, `:undirected`, `:bidirected`,
`:partially_directed`, `:partially_undirected`, `:partial`.

**Dict lookup precedence (highest --> lowest):**
1. Specific edge `(src, dst)` pair
2. Edge-type symbol
3. `:default` key inside the Dict
4. Hard-coded fallback

## Layout

The `layout` keyword controls node placement (default † `:circle`). `:circle`
is always available; the remaining methods require `using NetworkLayout`:

| `layout`      | Algorithm                           |
|---------------|-------------------------------------|
| `:circle`     | Evenly spaced on a circle (default) |
| `:spring`     | Fruchterman-Reingold force-directed |
| `:stress`     | Stress majorization                 |
| `:sfdp`       | Scalable Force-Directed Placement   |
| `:spectral`   | Spectral layout                     |
| `:shell`      | Concentric shells                   |
| `:squaregrid` | Square grid                         |

Alternatively, `layout` may be set to a custom `AbstractVector` of 2D coordinates
in the same order as `nodes(cg)`.

Extra keyword arguments are forwarded to the NetworkLayout algorithm
(e.g. `seed`, `iterations`).

## Examples

```julia
using CausalStructures, CairoMakie

dag = cgraph(directed(:A, :X), directed(:A, :Y), directed(:X, :Y); class = DAG)

# Global styling
Makie.plot(dag; node_color = :lightblue, edge_color = :gray40)

# Per-node colors
Makie.plot(dag; node_color = Dict(:A => :salmon, :default => :white))

# Per-edge-type colors
admg = cgraph(directed(:X, :Y), bidirected(:X, :Z); class = ADMG)
Makie.plot(admg; edge_color = Dict(:directed => :steelblue, :bidirected => :crimson))

# Highlight a specific edge
Makie.plot(dag; edge_color = Dict((:A, :X) => :red, :default => :black))

# Curve all edges; bow parallel edges apart in an ADMG
Makie.plot(dag; curvature = 0.2)
Makie.plot(admg; curvature = Dict(:directed => 0.2, :bidirected => -0.2))

# Force-directed layout (requires NetworkLayout)
using NetworkLayout
Makie.plot(dag; layout = :spring)
Makie.plot(dag; layout = :spring, seed = 42, iterations = 200)

# Custom layout (e.g. after manual tweaks)
positions = layout(dag, :spring)
positions[1] += (0.1, -0.05)
Makie.plot(dag; layout = positions)
```
"""
function Makie.plot(
    cg::CausalGraph;
    layout::Union{Symbol,AbstractVector} = CausalStructures._PLOT_LAYOUT_DEFAULT,
    node_radius::Union{Real,Nothing} = nothing,
    arrow_size::Union{Real,Nothing} = nothing,
    circle_size::Union{Real,Nothing} = nothing,
    node_color = CausalStructures._PLOT_NODE_COLOR_DEFAULT,
    node_strokecolor = CausalStructures._PLOT_NODE_STROKECOLOR_DEFAULT,
    node_strokewidth = CausalStructures._PLOT_NODE_STROKEWIDTH_DEFAULT,
    edge_color = CausalStructures._PLOT_EDGE_COLOR_DEFAULT,
    linewidth = CausalStructures._PLOT_LINEWIDTH_DEFAULT,
    curvature = CausalStructures._PLOT_CURVATURE_DEFAULT,
    layout_kwargs...,
)
    n = length(cg.backend.nodes)
    n == 0 && error("Cannot plot an empty graph (0 nodes).")

    positions = _positions(cg, layout, layout_kwargs)

    r_node = Float32(something(node_radius, max(0.12, 0.4 * sin(π / max(n, 2)))))
    r_arrow = Float32(something(arrow_size, r_node * 0.4f0))
    r_circle = Float32(something(circle_size, r_node * 0.28f0))

    node_pos = Dict{Symbol,Point2f}(
        cg.backend.nodes[i] => positions[i] for i in eachindex(cg.backend.nodes)
    )

    fig = Makie.Figure()
    ax = Makie.Axis(fig[1, 1]; aspect = Makie.DataAspect())
    Makie.hidedecorations!(ax)
    Makie.hidespines!(ax)

    # Edges drawn first so nodes appear on top.
    for e in cg.edges
        _draw_edge!(
            ax,
            e,
            node_pos[e.src],
            node_pos[e.dst],
            r_node,
            r_arrow,
            r_circle;
            color = _resolve_edge(edge_color, e, :black),
            linewidth = Float32(_resolve_edge(linewidth, e, 1.5f0)),
            curvature = Float32(_resolve_edge(curvature, e, 0.0f0)),
        )
    end

    # Node circles and labels.
    for i in eachindex(cg.backend.nodes)
        node = cg.backend.nodes[i]
        _draw_filled_circle!(
            ax,
            positions[i],
            r_node;
            color = _resolve_node(node_color, node, :white),
            strokecolor = _resolve_node(node_strokecolor, node, :black),
            strokewidth = Float32(_resolve_node(node_strokewidth, node, 2.0f0)),
        )
        Makie.text!(
            ax,
            positions[i][1],
            positions[i][2];
            text = string(node),
            align = (:center, :center),
            fontsize = 14,
        )
    end

    return fig
end
