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

_resolve_font(font) =
    font isa Symbol ? Makie.to_font(Makie.current_default_theme()[:fonts], font) :
    Makie.to_font(font)

# Minimum node-circle radius, in pixels, for `label` to fit inside it at the
# given fontsize/font, with `padding` (pixels) clear on every side. Pixels
# rather than data units, because text renders at a fixed pixel size
# regardless of axis zoom; `Makie.plot` converts this once it picks the ratio.
function _text_fit_pixel_radius(label::AbstractString, fontsize::Real, font, padding::Real)
    bb = Makie.text_bb(label, _resolve_font(font), Float32(fontsize))
    w, h = Float32(Makie.widths(bb)[1]), Float32(Makie.widths(bb)[2])
    return 0.5f0 * sqrt(w^2 + h^2) + Float32(padding)
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

# Triangle arrowhead, outlined in `color` and filled with `fill` (which may
# be a transparent/`:transparent` color for a hollow, outline-only arrowhead).
#   tip : the point of the arrow (just clear of the node boundary)
#   dir : unit vector in the direction the arrow points (toward tip)
#   size: length of the arrowhead
function _draw_arrowhead!(
    ax,
    tip::Point2f,
    dir::Point2f,
    size::Float32;
    color = :black,
    fill = color,
    linewidth = 1.5f0,
)
    perp = Point2f(-dir[2], dir[1])
    base = tip - size * dir
    pts = [tip, base + 0.5f0 * size * perp, base - 0.5f0 * size * perp]
    Makie.poly!(ax, pts; color = fill, strokecolor = color, strokewidth = linewidth)
end

function _draw_edge!(
    ax,
    e::CausalEdge,
    p_src::Point2f,
    p_dst::Point2f,
    r_from::Float32,
    r_to::Float32,
    r_arrow::Float32,
    r_circle::Float32,
    obstacles::AbstractVector{Tuple{Point2f,Float32}},
    fan_slot::Float32,
    px_per_data_unit::Float32;
    color = :black,
    fill = color,
    linewidth = 1.5f0,
)
    diff = p_dst - p_src
    len = _norm2(diff)
    len < 1.0f-6 && return

    has_arrow_src = e.src_end === _Arrow
    has_arrow_dst = e.dst_end === _Arrow
    has_circle_src = e.src_end === _Circle
    has_circle_dst = e.dst_end === _Circle

    # Arrowheads and circle marks are stroked outlines, so the stroke paints
    # roughly linewidth/2 (screen pixels) past the path coordinate. Without
    # this gap a tip placed exactly on the node boundary overlaps the node.
    half_lw_data = (Float32(linewidth) / 2.0f0) / px_per_data_unit
    gap_from = (has_arrow_src || has_circle_src) ? half_lw_data : 0.0f0
    gap_to = (has_arrow_dst || has_circle_dst) ? half_lw_data : 0.0f0
    r_from_eff = r_from + gap_from
    r_to_eff = r_to + gap_to

    # Minimum gap (beyond an obstacle's own radius) an edge must keep from a
    # non-incident node before it is left alone.
    clearance = 0.05f0 * (r_from + r_to)

    routed = _route_edge_path(p_src, p_dst, r_from_eff, r_to_eff, obstacles, clearance)
    # Real obstacles take priority: only fan siblings apart when nothing
    # actually forces this edge to route around a node.
    fanned =
        routed === nothing && fan_slot != 0.0f0 ?
        _fanned_edge_path(p_src, p_dst, r_from_eff, r_to_eff, fan_slot * 0.3f0 * len) :
        nothing

    path = if routed !== nothing
        routed
    elseif fanned !== nothing
        fanned
    else
        dir = Point2f(diff[1] / len, diff[2] / len)
        [p_src + r_from_eff * dir, p_dst - r_to_eff * dir]
    end

    m = length(path)
    tan_src = _unit(path[2] - path[1])
    tan_dst = _unit(path[m] - path[m-1])

    # Pull the shaft ends back along the path (by arc length) to leave room
    # for arrowheads.
    trim_start = has_arrow_src ? r_arrow : 0.0f0
    trim_end = has_arrow_dst ? r_arrow : 0.0f0
    shaft = _trim_polyline(path, trim_start, trim_end)
    length(shaft) >= 2 && Makie.lines!(ax, shaft; color = color, linewidth = linewidth)

    has_arrow_dst && _draw_arrowhead!(
        ax,
        path[m],
        tan_dst,
        r_arrow;
        color = color,
        fill = fill,
        linewidth = linewidth,
    )
    has_arrow_src && _draw_arrowhead!(
        ax,
        path[1],
        Point2f(-tan_src[1], -tan_src[2]),
        r_arrow;
        color = color,
        fill = fill,
        linewidth = linewidth,
    )

    # Open circles: centered one radius out from `path`'s endpoint (which
    # already sits gap_from/gap_to past the true node boundary - see above)
    # so the inner edge of the circle sits just clear of the node.
    if has_circle_src
        _draw_filled_circle!(
            ax,
            path[1] + r_circle * tan_src,
            r_circle;
            strokecolor = color,
            strokewidth = linewidth,
        )
    end
    if has_circle_dst
        _draw_filled_circle!(
            ax,
            path[m] - r_circle * tan_dst,
            r_circle;
            strokecolor = color,
            strokewidth = linewidth,
        )
    end
