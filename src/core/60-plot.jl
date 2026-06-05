"""
    caugi_plot(g::CausalGraph; kwargs...) -> Makie.Figure

Plot `g` using Makie. Requires a Makie backend (e.g. `CairoMakie`) to be
loaded before calling.

# Keyword arguments

- `node_radius`: radius of each node circle in layout units. Defaults to
  `max(0.12, 0.4 * sin(π / n))` so nodes never overlap on the circle layout.
- `arrow_size`: length of arrowhead triangles. Defaults to `0.4 * node_radius`.
- `circle_size`: radius of open-circle endpoint markers (`o`). Defaults to
  `0.25 * node_radius`.
- `node_color`: fill colour for nodes. Default `:white`.
- `node_strokecolor`: border colour for nodes. Default `:black`.
- `edge_color`: colour for all edges. Default `:black`.

# Examples

```julia
using CausalGraphInterface, CairoMakie

g = caugi(directed(:A, :B), bidirected(:B, :C), partial(:C, :D); class = UNKNOWN)
caugi_plot(g)
```
"""
function caugi_plot(args...; kwargs...)
    error(
        "caugi_plot requires a Makie backend. " *
        "Load one first, e.g.:\n\n    using CairoMakie\n",
    )
end
