# [Plotting](@id plotting-guide)

Plotting is provided by the `MakieExt` extension and requires loading a
[Makie](https://docs.makie.org/stable/) backend before use. Below we use
CairoMakie:

```@example plot
using CausalStructures
using CairoMakie
```

## Basic usage

Pass any `CausalGraph` to `plot`:

```@example plot
dag = cgraph("A --> X + Y, X --> Y"; class = DAG)
plot(dag)
```

## [Layouts](@id plot-layouts)

The `layout` keyword controls node placement. The `:circle` layout is always
available and is the default. All other layouts require
[NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl); once
loaded, the default switches to `:stress`:

```@example plot
using NetworkLayout

plot(dag)                 # now uses :stress instead of :circle
plot(dag; layout = :spring)
```

We provide these short-hand names for convenience:

| `layout`      | Algorithm                                                   |
| ------------- | ------------------------------------------------------------ |
| `:circle`     | Evenly spaced on a circle (default without NetworkLayout)   |
| `:spring`     | Fruchterman-Reingold force-directed                          |
| `:stress`     | Stress majorization (default once NetworkLayout is loaded)  |
| `:sfdp`       | Scalable Force-Directed Placement                            |
| `:spectral`   | Spectral layout                                               |
| `:shell`      | Concentric shells                                             |
| `:squaregrid` | Square grid                                                    |

Extra keyword arguments are forwarded to the underlying NetworkLayout algorithm:

```@example plot
plot(dag; layout = :spring, seed = 42, iterations = 500)
```

## Node styling

Each node style argument accepts either a scalar (applied to all nodes) or a `Dict{Symbol, <value>}` keyed by node name, with `:default` as a fallback.

| Keyword             | Default                      | Controls                        |
| ------------------- | ---------------------------- | ------------------------------- |
| `node_color`        | `:white`                     | fill color                      |
| `node_strokecolor`  | `:black`                     | border color                    |
| `node_strokewidth`  | `2.0`                        | border line width               |
| `node_radius`       | `max(0.12, 0.4 sin(π / n))` | radius of each node circle      |
| `arrow_size`        | `0.4 × node_radius`          | length of arrowhead triangles   |
| `circle_size`       | `0.28 × node_radius`         | radius of open-circle endpoints |

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

Adjust node size and arrowhead proportions:

```@example plot
plot(dag; node_radius = 0.18, arrow_size = 0.07)
```

## Edge styling

Each edge style argument accepts either a scalar or a `Dict` keyed by (and follows this precendence):

- a `(src, dst)` tuple for a specific edge
- an edge-type symbol (`:directed`, `:undirected`, `:bidirected`, `:partially_directed`, `:partially_undirected`, `:partial`)
- a `(src, dst)` tuple for a specific edge
- `:default` as a fallback

| Keyword      | Default  | Controls             |
| ------------ | -------- | --------------------- |
| `edge_color` | `:black` | line / marker color   |
| `linewidth`  | `1.5`    | line width            |

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
to the current Makie theme's axis-title defaults.

```@example plot
plot(dag; title = "My DAG", title_fontsize = 20, title_color = :navy)
```

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
