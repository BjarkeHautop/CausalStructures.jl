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

Compute 2-D node positions for `cg`, for use in plotting.

| `method`      | Algorithm                           | Requires                     |
|---------------|--------------------------------------|-------------------------------|
| `:spring`     | Fruchterman-Reingold force-directed  | `NetworkLayout`         |
| `:stress`     | Stress majorization                  | `NetworkLayout`         |
| `:sfdp`       | Scalable Force-Directed Placement    | `NetworkLayout`         |
| `:spectral`   | Spectral layout                      | `NetworkLayout`         |
| `:shell`      | Concentric shells                    | `NetworkLayout`         |
| `:squaregrid` | Square grid                          | `NetworkLayout`         |
| `:sugiyama`   | Layered/hierarchical (`DAG` only)    | `Sugiyama`               |

The default is `:stress`, except for a `DAG` with Sugiyama loaded, where it
is `:sugiyama`. Extra `kwargs` are forwarded to the underlying
algorithm.

# Arguments
- `cg::CausalGraph`: the graph to lay out.
- `method::Symbol = _default_layout_method(cg)`: the layout algorithm to use, one of
  `:spring`, `:stress`, `:sfdp`, `:spectral`, `:shell`, `:squaregrid`, or `:sugiyama`.

# Keywords
- `kwargs...`: forwarded to the underlying algorithm (e.g. `seed`, `iterations`).

# Returns
A `Dict{Symbol,NTuple{2,Float64}}` mapping each node name to its `(x, y)` position.

# Examples

```jldoctest; filter = r"entries:(\\n.*)*" => "entries:"
julia> using NetworkLayout

julia> dag = DAG("A --> X, A --> Y, X --> Y");

julia> layout(dag, :spring; iterations = 100)
Dict{Symbol, Tuple{Float64, Float64}} with 3 entries:
```

```julia
using NetworkLayout

dag = DAG("A ---> X, A ---> Y, X ---> Y")

layout(dag)
layout(dag, :spring)
layout(dag, :spring; seed = 1405, iterations = 200)

positions = layout(dag, :spring)
positions[:A] = (0.0, 2.0)

using CairoMakie
plot(dag; layout = positions)
```
"""
function layout(cg::CausalGraph, method::Symbol = _default_layout_method(cg); kwargs...)
    # Each method is matched against a literal so that every `_layout_impl` call is resolved
    # at compile time, which `juliac --trim` requires, also when `method` is only known at
    # runtime (as the default is).
    method === :spring && return _positions(cg, _layout_impl(cg, Val(:spring); kwargs...))
    method === :stress && return _positions(cg, _layout_impl(cg, Val(:stress); kwargs...))
    method === :sfdp && return _positions(cg, _layout_impl(cg, Val(:sfdp); kwargs...))
    method === :spectral &&
        return _positions(cg, _layout_impl(cg, Val(:spectral); kwargs...))
    method === :shell && return _positions(cg, _layout_impl(cg, Val(:shell); kwargs...))
    method === :squaregrid &&
        return _positions(cg, _layout_impl(cg, Val(:squaregrid); kwargs...))
    method === :sugiyama &&
        return _positions(cg, _layout_impl(cg, Val(:sugiyama); kwargs...))
    _unknown_layout_method(method)
end

_positions(cg::CausalGraph, coords) = Dict{Symbol,NTuple{2,Float64}}(
    nd => (Float64(p[1]), Float64(p[2])) for (nd, p) in zip(cg.backend.nodes, coords)
)

const _LAYOUT_METHODS_LIST = join(map(repr, _LAYOUT_METHODS), ", ")

function _unknown_layout_method(method::Symbol)
    error(
        "Unknown layout method :" *
        String(method) *
        ".\n" *
        "Available methods (require `using NetworkLayout` or, for :sugiyama, " *
        "`using Sugiyama`): " *
        _LAYOUT_METHODS_LIST *
        ".",
    )
end

# Fallback for any method not handled by a loaded extension.
function _layout_impl(::CausalGraph, ::Val{M}; kwargs...) where {M}
    if M === :sugiyama
        error("Layout method :sugiyama requires Sugiyama to be loaded: `using Sugiyama`.")
    end
    if M in _LAYOUT_METHODS
        error(
            "Layout method :" *
            String(M) *
            " requires NetworkLayout to be loaded: `using NetworkLayout`.",
        )
    end
    _unknown_layout_method(M)
end

function _layout_edge_paths_impl(::CausalGraph, ::Val{M}; kwargs...) where {M}
    return nothing
end