end

# Assigns each edge a signed fan-out slot: 0 when it is the only edge on its
# (unordered) node pair, otherwise evenly spaced values centered on 0. Grouping
# ignores direction so antiparallel edges fan out too, not just an ADMG's
# X --> Y and X <-> Y.
#
# `_fanned_edge_path` bows along each edge's own src->dst vector, so an edge
# stored reversed relative to its group's canonical order would land on the
# same side as its opposite; flipping its slot's sign corrects for that.
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

const _EDGE_TYPE_SYMBOLS = (
    :directed,
    :undirected,
    :bidirected,
    :partially_directed,
    :partially_undirected,
    :partial,
)

# Resolve a per-edge style attribute.
#
# `val` may be:
#   - a scalar  --> applied to all edges
#   - a Dict keyed by any mix of:
#       (Symbol, Symbol)  specific edge, e.g. (:X, :Y) => :red
#       Symbol            a node name, e.g. :X => :red, applied to every
#                         edge touching that node - unless the symbol is one
#                         of the reserved edge-type names below, in which
#                         case it's treated as an edge-type key instead
#       Symbol            edge type,     e.g. :directed => :blue
#       :default          fallback inside the dict
#
# Lookup precedence: specific edge > node-wide (dst, then src) > edge type >
# :default > `fallback`.
function _resolve_edge(val, e::CausalEdge, fallback)
    val isa AbstractDict || return val
    key = (e.src, e.dst)
    haskey(val, key) && return val[key]
    if !(e.dst in _EDGE_TYPE_SYMBOLS) && haskey(val, e.dst)
        return val[e.dst]
    end
    if !(e.src in _EDGE_TYPE_SYMBOLS) && haskey(val, e.src)
        return val[e.src]
    end
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

Visualize a [`CausalGraph`](@ref) using Makie. Requires loading a Makie
backend (e.g. `using CairoMakie`) before calling.

Keyword arguments: `layout`, `node_radius`, `node_padding`, `arrow_size`,
`circle_size`, `node_color`, `node_strokecolor`, `node_strokewidth`,
`edge_color`, `arrow_fill`, `linewidth`, `label_color`, `label_fontsize`,
`label_font`, `title`, `title_fontsize`, `title_color`, `title_gap`,
`outer_margin`, `fig_size`. Style keywords accept either a scalar (applied to everything)
or a `Dict` for per-node/per-edge overrides.

See the [Plotting](@ref plotting-guide) page for the full keyword reference,
styling precedence rules, and examples.

## Examples

