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
| `true` | `Bool` | `ancestors`, `descendants`, `possible_ancestors`, `possible_descendants`, `anteriors`, `posteriors` |

When `true` (open definition), the queried node itself is excluded from the
result. Set to `false` to use the closed definition (node included).

```julia
set_preferences!(CausalStructures, "open" => false)
```

--------------------------------------------------------------------------------

## Plotting

Every visual default used by `plot(cg; ...)` (Makie backend required) can be overridden
the same way, e.g. `set_preferences!(CausalStructures, "plot_node_color" => "lightblue")`.

| Key | Default | Notes |
| --- | ------- | ----- |
| `"plot_layout"` | `:stress` | One of `:spring`, `:stress`, `:sfdp`, `:spectral`, `:shell`, `:squaregrid`; requires NetworkLayout, see [Layouts](@ref plot-layouts) |
| `"plot_node_color"` | `"white"` | Any [Makie-compatible colour](https://docs.makie.org/stable/explanations/colors) |
| `"plot_node_strokecolor"` | `"black"` | |
| `"plot_node_strokewidth"` | `2.0` | |
| `"plot_edge_color"` | `"black"` | |
| `"plot_linewidth"` | `1.5` | |
| `"plot_curvature"` | `nothing` | `nothing` routes each edge automatically; a number forces that curvature (including `0.0`, for a straight line) |
| `"plot_label_color"` | `"black"` | |
| `"plot_label_fontsize"` | `14.0` | |
| `"plot_label_font"` | `"regular"` | Any [Makie-compatible font](https://docs.makie.org/stable/explanations/fonts) name or theme key |
| `"plot_node_padding"` | `10.0` | Space between label and circle edge; ignored when `node_radius` is set explicitly |
| `"plot_edge_arrow_fill"` | `nothing` | `nothing` matches the edge's own color (solid arrowhead); set e.g. `"transparent"` for a hollow one |
| `"plot_fig_size"` | `[600.0, 450.0]` | Pixels, fixed regardless of graph/layout; see [Figure size and margins](@ref) |
| `"plot_stretch_to_fig_size"` | `false` | Stretch the layout to fill an uneven `fig_size` instead of leaving margins |
