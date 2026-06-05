# Drawing primitives and the caugi_plot implementation.
#
# Endpoint semantics per CausalEdge:
#   src_end / dst_end : Tail | Arrow | Circle
#
# Edge type → endpoint marks:
#   -->   Tail  → Arrow   : line + arrowhead at dst
#   ---   Tail  → Tail    : plain line
#   <->   Arrow → Arrow   : line + arrowheads at both ends
#   o->   Circle→ Arrow   : open circle at src + arrowhead at dst
#   --o   Tail  → Circle  : line + open circle at dst
#   o-o   Circle→ Circle  : open circles at both ends

const _Tail = CausalGraphInterface.Tail
const _Arrow = CausalGraphInterface.Arrow
const _Circle = CausalGraphInterface.Circle

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
)
    diff = p_dst - p_src
    len = _norm2(diff)
    len < 1.0f-6 && return
    dir = Point2f(diff[1] / len, diff[2] / len)

    # Points on the node boundaries along the edge direction.
    src_bnd = p_src + r_node * dir
    dst_bnd = p_dst - r_node * dir

    has_arrow_src = e.src_end === _Arrow
    has_arrow_dst = e.dst_end === _Arrow
    has_circle_src = e.src_end === _Circle
    has_circle_dst = e.dst_end === _Circle

    # Pull the line ends back to leave room for arrowhead triangles.
    line_start = has_arrow_src ? src_bnd + r_arrow * dir : src_bnd
    line_end = has_arrow_dst ? dst_bnd - r_arrow * dir : dst_bnd

    if _norm2(line_end - line_start) > 1.0f-6
        Makie.lines!(ax, [line_start, line_end]; color = color, linewidth = linewidth)
    end

    has_arrow_dst && _draw_arrowhead!(ax, dst_bnd, dir, r_arrow; color = color)
    has_arrow_src &&
        _draw_arrowhead!(ax, src_bnd, Point2f(-dir[1], -dir[2]), r_arrow; color = color)

    # Open circles: centered one radius out from the node boundary so the
    # inner edge of the circle sits flush against the node.
    if has_circle_src
        _draw_filled_circle!(ax, src_bnd + r_circle * dir, r_circle; strokecolor = color)
    end
    if has_circle_dst
        _draw_filled_circle!(ax, dst_bnd - r_circle * dir, r_circle; strokecolor = color)
    end
end

function CausalGraphInterface.caugi_plot(
    g::CausalGraph;
    node_radius::Union{Real,Nothing} = nothing,
    arrow_size::Union{Real,Nothing} = nothing,
    circle_size::Union{Real,Nothing} = nothing,
    node_color = :white,
    node_strokecolor = :black,
    edge_color = :black,
)
    n = length(g.backend.nodes)
    n == 0 && error("Cannot plot an empty graph (0 nodes).")

    positions = _circle_layout(n)

    r_node = Float32(something(node_radius, max(0.12, 0.4 * sin(π / max(n, 2)))))
    r_arrow = Float32(something(arrow_size, r_node * 0.4f0))
    r_circle = Float32(something(circle_size, r_node * 0.28f0))

    node_pos = Dict{Symbol,Point2f}(
        g.backend.nodes[i] => positions[i] for i in eachindex(g.backend.nodes)
    )

    fig = Makie.Figure()
    ax = Makie.Axis(fig[1, 1]; aspect = Makie.DataAspect())
    Makie.hidedecorations!(ax)
    Makie.hidespines!(ax)

    # Edges drawn first so nodes appear on top.
    for e in g.edges
        _draw_edge!(
            ax,
            e,
            node_pos[e.src],
            node_pos[e.dst],
            r_node,
            r_arrow,
            r_circle;
            color = edge_color,
        )
    end

    # Node circles and labels.
    for i in eachindex(g.backend.nodes)
        _draw_filled_circle!(
            ax,
            positions[i],
            r_node;
            color = node_color,
            strokecolor = node_strokecolor,
            strokewidth = 2.0f0,
        )
        Makie.text!(
            ax,
            positions[i][1],
            positions[i][2];
            text = string(g.backend.nodes[i]),
            align = (:center, :center),
            fontsize = 14,
        )
    end

    return fig
end
