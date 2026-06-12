# [Plotting](@id plotting-guide)

Plotting is provided by the `MakieExt` extension and requires loading a
[Makie](https://docs.makie.org/stable/) backend before use. Below we use
CairoMakie:

```@example plot
using CausalGraphInterface
using CairoMakie
```

Layout algorithms beyond the default circle require
[NetworkLayout.jl](https://github.com/JuliaGraphs/NetworkLayout.jl):

```julia
using NetworkLayout  # unlocks :spring, :stress, :sfdp, :spectral, :shell, :squaregrid
```

## Basic usage

Pass any `CausalGraph` to `Makie.plot`:

```@example plot
dag = caugi(directed(:A, :X), directed(:A, :Y), directed(:X, :Y); class = DAG)
Makie.plot(dag)
```

## Edge types

All six edge types are rendered with their conventional endpoint marks:

\| Constructor \| Appearance \| Endpoints \|
\|--------------------------------\|-------------\|------------------------\| \|
`directed(:A, :B)` \| `A --> B` \| tail – arrowhead \| \| `undirected(:A, :B)`
\| `A --- B` \| tail – tail \| \| `bidirected(:A, :B)` \| `A <-> B` \| arrowhead
– arrowhead \| \| `partially_directed(:A, :B)` \| `A o-> B` \| circle –
arrowhead \| \| `partially_undirected(:A, :B)` \| `A o-- B` \| circle – tail \|
\| `partial(:A, :B)` \| `A o-o B` \| circle – circle \|

A graph combining several edge types:

```@example plot
cg = caugi(
    partial(:X, :Y),
    partially_directed(:X, :Z),
    partially_undirected(:Z, :W);
    class = UNKNOWN,
)
Makie.plot(cg)
```

## [Layouts](@id plot-layouts)

The `layout` keyword controls node placement. The `:circle` layout is always
available. All others require NetworkLayout.

\| `layout` \| Algorithm \|
\|---------------\|-------------------------------------\| \| `:circle` \|
Evenly spaced on a circle (default) \| \| `:spring` \| Fruchterman-Reingold
force-directed \| \| `:stress` \| Stress majorization \| \| `:sfdp` \| Scalable
Force-Directed Placement \| \| `:spectral` \| Spectral layout \| \| `:shell` \|
Concentric shells \| \| `:squaregrid` \| Square grid \|

Extra keyword arguments are forwarded to the NetworkLayout algorithm:

```@example plot
using NetworkLayout

Makie.plot(dag; layout = :spring)
Makie.plot(dag; layout = :spring, seed = 42, iterations = 500)
```

Node placement can also be specified using specific positions. Below we first
call `layout` then fine-tune one of the node positions before plotting:

```@example plot
positions = layout(dag, :spring; seed = 42)
positions[2] = (0.0, 0.0)  # move node 2 to the origin
Makie.plot(dag; layout = positions)
```

## Sizing

Three keyword arguments control the geometry. All must be positive `Real`
values; the defaults scale with the number of nodes.

\| Keyword \| Controls \| Default \|
\|----------------\|---------------------------------\|-----------------------------\|
\| `node_radius` \| radius of each node circle \| `max(0.12, 0.4 sin(π / n))` \|
\| `arrow_size` \| length of arrowhead triangles \| `0.4 × node_radius` \| \|
`circle_size` \| radius of open-circle endpoints \| `0.28 × node_radius` \|

```@example plot
Makie.plot(dag; node_radius = 0.18, arrow_size = 0.07, circle_size = 0.05)
```

## Node styling

Each node style argument accepts either a **scalar** (applied to all nodes) or a
**`Dict{Symbol, <value>}`** keyed by node name. Use `:default` inside the dict
as a fallback for nodes not listed explicitly.

\| Keyword \| Default \| Controls \|
\|--------------------\|----------\|-------------------------------\| \|
`node_color` \| `:white` \| fill color \| \| `node_strokecolor` \| `:black` \|
border color \| \| `node_strokewidth` \| `2.0` \| border line width (positive)
\|

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

\| Keyword \| Default \| Controls \|
\|--------------\|----------\|-------------------------------\| \| `edge_color`
\| `:black` \| line / marker color \| \| `linewidth` \| `1.5` \| line width
(positive) \|

Global edge color:

```@example plot
Makie.plot(dag; edge_color = :steelblue)
```

Color edges by type:

```@example plot
admg = caugi(directed(:X, :Y), bidirected(:X, :Z), directed(:Z, :Y); class = ADMG)

Makie.plot(admg;
    edge_color = Dict(:directed => :steelblue, :bidirected => :crimson),
)
```

Vary line width by type:

```@example plot
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

Combine type defaults with a specific edge override:

```@example plot
Makie.plot(admg;
    edge_color = Dict(
        :directed   => :steelblue,
        :bidirected => :crimson,
        (:X, :Y)    => :orange,
    ),
)
```

## Combining options

```@example plot
admg2 = caugi(
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
