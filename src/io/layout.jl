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
`Vector{NTuple{2,Float64}}` in the same order as `nodes(cg)`.

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

dag = cgraph(directed(:A, :X), directed(:X, :Y); class = DAG)

layout(dag)                # :stress (the default)
layout(dag, :spring)
layout(dag, :spring; seed = 1405, iterations = 200)
```
"""
function layout(cg::CausalGraph, method::Symbol = _default_layout_method(); kwargs...)
    return _layout_impl(cg, Val(method); kwargs...)
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
