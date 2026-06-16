# [Plotting](@id plotting-guide)

Plotting is provided by the `MakieExt` extension and requires loading a
[Makie](https://docs.makie.org/stable/) backend before use. Below we use
CairoMakie:

```@example plot
using CausalGraphInterface
using CairoMakie
```

## Basic usage

Pass any `CausalGraph` to `Makie.plot`:

```@example plot
dag = cgraph(
       directed(:A, :X),
       directed(:A, :Y),
       directed(:X, :Y);
       class = DAG,
)
Makie.plot(dag)
```

## Edge types

All six edge types are rendered with their conventional endpoint marks:

| Constructor                    | Appearance |
| ------------------------------ | ---------- |
| `directed(:A, :B)`             | `A --> B`  |
| `undirected(:A, :B)`           | `A --- B`  |
| `bidirected(:A, :B)`           | `A <-> B`  |
| `partially_directed(:A, :B)`   | `A o-> B`  |
| `partially_undirected(:A, :B)` | `A o-- B`  |
| `partial(:A, :B)`              | `A o-o B`  |

```@example plot
cg = cgraph(
    partial(:X, :Y),
    partially_directed(:X, :Z),
    partially_undirected(:Z, :W);
    class = UNKNOWN,
)
Makie.plot(cg)
```

## [Layouts](@id plot-layouts)

The `layout` keyword controls node placement. The `:circle` layout is always
available. All other layouts require
[NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl):

```@example plot
using NetworkLayout

Makie.plot(dag; layout = :spring)
```

| `layout`      | Algorithm                           |
| ------------- | ----------------------------------- |
| `:circle`     | Evenly spaced on a circle (default) |
| `:spring`     | Fruchterman-Reingold force-directed |
| `:stress`     | Stress majorization                 |
| `:sfdp`       | Scalable Force-Directed Placement   |
| `:spectral`   | Spectral layout                     |
| `:shell`      | Concentric shells                   |
| `:squaregrid` | Square grid                         |

Extra keyword arguments are forwarded to the underlying NetworkLayout algorithm:

```@example plot
Makie.plot(dag; layout = :spring, seed = 42, iterations = 500)
```

## Node styling

Each node style argument accepts either a **scalar** (applied to all nodes) or a
**`Dict{Symbol, <value>}`** keyed by node name, with `:default` as a fallback.

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
Makie.plot(dag; node_color = :lightblue, node_strokecolor = :navy)
```

Highlight individual nodes:

```@example plot
Makie.plot(dag;
    node_color = Dict(:A => :salmon, :default => :white),
    node_strokecolor = Dict(:A => :crimson, :default => :black),
)
```

Adjust node size and arrowhead proportions:

```@example plot
Makie.plot(dag; node_radius = 0.18, arrow_size = 0.07)
```

## Edge styling

Each edge style argument accepts either a **scalar** or a **`Dict`** keyed by:

- an **edge-type symbol** (`:directed`, `:undirected`, `:bidirected`,
  `:partially_directed`, `:partially_undirected`, `:partial`)
- a **`(src, dst)` tuple** for a specific edge
- `:default` as a fallback

**Lookup precedence** (highest wins): specific edge tuple → edge-type symbol →
`:default` → hard-coded fallback.

| Keyword      | Default  | Controls              |
| ------------ | -------- | --------------------- |
| `edge_color` | `:black` | line / marker color   |
| `linewidth`  | `1.5`    | line width            |

Color edges by type:

```@example plot
admg = cgraph(
       directed(:X, :Y),
       bidirected(:X, :Z),
       directed(:Z, :Y);
       class = ADMG,
)

Makie.plot(admg;
    edge_color = Dict(:directed => :steelblue, :bidirected => :crimson),
    linewidth  = Dict(:bidirected => 2.5, :default => 1.5),
)
```

Highlight a specific edge:

```@example plot
Makie.plot(dag;
    edge_color = Dict((:A, :X) => :red, :default => :black),
)
```

## Combining options

```@example plot
admg2 = cgraph(
    directed(:U, :X),
    directed(:U, :Y),
    directed(:X, :Y),
    bidirected(:X, :Y);
    class = ADMG,
)

Makie.plot(
    admg2;
    node_color       = Dict(:U => :lightyellow, :default => :white),
    node_strokecolor = :gray30,
    edge_color       = Dict(:directed => :gray20, :bidirected => :crimson),
    linewidth        = Dict(:bidirected => 2.0, :default => 1.5),
    node_radius      = 0.14,
)
```
