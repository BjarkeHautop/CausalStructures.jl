using Preferences
using Random
using Statistics

# When true, traversal functions use the open definition: the queried
# node itself is not included in the result. Set to false via
#   set_preferences!(CausalGraphInterface, "open" => false)
# then restart Julia to use the closed definition by default.
const _OPEN_DEFAULT::Bool = @load_preference("open", true)

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
include("core/60-plot.jl")
