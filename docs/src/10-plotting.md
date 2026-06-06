# Plotting

Plotting is provided by the `MakieExt` extension and requires loading a Makie
backend before use. Below we use CairoMakie:

```julia
using CausalGraphInterface
using CairoMakie
```

## Basic usage

Pass any `CausalGraph` to `Makie.plot`:

```julia
dag = caugi(directed(:A, :X), directed(:A, :Y), directed(:X, :Y); class = DAG)
fig = Makie.plot(dag)
```

## Edge types

All six edge types are rendered with their conventional endpoint marks:

| Constructor                    | Appearance  | Endpoints              |
|--------------------------------|-------------|------------------------|
| `directed(:A, :B)`             | `A --> B`   | tail – arrowhead       |
| `undirected(:A, :B)`           | `A --- B`   | tail – tail            |
| `bidirected(:A, :B)`           | `A <-> B`   | arrowhead – arrowhead  |
| `partially_directed(:A, :B)`   | `A o-> B`   | circle – arrowhead     |
| `partially_undirected(:A, :B)` | `A --o B`   | tail – circle          |
| `partial(:A, :B)`              | `A o-o B`   | circle – circle        |

## Sizing

Three keyword arguments control the geometry. All accept any `Real` value; the
defaults scale with the number of nodes.

| Keyword        | Controls                        | Default                     |
|----------------|---------------------------------|-----------------------------|
| `node_radius`  | radius of each node circle      | `max(0.12, 0.4 sin(π / n))` |
| `arrow_size`   | length of arrowhead triangles   | `0.4 × node_radius`         |
| `circle_size`  | radius of open-circle endpoints | `0.28 × node_radius`        |

```julia
fig = Makie.plot(dag; node_radius = 0.15, arrow_size = 0.06, circle_size = 0.04)
```

## Node styling

Each node style argument accepts either a **scalar** (applied to all nodes) or a
**`Dict{Symbol, <value>}`** keyed by node name. Use `:default` inside the dict
as a fallback for nodes not listed explicitly.

| Keyword            | Default  | Controls               |
|--------------------|----------|------------------------|
| `node_color`       | `:white` | fill color             |
| `node_strokecolor` | `:black` | border color           |
| `node_strokewidth` | `2.0`    | border line width      |

Global styling:

```julia
fig = Makie.plot(dag; node_color = :lightblue, node_strokecolor = :navy)
```

Highlight individual nodes:

```julia
fig = Makie.plot(dag;
    node_color = Dict(:A => :salmon, :default => :white),
    node_strokecolor = Dict(:A => :crimson, :default => :black),
)
```

## Edge styling

Each edge style argument accepts either a **scalar** or a **`Dict`**. The dict
may be keyed by:

- an **edge-type symbol** (`:directed`, `:undirected`, `:bidirected`,
  `:partially_directed`, `:partially_undirected`, `:partial`)
- a **`(src, dst)` tuple** for a specific edge
- `:default` as a fallback for anything not listed

**Lookup precedence** (highest wins):

1. Specific edge `(src, dst)` pair
2. Edge-type symbol
3. `:default` inside the dict
4. Hard-coded fallback

| Keyword      | Default  | Controls          |
|--------------|----------|-------------------|
| `edge_color` | `:black` | line / marker color |
| `linewidth`  | `1.5`    | line width        |

Global edge color:

```julia
fig = Makie.plot(dag; edge_color = :steelblue)
```

Color edges by type:

```julia
admg = caugi(directed(:X, :Y), bidirected(:X, :Z), directed(:Z, :Y); class = ADMG)

fig = Makie.plot(admg;
    edge_color = Dict(:directed => :steelblue, :bidirected => :crimson),
)
```

Vary line width by type:

```julia
fig = Makie.plot(admg;
    edge_color = Dict(:directed => :steelblue, :bidirected => :crimson),
    linewidth  = Dict(:bidirected => 2.5, :default => 1.5),
)
```

Highlight a specific edge:

```julia
fig = Makie.plot(dag;
    edge_color = Dict((:A, :X) => :red, :default => :black),
)
```

Combine type defaults with a specific edge override:

```julia
fig = Makie.plot(admg;
    edge_color = Dict(
        :directed   => :steelblue,
        :bidirected => :crimson,
        (:X, :Y)    => :orange,   # overrides :directed for this edge
    ),
)
```

## Combining options

```julia
admg = caugi(
    directed(:U, :X),
    directed(:U, :Y),
    directed(:X, :Y),
    bidirected(:X, :Y);
    class = ADMG,
)

fig = Makie.plot(
    admg;
    node_color       = Dict(:U => :lightyellow, :default => :white),
    node_strokecolor = :gray30,
    edge_color       = Dict(:directed => :gray20, :bidirected => :crimson),
    linewidth        = Dict(:bidirected => 2.0, :default => 1.5),
    node_radius      = 0.14,
)
```
