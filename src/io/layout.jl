# Layout coordinates for graph visualisation.
#
# `layout` is the public entry point. All methods are provided by the
# NetworkLayoutExt extension and require `using NetworkLayout` before calling.

const _LAYOUT_METHODS = (:spring, :stress, :sfdp, :spectral, :shell, :squaregrid)

function _default_layout_method()
    _PLOT_LAYOUT_PREFERENCE !== nothing && return Symbol(_PLOT_LAYOUT_PREFERENCE)
    return :stress
end

"""
    layout(cg::CausalGraph, method::Symbol = :stress; kwargs...)

Compute 2-D node positions for `cg` and return them as a
`Dict{Symbol,NTuple{2,Float64}}` keyed by node name.

Requires the NetworkLayout package to be loaded (`using NetworkLayout`):

| `method`      | Algorithm                          |
|---------------|------------------------------------|
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
using CausalStructures, NetworkLayout

dag = DAG(directed(:A, :X), directed(:X, :Y))

layout(dag)                # :stress (the default)
layout(dag, :spring)
layout(dag, :spring; seed = 1405, iterations = 200)

positions = layout(dag, :spring)
positions[:A] = (0.0, 2.0)
plot(dag; layout = positions)
```
"""
function layout(cg::CausalGraph, method::Symbol = _default_layout_method(); kwargs...)
    coords = _layout_impl(cg, Val(method); kwargs...)
    return Dict{Symbol,NTuple{2,Float64}}(
        nd => (Float64(p[1]), Float64(p[2])) for (nd, p) in zip(cg.backend.nodes, coords)
    )
end

# Fallback for any method not handled by a loaded extension.
function _layout_impl(::CausalGraph, ::Val{M}; kwargs...) where {M}
    if M in _LAYOUT_METHODS
        error(
            "Layout method $(repr(M)) requires NetworkLayout to be loaded: `using NetworkLayout`.",
        )
    end
    error(
        "Unknown layout method $(repr(M)).\n" *
        "Available methods (require `using NetworkLayout`): " *
        join(map(repr, _LAYOUT_METHODS), ", ") *
        ".",
    )
end
