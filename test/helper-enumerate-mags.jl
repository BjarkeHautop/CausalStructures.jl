# Helpers for enumerate_mags / count_mags tests.

# Orientation-independent structural signature of a MAG (or any graph), so two
# graphs compare equal regardless of how each edge's endpoints are ordered.
function mag_sig(m)
    return Set(
        (
            min(e.src, e.dst),
            max(e.src, e.dst),
            e.src <= e.dst ? e.src_end : e.dst_end,
            e.src <= e.dst ? e.dst_end : e.src_end,
        ) for e in m.edges
    )
end

# Signature of the PAG that `m` belongs to (its Markov equivalence class).
class_of(m) = mag_sig(CausalGraphInterface.mag_to_pag(m))
