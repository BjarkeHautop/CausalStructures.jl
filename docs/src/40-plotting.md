# [Plotting](@id plotting-guide)

Plotting is provided by the `MakieExt` extension and requires loading a
[Makie](https://docs.makie.org/stable/) backend before use. Node placement
requires [NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl)
(or bring your own layout). Below we use CairoMakie:

```@example plot
using CausalStructures
using CairoMakie
using NetworkLayout
```

## Basic usage

Pass any `CausalGraph` to `plot`. Consider Figure 6.5 of
[peters2017elements](@cite):

```@example plot
dag = cgraph(
    "C --> X, A --> X + K, X --> F + D, K --> Y, D --> Y + G, Y --> H";
    class = DAG,
)
plot(dag)
```

## [Layouts](@id plot-layouts)

The `layout` keyword controls node placement and defaults to `:stress`.

```@example plot
plot(dag; layout = :spring)
```

We provide these short-hand names for convenience:

| `layout`      | Algorithm                                                   |
| ------------- | ------------------------------------------------------------ |
| `:spring`     | Fruchterman-Reingold force-directed                          |
| `:stress`     | Stress majorization (the default)                            |
| `:sfdp`       | Scalable Force-Directed Placement                            |
| `:spectral`   | Spectral layout                                               |
| `:shell`      | Concentric shells                                             |
| `:squaregrid` | Square grid                                                    |

Extra keyword arguments are forwarded to the underlying NetworkLayout algorithm:

```@example plot
plot(dag; layout = :spring, seed = 1405, iterations = 500)
```

`layout` also accepts explicit positions instead of a `Symbol`: either a
`Dict` of `(x, y)` pairs keyed by node name, or a `Vector` of them in the
order returned by `nodes(cg)`:

```@example plot
plot(dag; layout = Dict(
    :A => (0, 1), :C => (0, -1), :K => (1, 1), :X => (1, -1),
    :D => (2, -1), :F => (2, -2), :Y => (3, 0), :G => (3, 1), :H => (4, 0),
))
```

!!! tip "Tweaking a layout by hand"
    [`layout`](@ref) returns exactly this `Dict`, so you can compute a
    starting layout, move individual nodes by name, and pass it back to
    `plot`:

    ```@example plot
    positions = layout(dag, :spring)
    positions[:A] = (0.0, 2.0)
    plot(dag; layout = positions)
    ```

## Node styling

Each node style argument accepts either a scalar (applied to all nodes) or a `Dict{Symbol, <value>}` keyed by node name, with `:default` as a fallback.

| Keyword             | Default                             | Controls                        |
| ------------------- | ------------------------------------ | -------------------------------- |
| `node_color`        | `:white`                             | fill color                      |
| `node_strokecolor`  | `:black`                             | border color                    |
| `node_strokewidth`  | `2.0`                                | border line width               |
| `node_linestyle`    | `nothing` (solid)                    | border line style               |
| `node_shape`        | `:round`                             | node outline shape              |
| `node_radius`       | `nothing` (text-fit, per node)       | size of each node               |
| `node_padding`      | `10.0`                                | clearance kept around each node's label when `node_radius` is `nothing` |
| `arrow_size`        | `0.4 ×` node-count-based reference   | length of arrowhead triangles   |
| `circle_size`       | `0.28 ×` node-count-based reference  | radius of open-circle endpoints |

Global styling:

```@example plot
plot(dag; node_color = :lightblue, node_strokecolor = :navy)
```

Highlight individual nodes:

```@example plot
plot(dag;
    node_color = Dict(:A => :salmon, :default => :white),
    node_strokecolor = Dict(:A => :crimson, :default => :black),
)
```

### Node shapes

`node_shape` is either `:round` (the default) or `:box`.

```@example plot
plot(dag; node_shape = Dict(:K => :box, :default => :round))
```

`node_linestyle` styles the border - a dashed border is the usual mark for an
unobserved variable:

```@example plot
plot(cgraph("U --> X + Y, X --> Y"; class = DAG);
    node_linestyle = Dict(:U => :dash),
    node_strokecolor = Dict(:U => :gray50, :default => :black),
)
```

### Text-fit node sizing

By default (`node_radius = nothing`), each node is sized to fit its
own label:

```@example plot
longlabels = cgraph("Exposure --> Mediator --> Y_outcome"; class = DAG)
plot(longlabels)
```

Pass `node_radius` explicitly to size every node uniformly instead

```@example plot
plot(dag; node_radius = 0.18, arrow_size = 0.07)
```

## Edge styling

Each edge style argument accepts either a scalar or a `Dict` keyed by (and follows this precedence):

1. a `(src, dst)` tuple for a specific edge
2. a node name (`Symbol`), applying to every edge touching that node
3. an edge-type symbol (`:directed`, `:undirected`, `:bidirected`, `:partially_directed`, `:partially_undirected`, `:partial`)
4. `:default` as a fallback

| Keyword      | Default   | Controls             |
| ------------ | --------- | --------------------- |
| `edge_color` | `:black`  | line / marker color   |
| `arrow_fill` | `nothing` | arrowhead fill color  |
| `linewidth`  | `1.5`     | line width            |

Color edges by type:

```@example plot
admg = cgraph("X --> Y, X <-> Z, Z --> Y"; class = ADMG)

plot(admg;
    edge_color = Dict(:directed => :steelblue, :bidirected => :crimson),
    linewidth  = Dict(:bidirected => 2.5, :default => 1.5),
)
```

Highlight a specific edge:

```@example plot
plot(dag;
    edge_color = Dict((:A, :X) => :red, :default => :black),
)
```

Highlight every edge touching a node:

```@example plot
plot(dag;
    edge_color = Dict(:A => :red, :default => :black),
)
```

`arrow_fill` is the arrowhead's fill color; `nothing` (the default) matches
the edge's own resolved `edge_color`, so arrowheads render solid. Pass a
transparent color for a hollow, outline-only arrowhead:

```@example plot
plot(dag; arrow_fill = :transparent)
```

## Label styling

Each label style argument accepts either a scalar or a `Dict{Symbol, <value>}` keyed by node name, with `:default` as a fallback (same resolution rules as node styling).

| Keyword          | Default    | Controls                |
| ---------------- | ---------- | ------------------------ |
| `labels`         | `nothing`  | text drawn in each node   |
| `label_color`    | `:black`   | node label text color     |
| `label_fontsize` | `14.0`     | node label font size      |
| `label_font`     | `:regular` | node label font           |

By default each node is labelled with its own name. `labels` can be
used to overwrite this:

```@example plot
plot(cgraph("A0 --> L1 --> A1 --> Y, A0 --> Y + A1"; class = DAG);
    labels = Dict(
        :A0 => "Treatment\nat baseline",
        :L1 => "Confounder\nat time 1",
        :A1 => "Treatment\nat time 1",
    ),
)
```

Node sizing accounts for multi-line labels, so the nodes grow to fit.

```@example plot
plot(dag; label_fontsize = 18, label_color = :navy)
```

```@example plot
plot(dag; label_color = Dict(:A => :crimson, :default => :black))
```

## Title

Pass `title` to add a plot title (`nothing` by default, i.e. no title).
`title_fontsize` and `title_color` style it; left as `nothing`, they fall back
to the current Makie theme's axis-title defaults. `title_gap` (default `4.0`,
points) controls the spacing between the title and the graph.

