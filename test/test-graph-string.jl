@testitem "graph string: simple directed chain" tags = [:unit, :graph_string] begin
    cg = DAG("A --> B --> C")
    @test cg isa DAG
    @test Set(nodes(cg)) == Set([:A, :B, :C])
    @test has_edge(cg, :A, :B)
    @test has_edge(cg, :B, :C)
    @test length(cg.edges) == 2
end

@testitem "graph string: fan-out with +" tags = [:unit, :graph_string] begin
    cg = DAG("A --> B + C")
    @test Set(nodes(cg)) == Set([:A, :B, :C])
    @test has_edge(cg, :A, :B)
    @test has_edge(cg, :A, :C)
    @test length(cg.edges) == 2
end

@testitem "graph string: fan-in with +" tags = [:unit, :graph_string] begin
    cg = DAG("A + B --> C")
    @test has_edge(cg, :A, :C)
    @test has_edge(cg, :B, :C)
    @test length(cg.edges) == 2
end

@testitem "graph string: multiple statements separated by comma" tags =
    [:unit, :graph_string] begin
    cg = DAG("A --> B, C --> D")
    @test Set(nodes(cg)) == Set([:A, :B, :C, :D])
    @test has_edge(cg, :A, :B)
    @test has_edge(cg, :C, :D)
end

@testitem "graph string: fan-out on both sides of a marker (full cartesian product)" tags =
    [:unit, :graph_string] begin
    cg = UNKNOWN("A + B o-> C + D")
    @test Set(nodes(cg)) == Set([:A, :B, :C, :D])
    for src in (:A, :B), dst in (:C, :D)
        @test has_edge(cg, src, dst)
    end
    @test length(cg.edges) == 4
end

@testitem "graph string: mixed isolated node, fan-out, and chain across statements" tags =
    [:unit, :graph_string] begin
    cg = UNKNOWN("A, B --> C + D,  E <-> D o-> F")
    @test Set(nodes(cg)) == Set([:A, :B, :C, :D, :E, :F])
    @test isempty(neighbors(cg, :A))
    @test has_edge(cg, :B, :C)
    @test has_edge(cg, :B, :D)
    @test has_edge(cg, :E, :D)
    @test has_edge(cg, :D, :F)
    @test length(cg.edges) == 4
end

@testitem "graph string: reversed directed marker" tags = [:unit, :graph_string] begin
    cg = DAG("A <-- B")
    @test has_edge(cg, :B, :A)
    @test :A in children(cg, :B)
    @test :B in parents(cg, :A)
end

@testitem "graph string: undirected marker" tags = [:unit, :graph_string] begin
    cg = UG("A --- B")
    e = only(cg.edges)
    @test e.src_end == CausalStructures.Tail
    @test e.dst_end == CausalStructures.Tail
end

@testitem "graph string: bidirected marker" tags = [:unit, :graph_string] begin
    cg = ADMG("A <-> B")
    e = only(cg.edges)
    @test e.src_end == CausalStructures.Arrow
    @test e.dst_end == CausalStructures.Arrow
end

@testitem "graph string: reversed partial markers normalize like other reversed markers" tags =
    [:unit, :graph_string] begin
    fwd = UNKNOWN("B o-> A")
    rev = UNKNOWN("A <-o B")
    @test Set((e.src, e.dst, e.src_end, e.dst_end) for e in fwd.edges) ==
          Set((e.src, e.dst, e.src_end, e.dst_end) for e in rev.edges)

    fwd2 = UNKNOWN("B o-- A")
    rev2 = UNKNOWN("A --o B")
    @test Set((e.src, e.dst, e.src_end, e.dst_end) for e in fwd2.edges) ==
          Set((e.src, e.dst, e.src_end, e.dst_end) for e in rev2.edges)
end

@testitem "graph string: partial markers" tags = [:unit, :graph_string] begin
    cg = UNKNOWN("A o-> B, B o-- C, C o-o D")
    @test Set(nodes(cg)) == Set([:A, :B, :C, :D])
    kinds = Dict((e.src, e.dst) => (e.src_end, e.dst_end) for e in cg.edges)
    @test kinds[(:A, :B)] == (CausalStructures.Circle, CausalStructures.Arrow)
    @test kinds[(:B, :C)] == (CausalStructures.Circle, CausalStructures.Tail)
    @test kinds[(:C, :D)] == (CausalStructures.Circle, CausalStructures.Circle)
end

@testitem "graph string: isolated nodes" tags = [:unit, :graph_string] begin
    cg = DAG("A --> B, C")
    @test Set(nodes(cg)) == Set([:A, :B, :C])
    @test isempty(children(cg, :C))
    @test isempty(parents(cg, :C))
end

@testitem "graph string: matches equivalent programmatic construction" tags =
    [:unit, :graph_string] begin
    from_string = UNKNOWN("A --> B + C, D o-> E")
    from_edges = UNKNOWN(directed(:A, :B), directed(:A, :C), partially_directed(:D, :E))
    @test Set(nodes(from_string)) == Set(nodes(from_edges))
    @test Set((e.src, e.dst, e.src_end, e.dst_end) for e in from_string.edges) ==
          Set((e.src, e.dst, e.src_end, e.dst_end) for e in from_edges.edges)
end

@testitem "graph string: newline-separated statements" tags = [:unit, :graph_string] begin
    cg = DAG("""
             A --> B
             B --> C
             """)
    @test has_edge(cg, :A, :B)
    @test has_edge(cg, :B, :C)
end

@testitem "graph string: invalid graph for class throws" tags = [:unit, :graph_string] begin
    @test_throws Exception DAG("A --> B --> A")
end

@testitem "graph string: malformed syntax throws ArgumentError" tags =
    [:unit, :graph_string] begin
    @test_throws ArgumentError DAG("A -->")
    @test_throws ArgumentError DAG("A ## B")
end
