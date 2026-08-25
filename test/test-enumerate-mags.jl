@testsnippet MagSig begin
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
    class_of(m) = mag_sig(CausalStructures.mag_to_pag(m))
end

# ── Basic counts ────────────────────────────────────────────────────────────────

@testitem "enumerate_mags: all-circle 2-path has 8 members" tags = [:unit, :enumerate_mags] begin
    pag = PAG(partial(:A, :B), partial(:B, :C))
    @test length(enumerate_mags(pag)) == 8
end

@testitem "enumerate_mags: collider PAG has 4 members" tags = [:unit, :enumerate_mags] begin
    pag = PAG(partially_directed(:A, :B), partially_directed(:C, :B))
    @test length(enumerate_mags(pag)) == 4
end

@testitem "enumerate_mags: an edgeless PAG has a single member" tags =
    [:unit, :enumerate_mags] begin
    # No adjacencies => the empty MAG is the only graph in the class.
    pag = PAG(node(:A), node(:B))
    @test length(enumerate_mags(pag)) == 1
end

# ── Selection bias (--- and o-- edges) ──────────────────────────────────────────

@testitem "enumerate_mags: undirected 4-cycle PAG has a single member" tags =
    [:unit, :enumerate_mags] begin
    # A --- B --- C --- D --- A is a closed selection-bias PAG; only the 4-cycle
    # itself is in the class.
    mag =
        MAG(undirected(:A, :B), undirected(:B, :C), undirected(:C, :D), undirected(:A, :D))
    pag = mag_to_pag(mag)
    mags = enumerate_mags(pag)
    @test length(mags) == 1
    @test all(is_mag, mags)
end

@testitem "enumerate_mags: handles a PAG with an o-- edge" setup=[MagSig] tags =
    [:unit, :enumerate_mags] begin
    # The pendant B --> E surfaces as E o-- B; both resolutions of the circle at E
    # (the directed edge and the undirected edge) are valid members of the class.
    mag = MAG(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:A, :D),
        directed(:B, :E),
    )
    pag = mag_to_pag(mag)
    mags = enumerate_mags(pag)
    @test all(is_mag, mags)
    @test all(m -> class_of(m) == mag_sig(pag), mags)
    @test any(m -> mag_sig(m) == mag_sig(mag), mags)   # the originating MAG is present
end

# ── Every member is in the class; the class is closed ───────────────────────────

@testitem "enumerate_mags: every member maps back to the PAG" setup=[MagSig] tags =
    [:unit, :enumerate_mags] begin
    mag = MAG(directed(:A, :C), directed(:B, :C), directed(:C, :D))
    pag = mag_to_pag(mag)
    target = mag_sig(pag)
    for m in enumerate_mags(pag)
        @test class_of(m) == target
    end
end

@testitem "enumerate_mags: contains the originating MAG" setup=[MagSig] tags =
    [:unit, :enumerate_mags] begin
    mag = MAG(bidirected(:D, :A), bidirected(:A, :B), directed(:A, :C), directed(:B, :C))
    pag = mag_to_pag(mag)
    @test any(m -> mag_sig(m) == mag_sig(mag), enumerate_mags(pag))
end

@testitem "enumerate_mags: contains the mag_from_pag representative" setup=[MagSig] tags =
    [:unit, :enumerate_mags] begin
    pag = PAG(partial(:A, :B), partial(:B, :C))
    rep = mag_from_pag(pag)
    @test any(m -> mag_sig(m) == mag_sig(rep), enumerate_mags(pag))
end

# ── Members are distinct ─────────────────────────────────────────────────────────

@testitem "enumerate_mags: members are pairwise distinct" setup=[MagSig] tags =
    [:unit, :enumerate_mags] begin
    pag = PAG(partial(:A, :B), partial(:B, :C))
    mags = enumerate_mags(pag)
    sigs = Set(mag_sig(m) for m in mags)
    @test length(sigs) == length(mags)
end

# ── Threaded helper ────────

@testitem "_enumerate_mags_threaded matches the sequential result" setup = [MagSig] tags =
    [:unit, :enumerate_mags] begin
    pag = PAG(partial(:A, :B), partial(:B, :C), partial(:C, :D))
    B = pag.backend
    n = length(B.nodes)

    adj = falses(n, n)
    mark = fill(CausalStructures.Circle, n, n)
    for e in pag.edges
        i, j = B.index[e.src], B.index[e.dst]
        adj[i, j] = adj[j, i] = true
        mark[j, i] = e.src_end
        mark[i, j] = e.dst_end
    end
    circle_pos = [
        (i, j) for i = 1:n for j = 1:n if adj[i, j] && mark[i, j] == CausalStructures.Circle
    ]
    total = 2^length(circle_pos)
    target = CausalStructures._pag_signature(pag.edges)
    node_set = Set(B.nodes)

    threaded = CausalStructures._enumerate_mags_threaded(
        circle_pos,
        mark,
        adj,
        B.nodes,
        node_set,
        target,
        total,
    )
    sequential = CausalStructures._enumerate_mags_range(
        circle_pos,
        mark,
        adj,
        B.nodes,
        node_set,
        target,
        0,
        total - 1,
    )

    @test Set(mag_sig(m) for m in threaded) == Set(mag_sig(m) for m in sequential)
    @test length(threaded) == length(enumerate_mags(pag))
end
