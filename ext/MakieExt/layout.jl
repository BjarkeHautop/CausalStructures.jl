# Convert layout output (Vector of NTuple) to the Point2f positions
# used by Makie drawing primitives.
function _positions(cg::CausalGraph, method::Symbol, kwargs)
    tuples = CausalGraphInterface.layout(cg, method; kwargs...)
    return [Point2f(x, y) for (x, y) in tuples]
end
