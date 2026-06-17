using CausalStructures
using Test

@testitem "print: directed edge (-->)" tags = [:unit] begin
    cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    @test contains(
        sprint(show, cg),
        """DAG with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A --> B, B --> C\n""",
    )
end

@testitem "print: undirected edge (---)" tags = [:unit] begin
    cg = cgraph(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test contains(
        sprint(show, cg),
        """UG with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A --- B, B --- C\n""",
    )
end

@testitem "print: bidirected edge (<->)" tags = [:unit] begin
    cg = cgraph(bidirected(:A, :B), bidirected(:B, :C); class = ADMG)
    @test contains(
        sprint(show, cg),
        """ADMG with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A <-> B, B <-> C\n""",
    )
end

@testitem "print: partially_directed edge (o->)" tags = [:unit] begin
    cg = cgraph(partially_directed(:A, :B), partially_directed(:B, :C); class = UNKNOWN)
    @test contains(
        sprint(show, cg),
        """UNKNOWN with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A o-> B, B o-> C\n""",
    )
end

@testitem "print: partially_undirected edge (o--)" tags = [:unit] begin
    cg = cgraph(partially_undirected(:A, :B), partially_undirected(:B, :C); class = UNKNOWN)
    @test contains(
        sprint(show, cg),
        """UNKNOWN with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A o-- B, B o-- C\n""",
    )
end

@testitem "print: partial edge (o-o)" tags = [:unit] begin
    cg = cgraph(partial(:A, :B), partial(:B, :C); class = UNKNOWN)
    @test contains(
        sprint(show, cg),
        """UNKNOWN with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A o-o B, B o-o C\n""",
    )
end

@testitem "print: no edges" tags = [:unit] begin
    cg = cgraph(node(:A), node(:B); class = DAG)
    @test contains(
        sprint(show, cg),
        """DAG with 2 nodes and 0 edges:\n  nodes: A, B\n  edges:\n    (none)\n""",
    )
end

@testitem "print: singular node/edge labels" tags = [:unit] begin
    cg = cgraph(directed(:A, :B); class = DAG)
    @test contains(sprint(show, cg), "DAG with 2 nodes and 1 edge:")
end
