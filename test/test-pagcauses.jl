# Tests for pagcauses (Algorithm 1, Wang, Tao, Qin & Zhou 2025), the
# block-set-search capstone built on possible_local_structures/
# maximal_local_mag (Wang, Qin & Zhou 2023).

@testsnippet PagcausesBaseline begin
    # enumerate_mags(::PAG) can include selection-variable (undirected-edge) MAGs; PAGcauses assumes none.
    classical_mags(pag) =
        [m for m in enumerate_mags(pag) if !any(CausalStructures.is_undirected, m.edges)]

    # Expand a MAG into a concrete DAG (each bidirected edge -> a fresh latent common cause).
    function expand_latents(mag)
        edges = CausalEdge[]
        li = 0
        for e in mag.edges
            if e.src_end == CausalStructures.Tail && e.dst_end == CausalStructures.Arrow
                push!(edges, directed(e.src, e.dst))
            elseif e.src_end == CausalStructures.Arrow && e.dst_end == CausalStructures.Tail
                push!(edges, directed(e.dst, e.src))
            else   # e.src_end == e.dst_end == Arrow: bidirected
                li += 1
                l = Symbol("L", li)
                push!(edges, directed(l, e.src), directed(l, e.dst))
            end
        end
        return cgraph(edges...; class = DAG)
    end

    # The Sec. 3.4 brute-force baseline: D-SEP(X,Y,M_X) per MAG, kept if disjoint from De(X,M) and not containing Y.
    function naive_dsep_sets(pag, x, y)
        sets = Set{Vector{Symbol}}()
        for mag in classical_mags(pag)
            chs = children(mag, x)
            mag_x = isempty(chs) ? mag : remove_edges(mag, [directed(x, c) for c in chs]...)
            w = possible_d_sep(mag_x, x, y)
            y in w && continue
            isempty(intersect(w, descendants(mag, x))) || continue
            push!(sets, sort(w))
        end
        return sets
    end
end

@testitem "pagcauses: X not a possible ancestor of Y returns no causal effect" tags =
    [:unit] begin
    mag = cgraph(
        directed(:B, :X),
        bidirected(:A, :X),
        directed(:A, :Y),
        directed(:X, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)   # X --> Y is definite, so Y is never an ancestor of X
    @test pagcauses(pag, :Y, :X) == Vector{Symbol}[]
end

@testitem "pagcauses: identifiable directly returns the single backdoor set (Proposition 1)" tags =
    [:unit] begin
    mag = cgraph(
        directed(:B, :X),
        bidirected(:A, :X),
        directed(:A, :Y),
        directed(:X, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test pagcauses(pag, :X, :Y) == [sort(backdoor_set(pag, :X, :Y))]
end

@testitem "pagcauses matches Fig. 2 of Wang, Tao, Qin & Zhou (2025) end to end" tags =
    [:unit] begin
    pag = cgraph(
        "X o-> Y, X o-> C, X o-> A, Y o-o C, C o-o A, B o-> C, B o-> Y, B o-> A";
        class = PAG,
    )
    result = Set(Set.(pagcauses(pag, :X, :Y)))

    # {}, {A, B}: local structure C = {A} (Fig. 2(c)/2(d)). {C}, {B, C}, {A, B, C}: C = {A, C}.
    expected =
        Set([Set{Symbol}(), Set([:A, :B]), Set([:C]), Set([:B, :C]), Set([:A, :B, :C])])
    @test result == expected
end

@testitem "pagcauses matches brute-force MAG enumeration (Theorem 4) when unidentifiable" setup =
    [PagcausesBaseline] tags = [:unit] begin
    # Only holds pre-Proposition-1: that early exit collapses equivalent sets to one representative.
    graphs = [
        mag_to_pag(
            cgraph(
                bidirected(:A, :X),
                directed(:B, :X),
                bidirected(:A, :B),
                directed(:X, :Y);
                class = MAG,
            ),
        ),
        cgraph(
            "X o-> Y, X o-> C, X o-> A, Y o-o C, C o-o A, B o-> C, B o-> Y, B o-> A";
            class = PAG,
        ),
    ]
    for pag in graphs
        @test backdoor_set(pag, :X, :Y) === nothing   # confirms this exercises the search, not Prop. 1
        @test naive_dsep_sets(pag, :X, :Y) == Set(sort.(pagcauses(pag, :X, :Y)))
    end
end

@testitem "pagcauses: every returned set is sound (a real Definition 1 adjustment set)" setup =
    [PagcausesBaseline] tags = [:unit] begin
    graphs = [
        mag_to_pag(
            cgraph(
                directed(:B, :X),
                bidirected(:A, :X),
                directed(:A, :Y),
                directed(:X, :Y);
                class = MAG,
            ),
        ),
        mag_to_pag(
            cgraph(
                bidirected(:A, :X),
                directed(:B, :X),
                bidirected(:A, :B),
                directed(:X, :Y);
                class = MAG,
            ),
        ),
        cgraph(
            "X o-> Y, X o-> C, X o-> A, Y o-o C, C o-o A, B o-> C, B o-> Y, B o-> A";
            class = PAG,
        ),
    ]
    for pag in graphs
        mags = classical_mags(pag)
        for w in pagcauses(pag, :X, :Y)
            @test any(is_valid_adjustment(expand_latents(mag), :X, :Y, w) for mag in mags)
        end
    end
end

@testitem "pagcauses: W-bar is computed on M_X, excluding X's directed-out neighbors" tags =
    [:unit] begin
    # Regression test: for W = empty, W-bar must be {A}, not {A, C, Y}.
    pag = cgraph(
        "X o-> Y, X o-> C, X o-> A, Y o-o C, C o-o A, B o-> C, B o-> Y, B o-> A";
        class = PAG,
    )
    node_vec, index, adj, mark =
        CausalStructures._pag_adj_marks(pag.backend.nodes, pag.edges)
    n = length(node_vec)
    xi, yi = index[:X], index[:Y]
    c_mask = falses(n)
    c_mask[index[:A]] = true
    CausalStructures._maximal_local_mag_marks!(adj, mark, n, xi, c_mask)

    wbar = CausalStructures._w_bar_mask(adj, mark, n, xi, yi, falses(n))
    @test Set(node_vec[v] for v = 1:n if wbar[v]) == Set([:A])
end
