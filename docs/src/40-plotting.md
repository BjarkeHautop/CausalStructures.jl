# [Plotting](@id plotting-guide)

To use plotting, first load a [Makie](https://docs.makie.org/stable/) backend. For node
placement, you can use [NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl),
[Sugiyama.jl](https://github.com/BjarkeHautop/Sugiyama.jl), or provide your own layout.
Below we use CairoMakie:

```@example plot
using CausalStructures
using CairoMakie
using NetworkLayout
using Sugiyama
```

!!! note "General-purpose by design"
    There are many conventions for drawing causal graphs. For example, you might box
    conditioned variables, dash latent variables, draw `<->` as a dashed arc, or use
    different colors for exposures and outcomes.

    [`plot`](@ref) does not impose any of these conventions by default. Instead, you can
    use its styling options, Makie themes, and layouts to choose the conventions that make
    sense for your application[^1].

    [^1]: Makie themes for common conventions are also welcome as PRs!

## Basic usage

You can pass any [`CausalGraph`](@ref) to [`plot`](@ref), and all edge marks are supported:

```@example plot
unknown = UNKNOWN("A <-> B o-> C o-- A")
plot(unknown)
```

As an example, here is the DAG from Figure 6.5 of
[peters2017elements](@citet):

```@example plot
dag = DAG(
    "C --> X, A --> X + K, X --> F + D, K --> Y, D --> Y + G, Y --> H"
)
plot(dag)
```

`plot` returns a `FigureAxisPlot`, so `fig, ax, plt = plot(dag)` gives you the `Figure`,
`Axis`, and plot object. The plot is reactive, so you can update it after creating it:

```@example plot
fig, ax, plt = plot(dag)
plt.node_color[] = :salmon
fig
```

There are four main areas of styling:

- **[Layout](@ref plot-layouts)**: where nodes are placed
- **[Styling nodes](@ref)**: node appearance
- **[Styling edges](@ref)**: edge appearance
- **[Labels and titles](@ref)**: text and annotations

If you want to set defaults for an entire project, you can use a
[Makie theme](https://docs.makie.org/stable/explanations/theming/themes):

```julia
Makie.set_theme!(CausalGraphPlot = (node_color = :lightblue, linewidth = 2))
```

`edge_color` and `edge_label_color` also pick up the active theme's `linecolor` and
`textcolor`. `node_color` and `node_label_color` stay fixed, so set them together if you
want a dark node with a light label, e.g.
`Makie.set_theme!(CausalGraphPlot = (node_color = :gray10, node_label_color = :white))`.

## [Layout](@id plot-layouts)

The `layout` keyword controls where the nodes are placed. For DAGs, it defaults to
`:sugiyama` if Sugiyama.jl is loaded, and to `:stress` otherwise.

```@example plot
plot(dag; layout = :spring)
```

You can use these shorthand names for the most common layouts. All except `:sugiyama` come
from [NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl), while `:sugiyama`
comes from [Sugiyama.jl](https://github.com/BjarkeHautop/Sugiyama.jl):

| `layout`      | Algorithm                            |
| ------------- | ------------------------------------- |
| `:spring`     | Fruchterman-Reingold force-directed   |
| `:stress`     | Stress majorization                   |
| `:sfdp`       | Scalable Force-Directed Placement     |
| `:spectral`   | Spectral layout                       |
| `:shell`      | Concentric shells                     |
| `:squaregrid` | Square grid                           |
| `:sugiyama`   | Sugiyama layout (DAGs only)           |

If you want to place the nodes yourself, you can pass explicit positions instead of a
`Symbol`. You can either use a `Dict` of `(x, y)` pairs keyed by node name, or a `Vector`
in the order returned by `nodes(cg)`:

```@example plot
plot(dag; layout = Dict(
    :A => (0, 1), :C => (0, -1), :K => (1, 1), :X => (1, -1),
    :D => (2, -1), :F => (2, -2), :Y => (3, 0), :G => (3, 1), :H => (4, 0),
))
```

!!! tip "Tweaking a layout by hand"
    You can compute a starting layout using [`layout`](@ref), and then
    manually adjust a few nodes:

    ```@example plot
    positions = layout(dag, :spring)
    positions[:A] = (0.0, 2.0)
    plot(dag; layout = positions)
    ```

!!! tip "Sugiyama positions without Sugiyama routing"
    Sugiyama.jl implements its own routing using dummy nodes. If you prefer the automatic
    Bezier-curve routing used by `plot`, you can compute the Sugiyama positions with
    [`layout`](@ref) and pass those instead:

    ```@example plot
    dag_layered = DAG("A --> X, A --> B, X --> Y, B --> Y, A --> Y")
    plot(dag_layered; layout = layout(dag_layered, :sugiyama))
    ```

## Styling nodes

You can set each node style either with a single value for all nodes or with a
`Dict{Symbol, <value>}` for per-node settings. Use `:default` in the dictionary as a
fallback.

| Keyword             | Default                             | Controls                        |
| ------------------- | ------------------------------------ | -------------------------------- |
| `node_color`        | `:white`                             | fill color                      |
| `node_strokecolor`  | `:black`                             | border color                    |
| `node_strokewidth`  | `2.0`                                | border line width               |
| `node_linestyle`    | `nothing` (solid)                    | border line style               |
| `node_shape`        | `:circle`                             | node outline shape              |
| `node_radius`       | `nothing` (text-fit, per node)       | size of each node               |
| `node_padding`      | `10.0`                                | clearance around each label when `node_radius` is `nothing` |

Combine color, border, and shape to highlight a node:

```@example plot
plot(dag;
    node_color = Dict(:A => :salmon, :default => :lightblue),
    node_strokecolor = Dict(:A => :crimson, :default => :navy),
    node_shape = Dict(:K => :square, :default => :circle),
)
```

You can set `node_shape` to `:circle` (the default), `:square`, `:ellipse`, or `:rect`. The
latter two are mainly useful when you want to fit an oblong label. You can also use
`node_linestyle` to style the border, for example to mark a latent variable:

```@example plot
plot(dag;
    node_linestyle = Dict(:X => :dash),
    node_strokecolor = Dict(:X => :gray50, :default => :black),
)
```

If you only want to draw the node names, you can make the fill transparent and remove the
border. Edges still stop at the (now invisible) node boundary, so you can use `:rect` with a
smaller `node_padding` to bring the arrowheads closer to the text:

```@example plot
plot(dag;
    node_color = :transparent,
    node_strokewidth = 0,
    node_shape = :rect,
    node_padding = 4,
)
```

### Text-fit node sizing

By default (`node_radius = nothing`), nodes are sized to fit their labels:

```@example plot
longlabels = DAG("Exposure --> Mediator --> Y_outcome")
plot(longlabels; node_shape = Dict(:Exposure => :ellipse))
```

If you want to control the size yourself, you can set `node_radius` explicitly:

```@example plot
plot(dag; node_radius = 0.06)
```

## Styling edges

You can set each edge style with a single value or with a `Dict` for more specific
overrides. The keys are checked in this order:

 1. a `CausalEdge` for one exact edge, e.g. `bidirected(:X, :Y)`
 2. a `(src, dst)` tuple for the node pair, in either order
 3. an edge-type symbol (`:directed`, `:undirected`, `:bidirected`, `:partially_directed`, `:partially_undirected`, `:partial`)
 4. `:default` as a fallback

| Keyword          | Default   | Controls               |
| ---------------- | --------- | ----------------------- |
| `edge_color`     | `:black`  | line / marker color     |
| `arrow_fill`     | `nothing` | arrowhead fill color    |
| `linewidth`      | `1.5`     | line width              |
| `edge_linestyle` | `nothing` (solid) | line style      |
| `edge_gap`       | `0.0`     | gap (pixels) at edge ends |
| `curvature`      | `nothing` | how far the edge bows   |
| `edge_paths`     | `nothing` | explicit waypoints for an edge's route |
| `arrow_size`     | `nothing` (`0.4 ×` average node radius) | length of arrowhead triangles |
| `circle_size`    | `nothing` (`0.28 ×` average node radius) | radius of open-circle (`o`) endpoints |

Let's style some edges by type:

```@example plot
admg = ADMG("X --> Y, X <-> Z, Z --> Y")

plot(admg;
    edge_color = Dict(:directed => :steelblue, :bidirected => :crimson),
    linewidth  = Dict(:bidirected => 2.5, :default => 1.5),
)
```

`arrow_fill` controls the arrowhead's fill color. By default (`nothing`), it uses the edge's
resolved `edge_color`, so arrowheads are solid. If you want hollow, outline-only
arrowheads, pass a transparent color:

```@example plot
plot(dag; arrow_fill = :transparent)
```

`edge_linestyle` styles the edge line itself. For example, you can use it to dash `<->` edges:

```@example plot
plot(admg; edge_linestyle = Dict(:bidirected => :dash))
```

If you prefer some space between each end of an edge and the node border, you can set
`edge_gap`:

```@example plot
plot(dag; edge_gap = 4)
```

### Targeting specific edges

If you want to change something for a specific edge, you can use a tuple key:

```@example plot
plot(dag;
    edge_color = Dict((:A, :X) => :red, :default => :black),
)
```

A tuple key uses an unordered node pair. This means that if an `ADMG` has both `X --> Y`
and `X <-> Y`, the tuple key applies to both edges. If you need to distinguish them, use a
[`CausalEdge`](@ref) instead:

```@example plot
shared = ADMG("X --> Y, X <-> Y")

plot(shared;
    edge_color = Dict(bidirected(:X, :Y) => :crimson, :default => :steelblue),
)
```

!!! tip "Symmetric edges"
    For symmetric edges, the order does not matter, so `bidirected(:Y, :X)` is the same key
    as `bidirected(:X, :Y)`.

Notice that the two edges between `X` and `Y` are automatically curved apart, so they
don't overlap.

### Curvature and automatic routing

`curvature` bows an edge into an arc instead of drawing it straight. Positive values bow
the edge to the left when travelling from `src` to `dst`, while negative values bow it to
the right.

```@example plot
plot(admg; curvature = Dict(:bidirected => -0.3))
```

If a straight `src --> dst` edge would pass too close to a non-incident node, `plot`
automatically bends it around that node with a Bezier curve. Edges with nothing in the way
are always drawn straight.

```@example plot
detour = DAG("A --> X + Y, X --> Y")

plot(detour; layout = [(0, 0), (1, 0), (2, 0)])
```

If you want to disable this automatic routing for a particular edge, you can set its
`curvature` to `0.0`:

```@example plot
plot(detour;
    layout = [(0, 0), (1, 0), (2, 0)],
    curvature = Dict(directed(:A, :Y) => 0.0),
)
```

### Explicit edge paths

Edges are normally drawn as straight lines unless automatic routing is needed. If you want
to control the path yourself, you can use `edge_paths` and provide intermediate points for
the edge. For example, the edge `K --> Y` below is drawn through the point `(0.5, -0.25)`:

```@example plot
positions = layout(dag, :spring)

plot(dag;
    layout = positions,
    edge_paths = Dict((:K, :Y) => [positions[:K], (0.5, -0.25), positions[:Y]]),
)
```

## Labels and titles

### Labels

You can set each label style with a single value or with a `Dict{Symbol, <value>}` keyed by
node name. Use `:default` as a fallback, just like with node styling.

| Keyword               | Default    | Controls                |
| --------------------- | ---------- | ------------------------ |
| `node_labels`         | `nothing`  | text drawn in each node   |
| `node_label_color`    | `:black`   | node label text color     |
| `node_label_fontsize` | `14.0`     | node label font size      |
| `node_label_font`     | `:regular` | node label font           |

By default, each node is labelled with its own name. If you want different labels, you can
set them with `node_labels`. Node sizing takes multi-line labels into account, so the nodes
grow to fit:

```@example plot
plot(DAG("A0 --> L1 --> A1 --> Y, A0 --> Y + A1");
    node_labels = Dict(
        :A0 => "Treatment\nat baseline",
        :L1 => "Confounder\nat time 1",
        :A1 => "Treatment\nat time 1",
    ),
)
```

You can use `node_label_color` and `node_label_fontsize` to style the label text:

```@example plot
plot(dag;
    node_label_color = Dict(:A => :crimson, :default => :black),
    node_label_fontsize = 18,
)
```

### Edge labels

You can set each edge label style with a single value or with a `Dict` for per-edge
overrides, using the same keys as for [edge styling](@ref "Styling edges").

| Keyword                | Default    | Controls                                              |
| ----------------------- | ---------- | ------------------------------------------------------ |
| `edge_labels`          | `nothing`  | text drawn along each edge                             |
| `edge_label_color`     | `:black`   | edge label text color                                  |
| `edge_label_fontsize`  | `12.0`     | edge label font size                                   |
| `edge_label_font`      | `:regular` | edge label font                                        |
| `edge_label_shift`     | `0.5`      | position along the edge, 0 (source) to 1 (destination) |
| `edge_label_distance`  | `nothing`  | perpendicular gap (pixels) from the edge; `nothing` scales with `edge_label_fontsize` |
| `edge_label_rotation`  | `nothing`  | text angle in radians; `nothing` follows the edge's own angle |

Let's add a label to the edge `K --> Y`:

```@example plot
plot(dag; edge_labels = Dict(directed(:K, :Y) => "hello"))
```

By default, the label follows the edge's angle. You can use `edge_label_shift` and
`edge_label_distance` to move it along or away from the edge:

```@example plot
plot(dag;
    edge_labels = Dict(directed(:K, :Y) => "hi"),
    edge_label_shift = 0.75,
    edge_label_distance = 12,
)
```

If an edge is steep or curved, following its angle can make the label hard to read. You
can use `edge_label_rotation` to give it a fixed angle instead:

```@example plot
plot(dag;
    edge_labels = Dict(directed(:A, :X) => "steep"),
    edge_label_rotation = 0.0,
)
```

### Titles

| Keyword          | Default   | Controls                                                  |
| ---------------- | --------- | ---------------------------------------------------------- |
| `title`          | `nothing` | plot title; `nothing` means no title                       |
| `title_fontsize` | `nothing` | title font size; `nothing` uses the Makie theme's default  |
| `title_color`    | `nothing` | title color; `nothing` uses the Makie theme's default      |
| `title_gap`      | `4.0`     | gap (points) between the title and the graph               |

If you want to add a title, set `title`:

```@example plot
plot(dag; title = "My DAG", title_fontsize = 20, title_color = :navy)
```

## Figure size and margins

| Keyword               | Default       | Controls                                          |
| ---------------------- | ------------- | -------------------------------------------------- |
| `outer_margin`        | `16`          | padding (pixels) around the whole figure           |
| `fig_size`            | `(600, 450)`  | figure size in pixels (width, height)              |
| `stretch_to_fig_size` | `false`       | stretch the layout to fill an uneven `fig_size`    |

Let's make the figure a bit larger:

```@example plot
plot(dag; fig_size = (800, 600))
```

!!! tip "Large graphs need a bigger `fig_size`"
    The default `(600, 450)` works well for small examples. As your graph gets larger,
    labels and edges can become cramped or overlap. Increase `fig_size` (and, if needed,
    `node_radius` or `node_label_fontsize`) to keep larger graphs readable.

!!! tip "Uneven `fig_size` and `stretch_to_fig_size`"
    By default, node positions keep the layout's own aspect ratio. Depending on your
    `fig_size`, this can leave a lot of empty space around the graph. If you want the
    layout to fill the figure instead, set `stretch_to_fig_size = true`.

## Composing into an existing figure

So far we've only used `plot`, which builds its own `Figure` and `Axis` for you. If you
already have an `Axis` (for example, as one panel of a larger figure), you can use
`plot!(ax, cg; kwargs...)` to draw the graph there instead. It accepts the same keywords as
`plot`, except for `outer_margin`, `title_gap`, `fig_size`, and `stretch_to_fig_size`,
since those control the figure that `plot` creates.

Let's use this to draw the DAG and the ADMG side by side in one figure:

```@example plot
fig = Figure(size = (900, 400))
plot!(Axis(fig[1, 1]; aspect = DataAspect()), dag)
plot!(Axis(fig[1, 2]; aspect = DataAspect()), admg; node_color = :salmon)
Makie.hidedecorations!.(fig.content)
Makie.hidespines!.(fig.content)
fig
```

## Combining options

Here we combine some of the styling options above to plot a PAG:

```@example plot
pag = PAG(
    "C o-> X, D --> G + Y, X --> D + F, Y --> H, K o-> X, K --> Y"
)

plot(
    pag;
    layout           = :spring,
    node_color       = Dict(:X => :skyblue, :Y => :gold, :default => :whitesmoke),
    node_strokecolor = Dict(:X => :royalblue, :Y => :darkorange, :default => :slategray),
    node_shape       = Dict(:K => :square, :default => :circle),
    node_linestyle   = Dict(:K => :dash, :default => nothing),
    edge_color       = Dict(:partially_directed => :royalblue, :default => :darkslategray),
    edge_linestyle   = Dict(:partially_directed => :dash),
    curvature        = Dict((:K, :Y) => 0.3),
    edge_labels      = Dict((:K, :X) => "cool"),
    node_label_color = Dict(:X => :navy, :Y => :saddlebrown, :default => :black),
    title            = "A cool PAG",
    title_fontsize   = 18,
    title_color      = :navy,
    fig_size         = (700, 500),
)
```
