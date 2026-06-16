# Layout coordinates for graph visualisation.
#
# `layout` is the public entry point. The `:circle` method is built in;
# all other methods are provided by the NetworkLayoutExt extension and require
# `using NetworkLayout` before calling.

"""
    layout(cg::CausalGraph, method::Symbol = :circle; kwargs...)

Compute 2-D node positions for `cg` and return them as a
`Vector{NTuple{2,Float64}}` in the same order as `nodes(cg)`.

The `:circle` method is always available. All other methods require the
NetworkLayout package to be loaded:

| `method`      | Algorithm                          |
|---------------|------------------------------------|
| `:circle`     | Nodes evenly spaced on a circle    |
| `:spring`     | Fruchterman-Reingold force-directed |
| `:stress`     | Stress majorization                |
| `:sfdp`       | Scalable Force-Directed Placement  |
| `:spectral`   | Spectral layout                    |
| `:shell`      | Concentric shells                  |
| `:squaregrid` | Square grid                        |

Extra `kwargs` are forwarded to the NetworkLayout algorithm (e.g. `seed`,
`iterations`).

## Examples

```julia
using CausalGraphInterface

dag = cgraph(directed(:A, :X), directed(:X, :Y); class = DAG)

# Always available:
layout(dag)               # circle layout
layout(dag, :circle)      # explicit

# Requires NetworkLayout extension:
using NetworkLayout

layout(dag, :spring)
layout(dag, :spring; seed = 1405, iterations = 200)
```
"""
function layout(cg::CausalGraph, method::Symbol = :circle; kwargs...)
    return _layout_impl(cg, Val(method); kwargs...)
end

_layout_impl(cg::CausalGraph, ::Val{:circle}; kwargs...) =
    _circle_positions(length(cg.backend.nodes))

# Fallback for any method not handled by a loaded extension.
function _layout_impl(cg::CausalGraph, ::Val{M}; kwargs...) where {M}
    error(
        "Unknown layout method $(repr(M)).\n" *
        "Built-in: :circle.\n" *
        "With NetworkLayout: :spring, :stress, :sfdp, :spectral, :shell, :squaregrid.",
    )
end

function _circle_positions(n::Int)
    n == 0 && return NTuple{2,Float64}[]
    n == 1 && return [(0.0, 0.0)]
    step = 2π / n
    return [(cos(π / 2 - (i - 1) * step), sin(π / 2 - (i - 1) * step)) for i = 1:n]
end
