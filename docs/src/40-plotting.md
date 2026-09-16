# [Plotting](@id plotting-guide)

Plotting requires loading a [Makie](https://docs.makie.org/stable/) backend before use.
Node placement requires [NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl)
or [Sugiyama.jl](https://github.com/BjarkeHautop/Sugiyama.jl) (or bring your own layout).
Below we use CairoMakie:

```@example plot
using CausalStructures
using CairoMakie
using NetworkLayout
using Sugiyama
```

!!! note "General-purpose by design"
    `plot` deliberately imposes no conventions of its own. There are many conventions
    in the literature, such as boxing conditioned variables, dashing latent variables,
    representing `<->` as an arc, or colouring exposures and outcomes. These conventions
    also sometimes disagree with one another. Rather than imposing a particular convention,
    we provide the capabilities and leave these choices to the caller. Downstream packages
    are encouraged to build an opinionated layer on top.

## Basic usage

Pass any `CausalGraph` to `plot`. Every edge mark is supported natively:

```@example plot
unknown = UNKNOWN("A <-> B o-> C o-- A")
plot(unknown)
```

Let us plot the DAG from Figure 6.5 of
[peters2017elements](@citet):

```@example plot
dag = DAG(
    "C --> X, A --> X + K, X --> F + D, K --> Y, D --> Y + G, Y --> H"
)
plot(dag)
```

`plot` returns a `FigureAxisPlot`, so `fig, ax, plt = plot(dag)` gives you back
the `Figure`, its `Axis`, and the plot itself - and `plt` is reactive:

```@example plot
fig, ax, plt = plot(dag)
plt.node_color[] = :salmon
fig
```

Styling breaks down into four areas, covered below:

- **[Layout](@ref plot-layouts)** — where nodes are placed
- **[Styling nodes](@ref)** — node appearance
- **[Styling edges](@ref)** — edge appearance
- **[Labels and titles](@ref)** — text and annotations

For a project-wide default you can use a
[Makie theme](https://docs.makie.org/stable/explanations/theming/themes):

```julia
Makie.set_theme!(CausalGraphPlot = (node_color = :lightblue, linewidth = 2))
```

`edge_color`/`edge_label_color` also pick up the active theme's
`linecolor`/`textcolor`; `node_color`/`node_label_color` stay fixed and should be
set together if you want a dark node/label pairing, e.g.
`Makie.set_theme!(CausalGraphPlot = (node_color = :gray10, node_label_color = :white))`.

## [Layout](@id plot-layouts)

The `layout` keyword controls node placement and defaults to `:sugiyama:` for a DAG if Sugiyama.jl is loaded, else `:stress`.

```@example plot
plot(dag; layout = :spring)
```

We provide these short-hand names for convenience. All except `:sugiyama` come from [NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl), while `:sugiyama` comes from [Sugiyama.jl](https://github.com/BjarkeHautop/Sugiyama.jl):

| `layout`      | Algorithm                            |
| ------------- | ------------------------------------- |
| `:spring`     | Fruchterman-Reingold force-directed   |
| `:stress`     | Stress majorization                   |
| `:sfdp`       | Scalable Force-Directed Placement     |
| `:spectral`   | Spectral layout                       |
| `:shell`      | Concentric shells                     |
| `:squaregrid` | Square grid                           |
| `:sugiyama`   | Sugiyama layout (DAGs only)           |

`layout` also accepts explicit positions instead of a `Symbol`: either a
`Dict` of `(x, y)` pairs keyed by node name, or a `Vector` of them in the order returned by `nodes(cg)`:

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
    Sugiyama.jl implements it's own routing via dummy nodes. If you
    prefer the automatic routing with Bezier curves, you can
    pass `layout = layout(dag_layered, :sugiyama)` in `plot`:

    ```@example plot
    dag_layered = DAG("A --> X, A --> B, X --> Y, B --> Y, A --> Y")
    plot(dag_layered; layout = layout(dag_layered, :sugiyama))
    ```

## Styling nodes

Each node style argument accepts either a scalar (applied to all nodes) or a `Dict{Symbol, <value>}` keyed by node name, with `:default` as a fallback.

| Keyword             | Default                             | Controls                        |
| ------------------- | ------------------------------------ | -------------------------------- |
| `node_color`        | `:white`                             | fill color                      |
| `node_strokecolor`  | `:black`                             | border color                    |
| `node_strokewidth`  | `2.0`                                | border line width               |
| `node_linestyle`    | `nothing` (solid)                    | border line style               |
| `node_shape`        | `:circle`                             | node outline shape              |
| `node_radius`       | `nothing` (text-fit, per node)       | size of each node               |
| `node_padding`      | `10.0`                                | clearance kept around each node's label when `node_radius` is `nothing` |
| `arrow_size`        | `0.4 ×` node-count-based reference   | length of arrowhead triangles   |
| `circle_size`       | `0.28 ×` node-count-based reference  | radius of open-circle endpoints |

Combine color, border, and shape to highlight a node:

```@example plot
plot(dag;
    node_color = Dict(:A => :salmon, :default => :lightblue),
    node_strokecolor = Dict(:A => :crimson, :default => :navy),
    node_shape = Dict(:K => :square, :default => :circle),
)
```

`node_shape` is one of `:circle` (the default), `:square`, `:ellipse`, or `:rect`; the
latter two mainly exist to fit an oblong label. `node_linestyle` styles the border, e.g.
to mark a latent variable:

```@example plot
plot(dag;
    node_linestyle = Dict(:X => :dash),
    node_strokecolor = Dict(:X => :gray50, :default => :black),
)
```

### Text-fit node sizing

By default (`node_radius = nothing`), each node is sized to fit its
own label:

```@example plot
longlabels = DAG("Exposure --> Mediator --> Y_outcome")
plot(longlabels; node_shape = Dict(:Exposure => :ellipse))
```

Alternatively, you can pass `node_radius` explicitly to control the size yourself:

```@example plot
plot(dag; node_radius = 0.06)
```

## Styling edges

Each edge style argument accepts either a scalar or a `Dict` keyed by (and follows this precedence):

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
| `curvature`      | `nothing` | how far the edge bows   |

Let's style some edges by type:

```@example plot
admg = ADMG("X --> Y, X <-> Z, Z --> Y")

plot(admg;
    edge_color = Dict(:directed => :steelblue, :bidirected => :crimson),
    linewidth  = Dict(:bidirected => 2.5, :default => 1.5),
)
```

`arrow_fill` is the arrowhead's fill color; `nothing` (the default) matches
the edge's own resolved `edge_color`, so arrowheads render solid. Pass a
transparent color for a hollow, outline-only arrowhead:

```@example plot
plot(dag; arrow_fill = :transparent)
```

`edge_linestyle` styles the line itself, e.g. to dash `<->` edges:

```@example plot
plot(admg; edge_linestyle = Dict(:bidirected => :dash))
```

### Targeting specific edges

A tuple key can be used to change something for a specific edge:

```@example plot
plot(dag;
    edge_color = Dict((:A, :X) => :red, :default => :black),
)
```

A tuple key uses an unordered node pair. However, an `ADMG`
may carry both `X --> Y` and `X <-> Y`, and a tuple key would then
apply to both of them. To distinguish them a [`CausalEdge`](@ref) can be used instead:

```@example plot
shared = ADMG("X --> Y, X <-> Y")

plot(shared;
    edge_color = Dict(bidirected(:X, :Y) => :crimson, :default => :steelblue),
)
```

!!! tip "Symmetric edges"
    Symmetric edges are stored in a canonical order, so `bidirected(:Y, :X)` is the same key as `bidirected(:X, :Y)`.

Notice the automatic routing of the edges above! See more about it below.

### Curvature and automatic routing

`curvature` bows an edge into an arc instead of drawing it straight. Positive values bow
to the left as seen travelling from `src` to `dst`, negative to the right.

```@example plot
plot(admg; curvature = Dict(:bidirected => -0.3))
```

An edge whose straight `src --> dst` line would pass too close to a
non-incident node is automatically bent around it as a Bezier curve, rather
than being drawn straight through it. Edges with nothing in their way are
always drawn straight.

```@example plot
detour = DAG("A --> X + Y, X --> Y")

plot(detour; layout = [(0, 0), (1, 0), (2, 0)])
```

`curvature` can also be used to disable this behavior:

```@example plot
plot(detour;
    layout = [(0, 0), (1, 0), (2, 0)],
    curvature = Dict(directed(:A, :Y) => 0.0),
)
```

### Explicit edge paths

Normally, edges are drawn as straight lines, except when automatic curvature is needed. You can override the edge path explicitly with `edge_paths` by providing intermediate points for an edge. For example, the edge `K --> Y` below is drawn through the point `(0.5, -0.25)`:

```@example plot
positions = layout(dag, :spring)

plot(dag;
    layout = positions,
    edge_paths = Dict((:K, :Y) => [positions[:K], (0.5, -0.25), positions[:Y]]),
)
```

## Labels and titles

### Labels

Each label style argument accepts either a scalar or a `Dict{Symbol, <value>}` keyed by node name,
with `:default` as a fallback (same resolution rules as node styling).

| Keyword               | Default    | Controls                |
| --------------------- | ---------- | ------------------------ |
| `node_labels`         | `nothing`  | text drawn in each node   |
| `node_label_color`    | `:black`   | node label text color     |
| `node_label_fontsize` | `14.0`     | node label font size      |
| `node_label_font`     | `:regular` | node label font           |

By default each node is labelled with its own name. `node_labels` can be
used to overwrite this; node sizing accounts for multi-line labels, so the nodes grow to fit:

```@example plot
plot(DAG("A0 --> L1 --> A1 --> Y, A0 --> Y + A1");
    node_labels = Dict(
        :A0 => "Treatment\nat baseline",
        :L1 => "Confounder\nat time 1",
        :A1 => "Treatment\nat time 1",
    ),
)
```

`node_label_color` and `node_label_fontsize` style the label text itself:

```@example plot
plot(dag;
    node_label_color = Dict(:A => :crimson, :default => :black),
    node_label_fontsize = 18,
)
```

### Edge labels

Each edge label style argument accepts either a scalar or a `Dict` for
per-edge overrides, using the same keying rules as other edge styling (a
`CausalEdge`, a `(src, dst)` tuple, an edge-type symbol, or `:default`).

| Keyword                | Default    | Controls                                              |
| ----------------------- | ---------- | ------------------------------------------------------ |
| `edge_labels`          | `nothing`  | text drawn along each edge                             |
| `edge_label_color`     | `:black`   | edge label text color                                  |
| `edge_label_fontsize`  | `12.0`     | edge label font size                                   |
| `edge_label_font`      | `:regular` | edge label font                                        |
| `edge_label_shift`     | `0.5`      | position along the edge, 0 (source) to 1 (destination) |
| `edge_label_distance`  | `nothing`  | perpendicular gap (pixels) from the edge; `nothing` scales with `edge_label_fontsize` |
| `edge_label_rotation`  | `nothing`  | text angle in radians; `nothing` follows the edge's own angle |

```@example plot
plot(dag; edge_labels = Dict(directed(:K, :Y) => "hello"))
```

By default the label follows the edge's own angle, while `edge_label_shift`/`edge_label_distance` move it along/off that path:

```@example plot
plot(dag;
    edge_labels = Dict(directed(:K, :Y) => "hi"),
    edge_label_shift = 0.75,
    edge_label_distance = 12,
)
```

For a steep or curved edge, following the edge's angle can leave the label hard to
read; `edge_label_rotation` overrides it with a fixed angle instead:

```@example plot
plot(dag;
    edge_labels = Dict(directed(:A, :X) => "steep"),
    edge_label_rotation = 0.0,
)
```

### Titles

Pass `title` to add a plot title (`nothing` by default, i.e. no title).
`title_fontsize` and `title_color` style it; left as `nothing`, they fall back
to the current Makie theme's axis-title defaults. `title_gap` (default `4.0`,
points) controls the spacing between the title and the graph.

```@example plot
plot(dag; title = "My DAG", title_fontsize = 20, title_color = :navy)
```

## Figure size and margins

| Keyword               | Default       | Controls                                          |
| ---------------------- | ------------- | -------------------------------------------------- |
| `outer_margin`        | `16`          | padding (pixels) around the whole figure           |
| `title_gap`           | `4.0`         | gap (points) between `title` and the graph         |
| `fig_size`            | `(600, 450)`  | figure size in pixels (width, height)              |
| `stretch_to_fig_size` | `false`       | stretch the layout to fill an uneven `fig_size`    |

```@example plot
plot(dag; fig_size = (800, 600))
```

!!! tip "Large graphs need a bigger `fig_size`"
    The default `(600, 450)` is sized for small examples. As the number of
    nodes grows, labels and edges get cramped and can overlap; increase
    `fig_size` (and `node_radius`/`node_label_fontsize` if needed) to keep larger
    causal graphs readable.

!!! tip "Uneven `fig_size` and `stretch_to_fig_size`"
    Node positions keep the layout's own aspect ratio by default, so depending on the chosen `fig_size` you can get a lot of empty space
    in the plot. Pass `stretch_to_fig_size = true` to disable this.

## Composing into an existing figure

So far we've only used `plot`, which builds its own `Figure` and `Axis` for
you. If you already have an `Axis` (say, one panel of a bigger figure),
`plot!(ax, cg; kwargs...)` draws into that instead, with the same keywords as
`plot` above except `outer_margin`, `title_gap`, `fig_size`, and
`stretch_to_fig_size`, since those size the figure `plot` builds for you.

This is how you put two graphs side by side, or mix one in with other plots:

```@example plot
fig = Figure(size = (900, 400))
plot!(Axis(fig[1, 1]; aspect = DataAspect()), dag)
plot!(Axis(fig[1, 2]; aspect = DataAspect()), admg; node_color = :salmon)
Makie.hidedecorations!.(fig.content)
Makie.hidespines!.(fig.content)
fig
```

## Combining options

Here we plot a PAG where we combine a bunch of the styling options from
above:

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
