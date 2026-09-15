# Drawing primitives and the plot recipe.
#
# Each CausalEdge carries src_end / dst_end (Tail | Arrow | Circle), drawn as
# a plain end, an arrowhead, or an open circle - see `_edge_type`.

const _Tail = CausalStructures.Tail
const _Arrow = CausalStructures.Arrow
const _Circle = CausalStructures.Circle

function _norm2(p::Point2f)
    sqrt(p[1]^2 + p[2]^2)
end

_resolve_font(font) =
    font isa Symbol ? Makie.to_font(Makie.current_default_theme()[:fonts], font) :
    Makie.to_font(font)

# Filled circle polygon in data coordinates, for open-circle edge markers.
function _draw_filled_circle!(
    parent,
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
        parent,
        pts;
        color = color,
        strokecolor = strokecolor,
        strokewidth = strokewidth,
    )
end

# Triangle arrowhead, outlined in `color` and filled with `fill` (which may
# be a transparent/`:transparent` color for a hollow, outline-only arrowhead).
function _draw_arrowhead!(
    parent,
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
    Makie.poly!(parent, pts; color = fill, strokecolor = color, strokewidth = linewidth)
end

function _edge_path(
    e::CausalEdge,
    g_src::_NodeGeom,
    g_dst::_NodeGeom,
    obstacles::AbstractVector{Tuple{Point2f,Float32}},
    fan_slot::Float32,
    curvature::Union{Float32,Nothing},
    px_per_data_unit::Float32,
    linewidth::Real,
    explicit_path::Union{AbstractVector{Point2f},Nothing} = nothing,
)
    p_src, p_dst = g_src.center, g_dst.center
    diff = p_dst - p_src
    len = _norm2(diff)
    len < 1.0f-6 && return nothing

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
    g_from = _inflate(g_src, gap_from)
    g_to = _inflate(g_dst, gap_to)

    explicit =
        explicit_path === nothing ? nothing : _clip_edge_path(explicit_path, g_from, g_to)
    explicit !== nothing && return explicit

    # Minimum gap (beyond an obstacle's own radius) an edge must keep from a
    # non-incident node before it is left alone.
    clearance = 0.2f0 * (_circumradius(g_src) + _circumradius(g_dst))

    bowed =
        curvature !== nothing ?
        _bowed_edge_path(p_src, p_dst, g_from, g_to, curvature * len) : nothing
    routed =
        bowed === nothing ?
        _route_edge_path(p_src, p_dst, g_from, g_to, obstacles, clearance) : nothing
    fanned =
        bowed === nothing && routed === nothing && fan_slot != 0.0f0 ?
        _bowed_edge_path(p_src, p_dst, g_from, g_to, fan_slot * 0.3f0 * len) : nothing

    if bowed !== nothing
        bowed
    elseif routed !== nothing
        routed
    elseif fanned !== nothing
        fanned
    else
        dir = Point2f(diff[1] / len, diff[2] / len)
        [
            p_src + _boundary_distance(g_from, dir) * dir,
            p_dst - _boundary_distance(g_to, dir) * dir,
        ]
    end
end

function _draw_edge!(
    parent,
    e::CausalEdge,
    g_src::_NodeGeom,
    g_dst::_NodeGeom,
    r_arrow::Float32,
    r_circle::Float32,
    obstacles::AbstractVector{Tuple{Point2f,Float32}},
    fan_slot::Float32,
    curvature::Union{Float32,Nothing},
    px_per_data_unit::Float32,
    explicit_path::Union{AbstractVector{Point2f},Nothing} = nothing;
    color = :black,
    fill = color,
    linewidth = 1.5f0,
)
    path = _edge_path(
        e,
        g_src,
        g_dst,
        obstacles,
        fan_slot,
        curvature,
        px_per_data_unit,
        linewidth,
        explicit_path,
    )
    path === nothing && return

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
    length(shaft) >= 2 && Makie.lines!(parent, shaft; color = color, linewidth = linewidth)

    has_arrow_dst && _draw_arrowhead!(
        parent,
        path[m],
        tan_dst,
        r_arrow;
        color = color,
        fill = fill,
        linewidth = linewidth,
    )
    has_arrow_src && _draw_arrowhead!(
        parent,
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
            parent,
            path[1] + r_circle * tan_src,
            r_circle;
            strokecolor = color,
            strokewidth = linewidth,
        )
    end
    if has_circle_dst
        _draw_filled_circle!(
            parent,
            path[m] - r_circle * tan_dst,
            r_circle;
            strokecolor = color,
            strokewidth = linewidth,
        )
    end
end

# Signed fan-out slot per edge: 0 if it's alone on its node pair, otherwise
# evenly spaced around 0, ignoring direction so antiparallel edges fan out
# too. Since `_bowed_edge_path` bows along each edge's own src->dst vector, a
# reversed edge needs its sign flipped to land opposite its sibling.
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

# Resolve a per-edge style attribute: a scalar, or a Dict keyed by CausalEdge,
# (src, dst) tuple, node name, edge type, or :default, most specific first.
function _resolve_edge(val, e::CausalEdge, fallback)
    val isa AbstractDict || return val
    haskey(val, e) && return val[e]
    key = (e.src, e.dst)
    haskey(val, key) && return val[key]
    rev = (e.dst, e.src)
    haskey(val, rev) && return val[rev]
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

# `curvature` resolves like any other per-edge style attribute (see
# `_resolve_edge`), just converted to Float32 once resolved.
function _resolve_curvature(val, e::CausalEdge)
    resolved = _resolve_edge(val, e, nothing)
    return resolved === nothing ? nothing : Float32(resolved)
end

# Look up an `edge_paths` override for `e` (same precedence as
# `_resolve_edge`), carried through the same unit-extent transform already
# applied to `positions` so it stays aligned with them.
function _resolve_edge_path(edge_paths, e::CausalEdge, cx1, cy1, scale1)
    edge_paths === nothing && return nothing
    raw = _resolve_edge(edge_paths, e, nothing)
    raw === nothing && return nothing
    return Point2f[_apply_unit_extent(Point2f(p[1], p[2]), cx1, cy1, scale1) for p in raw]
end

# A NamedTuple-valued recipe attribute (`layout_kwargs`) arrives here as a
# `Makie.Attributes` wrapping each field in its own Observable, rather than
# the plain NamedTuple that was assigned - unwrap it back to one.
_materialize_kwargs(nt::NamedTuple) = nt
_materialize_kwargs(a::Makie.Attributes) = NamedTuple(k => v[] for (k, v) in pairs(a))

# Resolve a per-node style attribute: either a scalar, or a Dict keyed by
# node name, with :default as a fallback.
function _resolve_node(val, node::Symbol, fallback)
    val isa AbstractDict || return val
    haskey(val, node) && return val[node]
    haskey(val, :default) && return val[:default]
    return fallback
end

# The Makie.plot/Makie.plot! recipe for a CausalGraph - see the Makie.plot
# docstring below for the full keyword reference.
Makie.@recipe(CausalGraphPlot, graph) do scene
    Makie.Attributes(
        layout = Makie.automatic,
        layout_kwargs = (;),
        labels = nothing,
        node_shape = CausalStructures._PLOT_NODE_SHAPE_DEFAULT,
        node_radius = nothing,
        node_padding = CausalStructures._PLOT_NODE_PADDING_DEFAULT,
        arrow_size = nothing,
        circle_size = nothing,
        node_color = CausalStructures._PLOT_NODE_COLOR_DEFAULT,
        node_strokecolor = CausalStructures._PLOT_NODE_STROKECOLOR_DEFAULT,
        node_strokewidth = CausalStructures._PLOT_NODE_STROKEWIDTH_DEFAULT,
        node_linestyle = CausalStructures._PLOT_NODE_LINESTYLE_DEFAULT,
        edge_color = CausalStructures._PLOT_EDGE_COLOR_DEFAULT,
        arrow_fill = CausalStructures._PLOT_EDGE_ARROW_FILL_DEFAULT,
        linewidth = CausalStructures._PLOT_LINEWIDTH_DEFAULT,
        curvature = CausalStructures._PLOT_CURVATURE_DEFAULT,
        edge_paths = nothing,
        label_color = CausalStructures._PLOT_LABEL_COLOR_DEFAULT,
        label_fontsize = CausalStructures._PLOT_LABEL_FONTSIZE_DEFAULT,
        label_font = CausalStructures._PLOT_LABEL_FONT_DEFAULT,
    )
end

# The graph's topology (node/edge count, each edge's src_end/dst_end) is
# fixed for this plot's lifetime, so the set of child subplots never changes;
# only their data does. Every redraw clears and recreates them wholesale
# (`empty!(plot.plots)`) rather than diffing a variable subplot structure.
#
# Node/label sizing reads the containing Axis's live pixel viewport, and the
# viewport itself is tracked as an `onany` input below, so a plain window
# resize with no attribute touched still re-solves node/label sizing to fit.
function Makie.plot!(plot::CausalGraphPlot)
    function update_plot(
        cg,
        layout,
        layout_kwargs,
        labels,
        node_shape,
        node_radius,
        node_padding,
        arrow_size,
        circle_size,
        node_color,
        node_strokecolor,
        node_strokewidth,
        node_linestyle,
        edge_color,
        arrow_fill,
        linewidth,
        curvature,
        edge_paths,
        label_color,
        label_fontsize,
        label_font,
        viewport,
    )
        empty!(plot.plots)

        node_names = cg.backend.nodes
        n = length(node_names)
        n == 0 && error("Cannot plot an empty graph (0 nodes).")

        resolved_layout =
            layout === Makie.automatic ? CausalStructures._default_layout_method(cg) :
            layout
        raw_positions, auto_edge_paths = _positions_and_auto_edge_paths(
            cg,
            resolved_layout,
            _materialize_kwargs(layout_kwargs),
        )
        # A user-supplied `edge_paths` only overrides the edges it names;
        # edges with an auto-computed path (e.g. from `layout = :sugiyama`)
        # keep it.
        edge_paths = if edge_paths === nothing
            auto_edge_paths
        elseif auto_edge_paths === nothing
            edge_paths
        else
            merge(auto_edge_paths, edge_paths)
        end
        cx1, cy1, scale1 = _unit_extent_params(raw_positions)
        positions = Point2f[_apply_unit_extent(p, cx1, cy1, scale1) for p in raw_positions]

        shapes = Symbol[Symbol(_resolve_node(node_shape, nd, :circle)) for nd in node_names]
        for (i, sh) in enumerate(shapes)
            sh in _NODE_SHAPES || error(
                "Unknown node_shape $(repr(sh)) for node $(repr(node_names[i])). " *
                "Available: " *
                join(map(repr, _NODE_SHAPES), ", ") *
                ".",
            )
        end

        node_labels = [
            labels === nothing ? string(nd) : _resolve_node(labels, nd, string(nd)) for
            nd in node_names
        ]

        # Text is fixed-pixel-sized regardless of zoom, so node sizes (data
        # units) are solved for the pixels-per-data-unit ratio the Axis's
        # real pixel area implies.
        avail_w, avail_h = Float32.(Makie.widths(viewport))

        xs = [p[1] for p in positions]
        ys = [p[2] for p in positions]
        bbox_w = max(maximum(xs) - minimum(xs), 1.0f-3)
        bbox_h = max(maximum(ys) - minimum(ys), 1.0f-3)

        half_w, half_h = if node_radius !== nothing
            r = Float32(node_radius)
            fill(r, n), fill(r, n)
        else
            pixel_sizes = [
                max.(
                    6.0f0,
                    _text_fit_pixel_size(
                        node_labels[i],
                        shapes[i],
                        _resolve_node(label_fontsize, node_names[i], 14.0f0),
                        _resolve_node(label_font, node_names[i], :regular),
                        node_padding,
                    ),
                ) for i = 1:n
            ]
            # Nodes are kept apart by their circumradius, whatever their shape.
            pixel_radii = Float32[
                _circumradius(
                    _NodeGeom(
                        Point2f(0, 0),
                        shapes[i],
                        pixel_sizes[i][1],
                        pixel_sizes[i][2],
                    ),
                ) for i = 1:n
            ]
            # px_per_unit that fits the bbox (plus a margin sized to the
            # largest label, in data units at that same ratio) inside the
            # available area. Solved in closed form:
            # margin = 1.3*maxpr/px, so
            # px*bbox + 2*1.3*maxpr = avail  =>  px = (avail - 2.6*maxpr)/bbox.
            maxpr = maximum(pixel_radii)
            px_fit_w = (avail_w - 2.6f0 * maxpr) / bbox_w
            px_fit_h = (avail_h - 2.6f0 * maxpr) / bbox_h
            px_per_unit = max(10.0f0, min(px_fit_w, px_fit_h))
            (
                Float32[p[1] / px_per_unit for p in pixel_sizes],
                Float32[p[2] / px_per_unit for p in pixel_sizes],
            )
        end

        geoms = [
            _NodeGeom(positions[i], shapes[i], half_w[i], half_h[i]) for
            i in eachindex(positions)
        ]
        radii = Float32[_circumradius(g) for g in geoms]

        # Arrowhead/circle-marker sizes are based on the typical (not
        # per-node) node size, so one long label doesn't skew them.
        r_typical = node_radius !== nothing ? Float32(node_radius) : Float32(sum(radii) / n)
        r_arrow = Float32(something(arrow_size, r_typical * 0.4f0))
        r_circle = Float32(something(circle_size, r_typical * 0.28f0))

        node_idx = Dict{Symbol,Int}(node_names[i] => i for i in eachindex(node_names))
        fan_slots = _edge_fan_slots(cg.edges)

        # Only feeds the arrowhead/circle-marker clearance gap in `_edge_path`
        # below - the Axis auto-scales its own data limits from the actual
        # geometry drawn here, so this doesn't need to match that exactly.
        margin = 1.3f0 * maximum(radii)
        px_per_data_unit =
            min(avail_w / (bbox_w + 2.0f0 * margin), avail_h / (bbox_h + 2.0f0 * margin))

        # Edges drawn first so nodes appear on top.
        for (i, e) in enumerate(cg.edges)
            src_idx = node_idx[e.src]
            dst_idx = node_idx[e.dst]
            obstacles = Tuple{Point2f,Float32}[
                (positions[j], radii[j]) for
                j in eachindex(positions) if j != src_idx && j != dst_idx
            ]

            resolved_color = _resolve_edge(edge_color, e, :black)
            _draw_edge!(
                plot,
                e,
                geoms[src_idx],
                geoms[dst_idx],
                r_arrow,
                r_circle,
                obstacles,
                fan_slots[i],
                _resolve_curvature(curvature, e),
                px_per_data_unit,
                _resolve_edge_path(edge_paths, e, cx1, cy1, scale1);
                color = resolved_color,
                fill = something(_resolve_edge(arrow_fill, e, nothing), resolved_color),
                linewidth = Float32(_resolve_edge(linewidth, e, 1.5f0)),
            )
        end

        for i in eachindex(node_names)
            nd = node_names[i]
            _draw_node!(
                plot,
                geoms[i];
                color = _resolve_node(node_color, nd, :white),
                strokecolor = _resolve_node(node_strokecolor, nd, :black),
                strokewidth = Float32(_resolve_node(node_strokewidth, nd, 2.0)),
                linestyle = _resolve_node(node_linestyle, nd, nothing),
            )
            Makie.text!(
                plot,
                positions[i][1],
                positions[i][2];
                text = node_labels[i],
                align = (:center, :center),
                color = _resolve_node(label_color, nd, :black),
                fontsize = Float32(_resolve_node(label_fontsize, nd, 14.0f0)),
                font = _resolve_node(label_font, nd, :regular),
            )
        end
        return
    end

    # Tracking the Axis's own pixel viewport (not just `plot`'s attributes)
    # as an `onany` input is what makes node/label sizing keep up with a live
    # window resize.
    viewport = Makie.viewport(Makie.parent_scene(plot))
    Makie.onany(
        update_plot,
        plot,
        plot.graph,
        plot.layout,
        plot.layout_kwargs,
        plot.labels,
        plot.node_shape,
        plot.node_radius,
        plot.node_padding,
        plot.arrow_size,
        plot.circle_size,
        plot.node_color,
        plot.node_strokecolor,
        plot.node_strokewidth,
        plot.node_linestyle,
        plot.edge_color,
        plot.arrow_fill,
        plot.linewidth,
        plot.curvature,
        plot.edge_paths,
        plot.label_color,
        plot.label_fontsize,
        plot.label_font,
        viewport;
        update = true,
    )
    return plot
end

Makie.plottype(::CausalGraph) = CausalGraphPlot

"""
    Makie.plot(cg; kwargs...) -> FigureAxisPlot
    Makie.plot!(ax, cg; kwargs...) -> CausalGraphPlot

Visualize a [`CausalGraph`](@ref) using Makie. Requires loading a Makie
backend (e.g. CairoMakie) before calling.

Every keyword below (except the figure-level ones noted last) is one of its
reactive attributes, so e.g. `plt.node_color[] = :red` restyles the existing
plot in place.

Keyword arguments: `layout`, `layout_kwargs`, `labels`, `node_shape`,
`node_radius`, `node_padding`, `arrow_size`, `circle_size`, `node_color`,
`node_strokecolor`, `node_strokewidth`, `node_linestyle`, `edge_color`,
`arrow_fill`, `linewidth`, `curvature`, `edge_paths`, `label_color`,
`label_fontsize`, `label_font` are shared by both `plot` and `plot!`. Style
keywords accept either a scalar (applied to everything) or a `Dict` for
per-node/per-edge overrides; a per-edge `Dict` may be keyed by a
`CausalEdge`, a `(src, dst)` tuple, a node name, an edge-type symbol, or
`:default`. `layout_kwargs` is a `NamedTuple` of extra keywords forwarded to
the chosen layout algorithm, e.g. `layout_kwargs = (; seed = 1)`.

`title`, `title_fontsize`, `title_color`, `title_gap`, `outer_margin`,
`fig_size`, `stretch_to_fig_size` only apply to `Makie.plot`.

`edge_paths` can be used to override an edge's drawn route directly: a
`Dict` (same keying as other per-edge overrides) from an edge to a vector
of waypoints running from its source node's position to its destination
node's position, in the same coordinates as `layout`.

See the [Plotting](@ref plotting-guide) page for the full keyword reference,
styling precedence rules, and examples.

## Examples

```julia
using CairoMakie

dag = DAG("A ---> X, A ---> Y, X ---> Y")

Makie.plot(dag; node_color = :lightblue, edge_color = :gray40)
Makie.plot(dag; edge_color = Dict((:A, :X) => :red, :default => :black))
Makie.plot(dag; edge_color = Dict(directed(:A, :X) => :red, :default => :black))
Makie.plot(dag; node_shape = Dict(:A => :square, :default => :circle))
Makie.plot(dag; node_shape = :rect, labels = Dict(:A => "Age at\\nbaseline"))
Makie.plot(dag; curvature = Dict((:A, :Y) => 0.3))
Makie.plot(dag; title = "My DAG", layout = :spring, layout_kwargs = (; seed = 1))

# Compose two graphs into one figure:
fig = Figure()
Makie.plot!(Axis(fig[1, 1]; aspect = DataAspect()), dag)
Makie.plot!(Axis(fig[1, 2]; aspect = DataAspect()), dag; node_color = :salmon)
Makie.hidedecorations!.(fig.content)
Makie.hidespines!.(fig.content)
```
"""
function Makie.plot(
    cg::CausalGraph;
    layout::Union{Symbol,AbstractVector,AbstractDict,Makie.Automatic} = Makie.automatic,
    layout_kwargs::NamedTuple = (;),
    edge_paths::Union{AbstractDict,Nothing} = nothing,
    title::Union{AbstractString,Nothing} = nothing,
    title_fontsize::Union{Real,Nothing} = CausalStructures._PLOT_TITLE_FONTSIZE_DEFAULT,
    title_color = CausalStructures._PLOT_TITLE_COLOR_DEFAULT,
    title_gap::Real = 4.0,
    outer_margin::Real = CausalStructures._PLOT_OUTER_MARGIN_DEFAULT,
    fig_size::NTuple{2,Real} = CausalStructures._PLOT_FIG_SIZE_DEFAULT,
    stretch_to_fig_size::Bool = CausalStructures._PLOT_STRETCH_TO_FIG_SIZE_DEFAULT,
    kwargs...,
)
    isempty(cg.backend.nodes) && error("Cannot plot an empty graph (0 nodes).")

    if stretch_to_fig_size
        # Precompute final, stretched positions and hand them to the recipe
        # as explicit positions, rather than letting `plot!` invoke the
        # (possibly randomized) layout algorithm a second time.
        resolved_layout =
            layout === Makie.automatic ? CausalStructures._default_layout_method(cg) :
            layout
        raw_positions, auto_edge_paths =
            _positions_and_auto_edge_paths(cg, resolved_layout, layout_kwargs)
        cx1, cy1, scale1 = _unit_extent_params(raw_positions)
        positions = Point2f[_apply_unit_extent(p, cx1, cy1, scale1) for p in raw_positions]

        fig_height_budget = Float32(fig_size[2]) - (title !== nothing ? 40.0f0 : 0.0f0)
        avail_w = Float32(fig_size[1]) - 2.0f0 * Float32(outer_margin)
        avail_h = fig_height_budget - 2.0f0 * Float32(outer_margin)
        stretch_params = _aspect_stretch_params(positions, avail_w / avail_h)
        positions = Point2f[_apply_aspect_stretch(p, stretch_params...) for p in positions]

        if auto_edge_paths !== nothing
            stretched_auto_edge_paths = Dict(
                key => Point2f[
                    _apply_aspect_stretch(
                        _apply_unit_extent(Point2f(p[1], p[2]), cx1, cy1, scale1),
                        stretch_params...,
                    ) for p in path
                ] for (key, path) in auto_edge_paths
            )
            edge_paths =
                edge_paths === nothing ? stretched_auto_edge_paths :
                merge(stretched_auto_edge_paths, edge_paths)
        end

        layout = Dict{Symbol,NTuple{2,Float64}}(
            nd => (Float64(p[1]), Float64(p[2])) for
            (nd, p) in zip(cg.backend.nodes, positions)
        )
    end

    fig = Makie.Figure(;
        size = (round(Int, fig_size[1]), round(Int, fig_size[2])),
        figure_padding = outer_margin,
    )
    ax = if title === nothing
        Makie.Axis(fig[1, 1]; aspect = Makie.DataAspect())
    else
        title_kwargs = Dict{Symbol,Any}(:titlegap => Float32(title_gap))
        title_fontsize !== nothing &&
            (title_kwargs[:titlesize] = Float32(title_fontsize))
        title_color !== nothing && (title_kwargs[:titlecolor] = title_color)
        Makie.Axis(fig[1, 1]; aspect = Makie.DataAspect(), title = title, title_kwargs...)
    end
    Makie.hidedecorations!(ax)
    Makie.hidespines!(ax)

    plt = Makie.plot!(ax, cg; layout, layout_kwargs, edge_paths, kwargs...)
    return Makie.FigureAxisPlot(fig, ax, plt)
end
