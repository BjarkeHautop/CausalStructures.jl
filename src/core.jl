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

include("core/00-defs.jl")
include("core/05-edges.jl")
include("core/06-constructors.jl")
include("core/07-mutate.jl")
include("core/10-validate.jl")
include("core/20-backend.jl")
include("core/30-traversal.jl")
include("core/31-separation.jl")
include("core/32-minimal-separator.jl")
include("core/33-adjustment.jl")
include("core/40-transforms.jl")
include("core/50-utils.jl")
include("core/60-layout.jl")
