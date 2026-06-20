# Preferences

Several defaults can be changed project-wide using
[Preferences.jl](https://github.com/JuliaPackageOrganizations/Preferences.jl).

These preferences are stored per-project. After setting a value, restart Julia for changes to take effect globally within the project.

```julia
using Preferences, CausalStructures

set_preferences!(CausalStructures, "key" => value)
```

To restore a preference to its default value, delete it:

```julia
delete_preferences!(CausalStructures, "key")
```

--------------------------------------------------------------------------------

## Traversal

### `"open"`: open vs closed neighbourhood definition

| Default | Type | Affects |
| ------- | ---- | ------- |
| `true` | `Bool` | `ancestors`, `descendants`, `possible_ancestors`, `possible_descendants`, `anteriors`, `posteriors` |

When `true` (open definition), the queried node itself is excluded from the
result. Set to `false` to use the closed definition (node included).

```julia
set_preferences!(CausalStructures, "open" => false)
```

--------------------------------------------------------------------------------

## Plotting

Controls default visual configuration used by `Makie.plot(cg; ...)`.
A Makie backend is required for plotting.

### `"plot_layout"`

Default graph layout algorithm.

| Default | Type | Valid values |
| ------- | ---- | ------------ |
| `:circle` | `String` | `:circle`, `:spring`, `:stress`, `:sfdp`, `:spectral`, `:shell`, `:squaregrid` |

Note: all layouts except `:circle` require NetworkLayout, see the
[Layouts](@ref plot-layouts) section for more details.

```julia
set_preferences!(CausalStructures, "plot_layout" => "spring")
```

### `"plot_node_color"`

Default node fill colour

| Default | Type |
| ------- | ---- |
| `"white"` | `String` |

Any [Makie-compatible colour name or hex
string](https://docs.makie.org/stable/explanations/colors).

```julia
set_preferences!(CausalStructures, "plot_node_color" => "lightblue")
```

### `"plot_node_strokecolor"`

Default node border colour.

| Default | Type |
| ------- | ---- |
| `"black"` | `String` |

```julia
set_preferences!(CausalStructures, "plot_node_strokecolor" => "gray30")
```

### `"plot_node_strokewidth"`

Default node border width.

| Default | Type |
| ------- | ---- |
| `2.0` | `Number` |

```julia
set_preferences!(CausalStructures, "plot_node_strokewidth" => 1.5)
```

### `"plot_edge_color"`

Default edge color.

| Default | Type |
| ------- | ---- |
| `"black"` | `String` |

```julia
set_preferences!(CausalStructures, "plot_edge_color" => "steelblue")
```

### `"plot_linewidth"`

Default edge line width.

| Default | Type |
| ------- | ---- |
| `1.5` | `Number` |

```julia
set_preferences!(CausalStructures, "plot_linewidth" => 2.0)
```

### `"plot_curvature"`

Default edge curvature. `0.0` draws straight edges; positive values bow edges to
the left of the `src --> dst` direction and negative values to the right.

| Default | Type |
| ------- | ---- |
| `0.0` | `Number` |

```julia
set_preferences!(CausalStructures, "plot_curvature" => 0.2)
```
