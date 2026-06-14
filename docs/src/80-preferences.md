# Preferences

Several defaults can be changed project-wide using
[Preferences.jl](https://github.com/JuliaPackageOrganizations/Preferences.jl).
Set a preference once, restart Julia, and the new value becomes the default for
every call in that project.

```julia
using Preferences, CausalGraphInterface

set_preferences!(CausalGraphInterface, "key" => value)
# restart Julia
```

To restore a preference to its built-in default, delete it:

```julia
delete_preferences!(CausalGraphInterface, "key")
# restart Julia
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
set_preferences!(CausalGraphInterface, "open" => false)
```

--------------------------------------------------------------------------------

## Plotting

All plot preferences affect `Makie.plot(cg; ...)` when the corresponding keyword
argument is not passed explicitly. They require loading a Makie backend.

### `"plot_layout"`: default layout algorithm

| Default | Type | Valid values |
| ------- | ---- | ------------ |
| `:circle` | `String` | `:circle`, `:spring`, `:stress`, `:sfdp`, `:spectral`, `:shell`, `:squaregrid` |

Note, that all algorithms except `:circle` require NetworkLayout, see the
[Layouts](@ref plot-layouts) section for more details.

```julia
set_preferences!(CausalGraphInterface, "plot_layout" => "spring")
```

### `"plot_node_color"`: default node fill colour

| Default | Type |
| ------- | ---- |
| `"white"` | `String` |

Any [Makie-compatible colour name or hex
string](https://docs.makie.org/stable/explanations/colors).

```julia
set_preferences!(CausalGraphInterface, "plot_node_color" => "lightblue")
```

### `"plot_node_strokecolor"`: default node border colour

| Default | Type |
| ------- | ---- |
| `"black"` | `String` |

```julia
set_preferences!(CausalGraphInterface, "plot_node_strokecolor" => "gray30")
```

### `"plot_node_strokewidth"`: default node border width

| Default | Type |
| ------- | ---- |
| `2.0` | `Number` |

```julia
set_preferences!(CausalGraphInterface, "plot_node_strokewidth" => 1.5)
```

### `"plot_edge_color"`: default edge colour

| Default | Type |
| ------- | ---- |
| `"black"` | `String` |

```julia
set_preferences!(CausalGraphInterface, "plot_edge_color" => "steelblue")
```

### `"plot_linewidth"`: default edge line width

| Default | Type |
| ------- | ---- |
| `1.5` | `Number` |

```julia
set_preferences!(CausalGraphInterface, "plot_linewidth" => 2.0)
```
