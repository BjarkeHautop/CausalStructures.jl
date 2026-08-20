@testitem "cgraph string: simple directed chain" tags = [:unit, :graph_string] begin
    cg = cgraph("A --> B --> C"; class = DAG)
    @test cg isa DAG
    @test Set(nodes(cg)) == Set([:A, :B, :C])
    @test has_edge(cg, :A, :B)
    @test has_edge(cg, :B, :C)
    @test length(cg.edges) == 2
end

@testitem "cgraph string: fan-out with +" tags = [:unit, :graph_string] begin
    cg = cgraph("A --> B + C"; class = DAG)
    @test Set(nodes(cg)) == Set([:A, :B, :C])
    @test has_edge(cg, :A, :B)
    @test has_edge(cg, :A, :C)
    @test length(cg.edges) == 2
end

@testitem "cgraph string: fan-in with +" tags = [:unit, :graph_string] begin
    cg = cgraph("A + B --> C"; class = DAG)
    @test has_edge(cg, :A, :C)
    @test has_edge(cg, :B, :C)
    @test length(cg.edges) == 2
end

@testitem "cgraph string: multiple statements separated by comma" tags =
    [:unit, :graph_string] begin
    cg = cgraph("A --> B, C --> D"; class = DAG)
    @test Set(nodes(cg)) == Set([:A, :B, :C, :D])
    @test has_edge(cg, :A, :B)
    @test has_edge(cg, :C, :D)
end

@testitem "cgraph string: fan-out on both sides of a marker (full cartesian product)" tags =
    [:unit, :graph_string] begin
    cg = cgraph("A + B o-> C + D"; class = UNKNOWN)
    @test Set(nodes(cg)) == Set([:A, :B, :C, :D])
    for src in (:A, :B), dst in (:C, :D)
        @test has_edge(cg, src, dst)
    end
    @test length(cg.edges) == 4
end

@testitem "cgraph string: mixed isolated node, fan-out, and chain across statements" tags =
    [:unit, :graph_string] begin
    cg = cgraph("A, B --> C + D,  E <-> D o-> F"; class = UNKNOWN)
    @test Set(nodes(cg)) == Set([:A, :B, :C, :D, :E, :F])
    @test isempty(neighbors(cg, :A))
    @test has_edge(cg, :B, :C)
    @test has_edge(cg, :B, :D)
    @test has_edge(cg, :E, :D)
    @test has_edge(cg, :D, :F)
    @test length(cg.edges) == 4
end

@testitem "cgraph string: reversed directed marker" tags = [:unit, :graph_string] begin
    cg = cgraph("A <-- B"; class = DAG)
    @test has_edge(cg, :B, :A)
    @test :A in children(cg, :B)
    @test :B in parents(cg, :A)
end

@testitem "cgraph string: undirected marker" tags = [:unit, :graph_string] begin
    cg = cgraph("A --- B"; class = UG)
    e = only(cg.edges)
    @test e.src_end == CausalStructures.Tail
    @test e.dst_end == CausalStructures.Tail
end

@testitem "cgraph string: bidirected marker" tags = [:unit, :graph_string] begin
    cg = cgraph("A <-> B"; class = ADMG)
    e = only(cg.edges)
    @test e.src_end == CausalStructures.Arrow
    @test e.dst_end == CausalStructures.Arrow
end

@testitem "cgraph string: reversed partial markers normalize like other reversed markers" tags =
    [:unit, :graph_string] begin
    fwd = cgraph("B o-> A"; class = UNKNOWN)
    rev = cgraph("A <-o B"; class = UNKNOWN)
    @test Set((e.src, e.dst, e.src_end, e.dst_end) for e in fwd.edges) ==
          Set((e.src, e.dst, e.src_end, e.dst_end) for e in rev.edges)

    fwd2 = cgraph("B o-- A"; class = UNKNOWN)
    rev2 = cgraph("A --o B"; class = UNKNOWN)
    @test Set((e.src, e.dst, e.src_end, e.dst_end) for e in fwd2.edges) ==
          Set((e.src, e.dst, e.src_end, e.dst_end) for e in rev2.edges)
end

@testitem "cgraph string: partial markers" tags = [:unit, :graph_string] begin
    cg = cgraph("A o-> B, B o-- C, C o-o D"; class = UNKNOWN)
    @test Set(nodes(cg)) == Set([:A, :B, :C, :D])
    kinds = Dict((e.src, e.dst) => (e.src_end, e.dst_end) for e in cg.edges)
    @test kinds[(:A, :B)] == (CausalStructures.Circle, CausalStructures.Arrow)
    @test kinds[(:B, :C)] == (CausalStructures.Circle, CausalStructures.Tail)
    @test kinds[(:C, :D)] == (CausalStructures.Circle, CausalStructures.Circle)
end

@testitem "cgraph string: isolated nodes" tags = [:unit, :graph_string] begin
    cg = cgraph("A --> B, C"; class = DAG)
    @test Set(nodes(cg)) == Set([:A, :B, :C])
    @test isempty(children(cg, :C))
    @test isempty(parents(cg, :C))
end

@testitem "cgraph string: matches equivalent programmatic construction" tags =
    [:unit, :graph_string] begin
    from_string = cgraph("A --> B + C, D o-> E"; class = UNKNOWN)
    from_edges = cgraph(
        directed(:A, :B),
        directed(:A, :C),
        partially_directed(:D, :E);
        class = UNKNOWN,
    )
    @test Set(nodes(from_string)) == Set(nodes(from_edges))
    @test Set((e.src, e.dst, e.src_end, e.dst_end) for e in from_string.edges) ==
          Set((e.src, e.dst, e.src_end, e.dst_end) for e in from_edges.edges)
end

@testitem "cgraph string: newline-separated statements" tags = [:unit, :graph_string] begin
    cg = cgraph(
        """
        A --> B
        B --> C
        """;
        class = DAG,
    )
    @test has_edge(cg, :A, :B)
    @test has_edge(cg, :B, :C)
end

@testitem "cgraph string: invalid graph for class throws" tags = [:unit, :graph_string] begin
    @test_throws Exception cgraph("A --> B --> A"; class = DAG)
end

@testitem "cgraph string: malformed syntax throws ArgumentError" tags =
    [:unit, :graph_string] begin
    @test_throws ArgumentError cgraph("A -->")
    @test_throws ArgumentError cgraph("A ## B")
end