```@example plot
plot(dag; title = "My DAG", title_fontsize = 20, title_color = :navy)
```

## Figure size and margins

| Keyword        | Default       | Controls                                                     |
| -------------- | ------------- | -------------------------------------------------------------- |
| `outer_margin` | `16`          | padding (pixels) around the whole figure                       |
| `title_gap`    | `4.0`         | gap (points) between `title` and the graph                     |
| `fig_size`     | `(600, 450)`  | figure size in pixels (width, height)                          |

```@example plot
plot(dag; fig_size = (800, 600))
```

!!! note "Large graphs need a bigger `fig_size`"
    The default `(600, 450)` is sized for small examples. As the number of
    nodes grows, labels and edges get cramped and can overlap; increase
    `fig_size` (and `node_radius`/`label_fontsize` if needed) to keep larger
    causal graphs readable.

### Automatic edge routing

An edge whose straight `src --> dst` line would pass too close to a
non-incident node automatically bends around it as a Bezier curve, rather
than being drawn straight through it. Edges with nothing in their way are
always drawn straight.

```@example plot
detour = cgraph("A --> X + Y, X --> Y"; class = DAG)

# A, X, Y placed in a line, so the straight A --> Y edge would cross X.
plot(detour; layout = [(0, 0), (1, 0), (2, 0)])
```

## Combining options

Here we plot a PAG where we combine a bunch of different
styling options:

```@example plot
pag = cgraph(
    "C o-> X, D --> G + Y, X --> D + F, Y --> H, K o-> X, K --> Y";
    class = PAG,
)

plot(
    pag;
    node_color       = Dict(:X => :lightyellow, :default => :white),
    node_strokecolor = :gray30,
    edge_color       = Dict(:partially_directed => :crimson, :default => :gray20),
    circle_size      = 0.05,
    node_radius      = 0.14,
    label_color      = Dict(:X => :gray30, :default => :black),
    label_fontsize   = 16,
    title            = "A PAG",
    title_fontsize   = 18,
    title_color      = :gray20,
)
```
