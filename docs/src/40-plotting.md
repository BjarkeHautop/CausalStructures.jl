# [Plotting](@id plotting-guide)

Plotting is provided by the `MakieExt` extension and requires loading a
[Makie](https://docs.makie.org/stable/) backend before use. Node placement
requires [NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl).
Below we use CairoMakie:

```@example plot
using CausalStructures
using CairoMakie
using NetworkLayout
```

## Basic usage

Pass any `CausalGraph` to `plot`:

```@example plot
dag = cgraph("A --> X + Y, X --> Y"; class = DAG)
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

`layout` also accepts a `Vector` of `(x, y)` positions (one per node, in the
order returned by `nodes(cg)`) instead of a `Symbol`.

!!! tip "Tweaking a layout by hand"
    [`layout`](@ref) itself returns this `Vector`, so you can compute a
    starting layout, tweak individual node positions by hand, and pass the
    modified vector back to `plot`:

    ```@example plot
    positions = layout(dag, :spring)
    positions[1] = (0.0, 2.0)
    plot(dag; layout = positions)
    ```

## Node styling

Each node style argument accepts either a scalar (applied to all nodes) or a `Dict{Symbol, <value>}` keyed by node name, with `:default` as a fallback.

| Keyword             | Default                             | Controls                        |
| ------------------- | ------------------------------------ | -------------------------------- |
| `node_color`        | `:white`                             | fill color                      |
| `node_strokecolor`  | `:black`                             | border color                    |
| `node_strokewidth`  | `2.0`                                | border line width               |
| `node_radius`       | `nothing` (text-fit, per node)       | radius of each node circle      |
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

### Text-fit node sizing

By default (`node_radius = nothing`), each node's circle is sized to fit its
own label:

```@example plot
longlabels = cgraph("Exposure --> Y_outcome, Mediator --> Y_outcome"; class = DAG)
plot(longlabels)
```

Pass `node_radius` explicitly to size every node uniformly instead:

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
| `label_color`    | `:black`   | node label text color     |
| `label_fontsize` | `14.0`     | node label font size      |
| `label_font`     | `:regular` | node label font           |

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

```@example plot
admg2 = cgraph("U --> X + Y, X --> Y, X <-> Z, Z --> Y"; class = ADMG)

plot(
    admg2;
    node_color       = Dict(:U => :lightyellow, :default => :white),
    node_strokecolor = :gray30,
    edge_color       = Dict(:directed => :gray20, :bidirected => :crimson),
    linewidth        = Dict(:bidirected => 2.0, :default => 1.5),
    node_radius      = 0.14,
    label_color      = Dict(:U => :gray30, :default => :black),
    label_fontsize   = 16,
    title            = "Confounded ADMG",
    title_fontsize   = 18,
    title_color      = :gray20,
)
```
