
using Preferences
using Random
using Statistics

const _OPEN_DEFAULT::Bool = @load_preference("open", true)

const _PLOT_LAYOUT_PREFERENCE = @load_preference("plot_layout", nothing)
const _PLOT_NODE_COLOR_DEFAULT = @load_preference("plot_node_color", "white")
const _PLOT_NODE_STROKECOLOR_DEFAULT = @load_preference("plot_node_strokecolor", "black")
const _PLOT_NODE_STROKEWIDTH_DEFAULT = @load_preference("plot_node_strokewidth", 2.0)
const _PLOT_EDGE_COLOR_DEFAULT = @load_preference("plot_edge_color", "black")
const _PLOT_LINEWIDTH_DEFAULT = @load_preference("plot_linewidth", 1.5)
const _PLOT_LABEL_COLOR_DEFAULT = @load_preference("plot_label_color", "black")
const _PLOT_LABEL_FONTSIZE_DEFAULT = @load_preference("plot_label_fontsize", 14.0)
const _PLOT_LABEL_FONT_DEFAULT::Symbol =
    Symbol(@load_preference("plot_label_font", "regular"))
const _PLOT_NODE_PADDING_DEFAULT = @load_preference("plot_node_padding", 10.0)
const _PLOT_EDGE_ARROW_FILL_DEFAULT = @load_preference("plot_edge_arrow_fill", nothing)
const _PLOT_FIG_SIZE_DEFAULT =
    Tuple(Float64.(@load_preference("plot_fig_size", [600.0, 450.0])))

# Foundation: types, edges, construction, mutation, validation, backend storage
include("core/defs.jl")
include("core/edges.jl")
include("core/constructors.jl")
include("core/graph-string.jl")
include("core/mutate.jl")
include("core/validate.jl")
include("core/backend.jl")

# Graph query algorithms: traversal, separation, minimal separators
include("query/traversal.jl")
include("query/separation.jl")
include("query/minimal-separator.jl")
include("query/possible-d-sep.jl")

# Causal identification: adjustment sets, frontdoor, conditioning
include("identification/estimand.jl")
include("identification/enumerate-subsets.jl")
include("identification/adjustment-admg.jl")
include("identification/adjustment-mag.jl")
include("identification/adjustment-pag.jl")
include("identification/adjustment-pdag.jl")
include("identification/backdoor.jl")
include("identification/backdoor-pdag.jl")
include("identification/backdoor-mag.jl")
include("identification/backdoor-pag.jl")
include("identification/frontdoor.jl")
include("identification/id.jl")
include("identification/iv.jl")
include("identification/condition-marginalize.jl")

# Graph transformations: skeleton, latent projection, PDAG ops, DAG enumeration
include("transform/skeleton-subgraph.jl")
include("transform/latent.jl")
include("transform/pdag.jl")
include("transform/background-knowledge.jl")
include("transform/mag.jl")
include("transform/local-structure.jl")
include("transform/enumerate-dags.jl")
include("transform/enumerate-mags.jl")

# Depends on identification/backdoor.jl (adjustment_set) and
# transform/background-knowledge.jl (apply_background_knowledge) above.
include("identification/possible-adjustment-sets.jl")
include("identification/possible-joint-parent-sets.jl")
include("identification/pagcauses.jl")

# I/O, generation, simulation, display, layout
include("io/utils.jl")
include("io/uniform-dag.jl")
include("io/layout.jl")
