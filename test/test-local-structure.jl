# Tests for possible_local_structures (Proposition 2, Wang, Qin & Zhou 2023)
# and maximal_local_mag (Algorithm 1, same paper), the local-structure
# ingredients of PAGcauses (Wang, Tao, Qin & Zhou 2025).

@testitem "maximal_local_mag matches Fig. 1 of Wang, Qin & Zhou (2023) end to end" tags =
    [:unit, :local_structure] begin
    # Fig. 1(a); not a valid PAG
    fig1a = cgraph(
        "V1 o-o V2 + V5, V2 o-o V3 + V5, V5 o-o V3, V5 o-> V4, V1 o-> V4, V3 o-> V4";
        class = UNKNOWN,
    )
    node_vec, index, adj, mark =
        CausalStructures._pag_adj_marks(fig1a.backend.nodes, fig1a.edges)
    n = length(node_vec)
    c_mask = falses(n)
    c_mask[index[:V2]] = true
    CausalStructures._maximal_local_mag_marks!(adj, mark, n, index[:V1], c_mask)
    result = Set(
        (e.src, e.dst, e.src_end, e.dst_end) for
        e in CausalStructures._edges_from_marks(node_vec, adj, mark)
    )

    # Fig. 1(d) plus one further R8 step beyond what the figure illustrates.
    expected = cgraph(
        "V1 --> V4 + V5, V2 o-> V1, V2 --> V3 + V5, V5 --> V3 + V4, V3 --> V4";
        class = UNKNOWN,
    )
    expected_set = Set((e.src, e.dst, e.src_end, e.dst_end) for e in expected.edges)
    @test result == expected_set
end

@testitem "possible_local_structures rejects sets that aren't pairwise adjacent" tags =
    [:unit, :local_structure] begin
    # X has circles to A, B, Y; Y isn't adjacent to A or B, so any C
    # containing Y with A or B fails Prop. 2's completeness condition.
    mag = cgraph(
        bidirected(:A, :X),
        directed(:B, :X),
        bidirected(:A, :B),
        directed(:X, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    result = Set(Set.(possible_local_structures(pag, :X)))
    expected = Set([Set{Symbol}(), Set([:A]), Set([:B]), Set([:A, :B]), Set([:Y])])
    @test result == expected
    @test Set([:A, :Y]) ∉ result
    @test Set([:B, :Y]) ∉ result
end

@testitem "maximal_local_mag: empty local structure directs all circles away from x" tags =
    [:unit, :local_structure] begin
    mag = cgraph(
        bidirected(:A, :X),
        directed(:B, :X),
        bidirected(:A, :B),
        directed(:X, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    result = maximal_local_mag(pag, :X, Symbol[])
    edges_set = Set((e.src, e.dst, e.src_end, e.dst_end) for e in result.edges)
    expected = cgraph("A o-o B, X --> A + B + Y"; class = UNKNOWN)
    @test edges_set == Set((e.src, e.dst, e.src_end, e.dst_end) for e in expected.edges)
end

@testitem "maximal_local_mag: c = {A} orients X's arrow at the A end only" tags =
    [:unit, :local_structure] begin
    mag = cgraph(
        bidirected(:A, :X),
        directed(:B, :X),
        bidirected(:A, :B),
        directed(:X, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    result = maximal_local_mag(pag, :X, [:A])
    edges_set = Set((e.src, e.dst, e.src_end, e.dst_end) for e in result.edges)
    expected = cgraph("A --> B, A o-> X, X --> B + Y"; class = UNKNOWN)
    @test edges_set == Set((e.src, e.dst, e.src_end, e.dst_end) for e in expected.edges)
end

@testitem "_pa_mask returns parents, not children" tags = [:unit, :local_structure] begin
    mag = cgraph(directed(:P, :T); class = MAG)
    node_vec, index, adj, mark =
        CausalStructures._pag_adj_marks(mag.backend.nodes, mag.edges)
    n = length(node_vec)
    pa_t = CausalStructures._pa_mask(adj, mark, n, [index[:T]])
    @test [node_vec[i] for i = 1:n if pa_t[i]] == [:P]
    pa_p = CausalStructures._pa_mask(adj, mark, n, [index[:P]])
    @test isempty([node_vec[i] for i = 1:n if pa_p[i]])
end