```julia
using CausalStructures, CairoMakie

dag = cgraph(directed(:A, :X), directed(:A, :Y), directed(:X, :Y); class = DAG)

Makie.plot(dag; node_color = :lightblue, edge_color = :gray40)
Makie.plot(dag; edge_color = Dict((:A, :X) => :red, :default => :black))
Makie.plot(dag; title = "My DAG", layout = :spring)
```
"""
function Makie.plot(
    cg::CausalGraph;
    layout::Union{Symbol,AbstractVector} = CausalStructures._default_layout_method(),
    node_radius::Union{Real,Nothing} = nothing,
    node_padding::Real = CausalStructures._PLOT_NODE_PADDING_DEFAULT,
    arrow_size::Union{Real,Nothing} = nothing,
    circle_size::Union{Real,Nothing} = nothing,
    node_color = CausalStructures._PLOT_NODE_COLOR_DEFAULT,
    node_strokecolor = CausalStructures._PLOT_NODE_STROKECOLOR_DEFAULT,
    node_strokewidth = CausalStructures._PLOT_NODE_STROKEWIDTH_DEFAULT,
    edge_color = CausalStructures._PLOT_EDGE_COLOR_DEFAULT,
    arrow_fill = CausalStructures._PLOT_EDGE_ARROW_FILL_DEFAULT,
    linewidth = CausalStructures._PLOT_LINEWIDTH_DEFAULT,
    label_color = CausalStructures._PLOT_LABEL_COLOR_DEFAULT,
    label_fontsize = CausalStructures._PLOT_LABEL_FONTSIZE_DEFAULT,
    label_font = CausalStructures._PLOT_LABEL_FONT_DEFAULT,
    title::Union{AbstractString,Nothing} = nothing,
    title_fontsize::Union{Real,Nothing} = nothing,
    title_color = nothing,
    outer_margin::Real = 16,
    title_gap::Real = 4.0,
    fig_size::NTuple{2,Real} = CausalStructures._PLOT_FIG_SIZE_DEFAULT,
    layout_kwargs...,
)
    n = length(cg.backend.nodes)
    n == 0 && error("Cannot plot an empty graph (0 nodes).")

    positions = _rescale_to_unit_extent(_positions(cg, layout, layout_kwargs))

    # Reference radius (node-count based, ignoring label length), used only
    # when node_radius is given explicitly.
    r_ref = Float32(something(node_radius, max(0.12, 0.4 * sin(π / max(n, 2)))))

    # The figure is a fixed size (`fig_size`) so the same graph doesn't render
    # at a different size per layout algorithm. Node radii (data units) are
    # then solved for the pixels-per-data-unit ratio that canvas implies, since
    # text is fixed-pixel-sized regardless of zoom (`_text_fit_pixel_radius`).
    # Tightly-clustered nodes therefore get smaller circles rather than
    # blowing up the figure.
    xs = [p[1] for p in positions]
    ys = [p[2] for p in positions]
    bbox_w = max(maximum(xs) - minimum(xs), 1.0f-3)
    bbox_h = max(maximum(ys) - minimum(ys), 1.0f-3)

    fig_height_budget = Float32(fig_size[2]) - (title !== nothing ? 40.0f0 : 0.0f0)
    avail_w = Float32(fig_size[1]) - 2.0f0 * Float32(outer_margin)
    avail_h = fig_height_budget - 2.0f0 * Float32(outer_margin)

    r_nodes = if node_radius !== nothing
        fill(r_ref, n)
    else
        pixel_radii = Float32[
            max(
                6.0f0,
                _text_fit_pixel_radius(
                    string(cg.backend.nodes[i]),
                    _resolve_node(label_fontsize, cg.backend.nodes[i], 14.0f0),
                    _resolve_node(label_font, cg.backend.nodes[i], :regular),
                    node_padding,
                ),
            ) for i = 1:n
        ]
        # px_per_unit that keeps the closest label-fit pair from overlapping.
        px_overlap = 400.0f0
        for i = 1:n, j = (i+1):n
            d = _norm2(positions[i] - positions[j])
            d < 1.0f-6 && continue
            px_overlap = max(px_overlap, 1.15f0 * (pixel_radii[i] + pixel_radii[j]) / d)
        end
        # px_per_unit that fits the bbox (plus a margin sized to the largest
        # label, in data units at that same ratio) inside the fixed canvas.
        # Solved in closed form: margin = 1.3*maxpr/px, so
        # px*bbox + 2*1.3*maxpr = avail  =>  px = (avail - 2.6*maxpr)/bbox.
        maxpr = maximum(pixel_radii)
        px_fit_w = (avail_w - 2.6f0 * maxpr) / bbox_w
        px_fit_h = (avail_h - 2.6f0 * maxpr) / bbox_h
        px_per_unit = max(10.0f0, min(px_overlap, px_fit_w, px_fit_h))
        pixel_radii ./ px_per_unit
    end

    # Based on the typical (not per-node) radius, so endpoint marks stay
    # consistent across the plot regardless of any one node's label length.
    r_typical = node_radius !== nothing ? r_ref : Float32(sum(r_nodes) / n)
    r_arrow = Float32(something(arrow_size, r_typical * 0.4f0))
    r_circle = Float32(something(circle_size, r_typical * 0.28f0))

    node_pos = Dict{Symbol,Point2f}(
        cg.backend.nodes[i] => positions[i] for i in eachindex(cg.backend.nodes)
    )
    node_idx =
        Dict{Symbol,Int}(cg.backend.nodes[i] => i for i in eachindex(cg.backend.nodes))
    fan_slots = _edge_fan_slots(cg.edges)

    # Explicit axis data limits: Makie's autolimits ignore the node circles'
    # rendered extent, so boundary nodes would clip.
    margin = 1.3f0 * maximum(r_nodes)
    xlo, xhi = minimum(xs) - margin, maximum(xs) + margin
    ylo, yhi = minimum(ys) - margin, maximum(ys) + margin
    xlo == xhi && (xlo -= 1.0f0; xhi += 1.0f0)
    ylo == yhi && (ylo -= 1.0f0; yhi += 1.0f0)

    # DataAspect renders both axes at the same scale, set by whichever of x/y
    # is the tighter fit against the fixed canvas.
    px_per_data_unit = min(avail_w / (xhi - xlo), avail_h / (yhi - ylo))

    fig = Makie.Figure(;
        size = (round(Int, fig_size[1]), round(Int, fig_size[2])),
        figure_padding = outer_margin,
    )
    ax = if title === nothing
        Makie.Axis(fig[1, 1]; aspect = Makie.DataAspect(), limits = (xlo, xhi, ylo, yhi))
    else
        title_kwargs = Dict{Symbol,Any}(:titlegap => Float32(title_gap))
        title_fontsize !== nothing &&
            (title_kwargs[:titlesize] = Float32(title_fontsize))
        title_color !== nothing && (title_kwargs[:titlecolor] = title_color)
        Makie.Axis(
            fig[1, 1];
            aspect = Makie.DataAspect(),
            limits = (xlo, xhi, ylo, yhi),
            title = title,
            title_kwargs...,
        )
    end
    Makie.hidedecorations!(ax)
    Makie.hidespines!(ax)

    # Edges drawn first so nodes appear on top.
    for (i, e) in enumerate(cg.edges)
        # Every other node is a candidate obstacle for routing, at its own
        # (possibly text-fit) radius.
        src_idx = node_idx[e.src]
        dst_idx = node_idx[e.dst]
        obstacles = Tuple{Point2f,Float32}[
            (positions[j], r_nodes[j]) for
            j in eachindex(positions) if j != src_idx && j != dst_idx
        ]

        resolved_color = _resolve_edge(edge_color, e, :black)
        _draw_edge!(
            ax,
            e,
            node_pos[e.src],
            node_pos[e.dst],
            r_nodes[src_idx],
            r_nodes[dst_idx],
            r_arrow,
            r_circle,
            obstacles,
            fan_slots[i],
            px_per_data_unit;
            color = resolved_color,
            fill = something(_resolve_edge(arrow_fill, e, nothing), resolved_color),
            linewidth = Float32(_resolve_edge(linewidth, e, 1.5f0)),
        )
    end

    for i in eachindex(cg.backend.nodes)
        node = cg.backend.nodes[i]
        _draw_filled_circle!(
            ax,
            positions[i],
            r_nodes[i];
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
            color = _resolve_node(label_color, node, :black),
            fontsize = Float32(_resolve_node(label_fontsize, node, 14.0f0)),
            font = _resolve_node(label_font, node, :regular),
        )
    end

    return fig
end
