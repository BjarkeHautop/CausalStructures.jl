# Convert layout output (Vector of NTuple) to the Point2f positions
# used by Makie drawing primitives.
function _positions(cg::CausalGraph, method::Symbol, kwargs)
    tuples = CausalGraphInterface.layout(cg, method; kwargs...)
    return [Point2f(x, y) for (x, y) in tuples]
end

# Accept a pre-computed positions vector (e.g. from layout() after manual tweaks).
function _positions(cg::CausalGraph, positions::AbstractVector, ::Any)
    n = length(cg.backend.nodes)
    length(positions) == n ||
        error("positions length ($(length(positions))) must match node count ($n)")
    return [Point2f(p[1], p[2]) for p in positions]
end
