# Layout coordinates for graph visualisation.
#
# `layout` is the public entry point. The `:spring`/`:stress`/`:sfdp`/
# `:spectral`/`:shell`/`:squaregrid` methods are provided by the
# NetworkLayoutExt extension and require `using NetworkLayout` before
# calling. `:sugiyama` is provided by SugiyamaExt and requires
# `using Sugiyama`.

const _LAYOUT_METHODS = (:spring, :stress, :sfdp, :spectral, :shell, :squaregrid, :sugiyama)

_sugiyama_loaded() = Base.get_extension(@__MODULE__, :SugiyamaExt) !== nothing

function _default_layout_method(cg::CausalGraph)
    _PLOT_LAYOUT_PREFERENCE !== nothing && return Symbol(_PLOT_LAYOUT_PREFERENCE)
    cg isa DAG && _sugiyama_loaded() && return :sugiyama
    return :stress
end

"""
    layout(cg::CausalGraph, method::Symbol = :stress; kwargs...)

Compute 2-D node positions for `cg` and return them as a
`Dict{Symbol,NTuple{2,Float64}}` keyed by node name.

| `method`      | Algorithm                           | Requires                     |
|---------------|--------------------------------------|-------------------------------|
| `:spring`     | Fruchterman-Reingold force-directed  | `using NetworkLayout`         |
| `:stress`     | Stress majorization                  | `using NetworkLayout`         |
| `:sfdp`       | Scalable Force-Directed Placement    | `using NetworkLayout`         |
| `:spectral`   | Spectral layout                      | `using NetworkLayout`         |
| `:shell`      | Concentric shells                    | `using NetworkLayout`         |
| `:squaregrid` | Square grid                          | `using NetworkLayout`         |
| `:sugiyama`   | Layered/hierarchical (`DAG` only)    | `using Sugiyama`               |

The default is `:stress`, except for a `DAG` with Sugiyama loaded, where it
is `:sugiyama`. Extra `kwargs` are forwarded to the underlying
algorithm.

## Examples

```julia
using CausalStructures, NetworkLayout

dag = DAG(directed(:A, :X), directed(:X, :Y))

layout(dag)                # :stress (the default without Sugiyama loaded)
layout(dag, :spring)
layout(dag, :spring; seed = 1405, iterations = 200)

positions = layout(dag, :spring)
positions[:A] = (0.0, 2.0)
plot(dag; layout = positions)
```
"""
function layout(cg::CausalGraph, method::Symbol = _default_layout_method(cg); kwargs...)
    coords = _layout_impl(cg, Val(method); kwargs...)
    return Dict{Symbol,NTuple{2,Float64}}(
        nd => (Float64(p[1]), Float64(p[2])) for (nd, p) in zip(cg.backend.nodes, coords)
    )
end

# Fallback for any method not handled by a loaded extension.
function _layout_impl(::CausalGraph, ::Val{M}; kwargs...) where {M}
    if M === :sugiyama
        error("Layout method :sugiyama requires Sugiyama to be loaded: `using Sugiyama`.")
    end
    if M in _LAYOUT_METHODS
        error(
            "Layout method $(repr(M)) requires NetworkLayout to be loaded: `using NetworkLayout`.",
        )
    end
    error(
        "Unknown layout method $(repr(M)).\n" *
        "Available methods (require `using NetworkLayout` or, for :sugiyama, " *
        "`using Sugiyama`): " *
        join(map(repr, _LAYOUT_METHODS), ", ") *
        ".",
    )
end

function _layout_edge_paths_impl(::CausalGraph, ::Val{M}; kwargs...) where {M}
    return nothing
end
