# Preferences

Several defaults can be changed project-wide using
[Preferences.jl](https://github.com/JuliaPackaging/Preferences.jl).

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
| `true` | `Bool` | [`ancestors`](@ref), [`descendants`](@ref), [`possible_ancestors`](@ref), [`possible_descendants`](@ref), [`anteriors`](@ref), [`posteriors`](@ref) |

When `true` (open definition), the queried node itself is excluded from the
result. Set to `false` to use the closed definition (node included).

```julia
set_preferences!(CausalStructures, "open" => false)
```

--------------------------------------------------------------------------------

## Plotting

### `"plot_layout"`: default layout algorithm

| Default | Type | Affects |
| ------- | ---- | ------- |
| `nothing` (falls back to `:stress`, or `:sugiyama` for a [`DAG`](@ref) once Sugiyama is loaded) | `Union{Symbol,Nothing}` | [`layout`](@ref), `plot(cg; ...)` |

One of `:spring`, `:stress`, `:sfdp`, `:spectral`, `:shell`, `:squaregrid`
(require NetworkLayout) or `:sugiyama` (requires Sugiyama); see
[Layouts](@ref plot-layouts).

```julia
set_preferences!(CausalStructures, "plot_layout" => "spring")
```

For `plot`'s appearance (colors, linewidths, fonts, node shapes, figure
size, ...), use a
[Makie theme](https://docs.makie.org/stable/explanations/theming/themes):

```julia
using Makie

Makie.set_theme!(CausalGraphPlot = (node_color = :lightblue, linewidth = 2))
```
