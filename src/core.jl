# Most algorithms are adapted from the caugi R/Rust package (caugi/).
# Functions not present in caugi are implemented directly from the cited papers.

using Preferences
using Random
using Statistics


const _OPEN_DEFAULT::Bool = @load_preference("open", true)

const _PLOT_LAYOUT_DEFAULT::Symbol = Symbol(@load_preference("plot_layout", "circle"))
const _PLOT_NODE_COLOR_DEFAULT = @load_preference("plot_node_color", "white")
const _PLOT_NODE_STROKECOLOR_DEFAULT = @load_preference("plot_node_strokecolor", "black")
const _PLOT_NODE_STROKEWIDTH_DEFAULT = @load_preference("plot_node_strokewidth", 2.0)
const _PLOT_EDGE_COLOR_DEFAULT = @load_preference("plot_edge_color", "black")
const _PLOT_LINEWIDTH_DEFAULT = @load_preference("plot_linewidth", 1.5)

# Foundation: types, edges, construction, mutation, validation, backend storage
include("core/defs.jl")
include("core/edges.jl")
include("core/constructors.jl")
include("core/mutate.jl")
include("core/validate.jl")
include("core/backend.jl")

# Graph query algorithms: traversal, separation, minimal separators
include("query/traversal.jl")
include("query/separation.jl")
include("query/minimal-separator.jl")

# Causal identification: adjustment sets, frontdoor, conditioning
include("identification/adjustment-admg.jl")
include("identification/adjustment-mag.jl")
include("identification/adjustment-pdag.jl")
include("identification/backdoor.jl")
include("identification/frontdoor.jl")
include("identification/condition-marginalize.jl")

# Graph transformations: skeleton, latent projection, PDAG ops, DAG enumeration
include("transform/skeleton-subgraph.jl")
include("transform/latent.jl")
include("transform/pdag.jl")
include("transform/enumerate-dags.jl")

# I/O, generation, simulation, display, layout
include("io/utils.jl")
include("io/layout.jl")
