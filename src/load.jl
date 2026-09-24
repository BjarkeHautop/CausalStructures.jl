
using Preferences: Preferences, @load_preference
using Random: Random, randperm
using Statistics: Statistics

const _OPEN_DEFAULT::Bool = @load_preference("open", true)

const _PLOT_LAYOUT_PREFERENCE = @load_preference("plot_layout", nothing)

# Foundation: types, edges, construction, editing, validation, backend storage
include("core/defs.jl")
include("core/edges.jl")
include("core/constructors.jl")
include("core/graph-string.jl")
include("core/edit.jl")
include("core/validate.jl")
include("core/backend.jl")

# Graph query algorithms: traversal, separation, minimal separators
include("query/traversal.jl")
include("query/separation.jl")
include("query/buckets.jl")
include("query/definite-separation.jl")
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
include("transform/manipulate-pag.jl")
include("transform/local-structure.jl")
include("transform/enumerate-dags.jl")
include("transform/enumerate-mags.jl")

# Depends on identification/backdoor.jl (adjustment_set) and
# transform/background-knowledge.jl (apply_background_knowledge) above.
# possible-adjustment-sets.jl's possible_optimal_adjustment_sets calls
# possible_parent_sets, defined in possible-joint-parent-sets.jl.
include("identification/possible-joint-parent-sets.jl")
include("identification/possible-adjustment-sets.jl")
include("identification/pagcauses.jl")

# Depends on query/buckets.jl, query/definite-separation.jl, and
# transform/manipulate-pag.jl above.
include("identification/idp.jl")
include("identification/cidp.jl")

# I/O, generation, simulation, display, layout
include("io/utils.jl")
include("io/uniform-dag.jl")
include("io/layout.jl")

# Graph comparison metrics
include("metrics/utils.jl")
include("metrics/hamming.jl")
include("metrics/separation-distance.jl")
include("metrics/sc-metric.jl")
include("metrics/aid.jl")
