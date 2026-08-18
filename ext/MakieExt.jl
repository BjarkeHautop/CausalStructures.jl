module MakieExt

using CausalStructures
import Makie
using Makie: Point2f

include("MakieExt/layout.jl")
include("MakieExt/nodes.jl")
include("MakieExt/routing.jl")
include("MakieExt/draw.jl")

end
