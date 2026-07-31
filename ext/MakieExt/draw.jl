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

# Draw one edge with the correct endpoint decorations.
#
# An edge whose straight center-to-center chord would pass too close to a
# non-incident node (any entry in `obstacles`) is bent around it into a
# Bezier curve (see routing.jl). Otherwise, if this edge shares its pair of
# nodes with `sibling_count - 1` other edges (e.g. an ADMG's X --> Y and
# X <-> Y), it is fanned out by `fan_slot` so the group doesn't draw as
# overlapping lines. An edge with nothing in its way and no siblings is drawn
# as a straight line, matching the previous behavior.
function _draw_edge!(
    ax,
    e::CausalEdge,
    p_src::Point2f,
    p_dst::Point2f,
    r_node::Float32,
    r_arrow::Float32,
    r_circle::Float32,
    obstacles::AbstractVector{Tuple{Point2f,Float32}},
    fan_slot::Float32;
    color = :black,
    linewidth = 1.5f0,
)
    diff = p_dst - p_src
    len = _norm2(diff)
    len < 1.0f-6 && return

    # Minimum gap (beyond an obstacle's own radius) an edge must keep from a
    # non-incident node before it is left alone.
    clearance = 0.1f0 * r_node

    routed = _route_edge_path(p_src, p_dst, r_node, r_node, obstacles, clearance)
    # Real obstacles take priority: only fan siblings apart when nothing
    # actually forces this edge to route around a node.
    fanned =
        routed === nothing && fan_slot != 0.0f0 ?
        _fanned_edge_path(p_src, p_dst, r_node, r_node, fan_slot * 0.3f0 * len) : nothing

    path = if routed !== nothing
        routed
    elseif fanned !== nothing
        fanned
    else
        dir = Point2f(diff[1] / len, diff[2] / len)
        [p_src + r_node * dir, p_dst - r_node * dir]
    end

    has_arrow_src = e.src_end === _Arrow
    has_arrow_dst = e.dst_end === _Arrow
    has_circle_src = e.src_end === _Circle
    has_circle_dst = e.dst_end === _Circle

    m = length(path)
    tan_src = _unit(path[2] - path[1])
    tan_dst = _unit(path[m] - path[m-1])

    # Pull the shaft ends back along the path (by arc length) to leave room
    # for arrowheads.
    trim_start = has_arrow_src ? r_arrow : 0.0f0
    trim_end = has_arrow_dst ? r_arrow : 0.0f0
    shaft = _trim_polyline(path, trim_start, trim_end)
    length(shaft) >= 2 && Makie.lines!(ax, shaft; color = color, linewidth = linewidth)

    has_arrow_dst && _draw_arrowhead!(ax, path[m], tan_dst, r_arrow; color = color)
    has_arrow_src && _draw_arrowhead!(
        ax,
        path[1],
        Point2f(-tan_src[1], -tan_src[2]),
        r_arrow;
        color = color,
    )

    # Open circles: centered one radius out from the node boundary (tangent
    # to the path) so the inner edge of the circle sits flush against the node.
    if has_circle_src
        _draw_filled_circle!(
            ax,
            path[1] + r_circle * tan_src,
            r_circle;
            strokecolor = color,
        )
    end
    if has_circle_dst
        _draw_filled_circle!(
            ax,
            path[m] - r_circle * tan_dst,
            r_circle;
            strokecolor = color,
        )
    end
end

# Assigns each edge a signed fan-out slot: 0 for edges that are the only one
# connecting their (unordered) pair of nodes, and evenly spaced values
# centered on 0 for edges sharing a pair with others (regardless of edge
# type or direction) - e.g. an ADMG's X --> Y and X <-> Y, or a graph with
# two antiparallel edges A --> B and B --> A. Grouping ignores direction so
# that antiparallel edges fan out too, since they'd otherwise draw as
# perfectly overlapping lines just like same-direction duplicates.
#
# `_fanned_edge_path` derives its bow direction from each edge's own
# src->dst vector, so an edge stored in the reverse direction of its
# group's canonical order (`key[1] --> key[2]`) would otherwise cancel out
# a same-signed slot instead of landing on the opposite side; flipping its
# slot's sign corrects for that.
function _edge_fan_slots(edges::AbstractVector{CausalEdge})
    groups = Dict{Tuple{Symbol,Symbol},Vector{Int}}()
    for (i, e) in enumerate(edges)
        key = e.src < e.dst ? (e.src, e.dst) : (e.dst, e.src)
        push!(get!(() -> Int[], groups, key), i)
    end

    slots = zeros(Float32, length(edges))
    for (key, idxs) in groups
        k = length(idxs)
        k == 1 && continue
        for (rank, i) in enumerate(idxs)
            raw = Float32(rank - 1) - Float32(k - 1) / 2.0f0
            flip = edges[i].src == key[1] ? 1.0f0 : -1.0f0
            slots[i] = raw * flip
        end
    end
    return slots
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

Edges are routed automatically: a straight `src --> dst` line that would pass
too close to a non-incident node bends around it as a Bezier curve instead;
edges with nothing in their way are always drawn straight. Multiple edges
sharing a pair of nodes (e.g. an ADMG's `X --> Y` and `X <-> Y`) are fanned
out into distinct arcs instead of drawing on top of each other.

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

# A, X, Y placed in a line: A --> Y automatically bends around X, since the
# straight line between A and Y would otherwise cross it.
Makie.plot(dag; layout = [(0, 0), (1, 0), (2, 0)])

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
    node_idx =
        Dict{Symbol,Int}(cg.backend.nodes[i] => i for i in eachindex(cg.backend.nodes))
    fan_slots = _edge_fan_slots(cg.edges)

    fig = Makie.Figure()
    ax = Makie.Axis(fig[1, 1]; aspect = Makie.DataAspect())
    Makie.hidedecorations!(ax)
    Makie.hidespines!(ax)

    # Edges drawn first so nodes appear on top.
    for (i, e) in enumerate(cg.edges)
        # Every other node is a candidate obstacle for routing (all nodes
        # share the same radius r_node).
        src_idx = node_idx[e.src]
        dst_idx = node_idx[e.dst]
        obstacles = Tuple{Point2f,Float32}[
            (positions[j], r_node) for
            j in eachindex(positions) if j != src_idx && j != dst_idx
        ]

        _draw_edge!(
            ax,
            e,
            node_pos[e.src],
            node_pos[e.dst],
            r_node,
            r_arrow,
            r_circle,
            obstacles,
            fan_slots[i];
            color = _resolve_edge(edge_color, e, :black),
            linewidth = Float32(_resolve_edge(linewidth, e, 1.5f0)),
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
