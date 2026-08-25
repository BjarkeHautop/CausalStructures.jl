@testitem "print: directed edge (-->)" tags = [:unit, :print] begin
    cg = DAG(directed(:A, :B), directed(:B, :C))
    @test contains(
        sprint(show, cg),
        """DAG with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A --> B, B --> C\n""",
    )
end

@testitem "print: undirected edge (---)" tags = [:unit, :print] begin
    cg = UG(undirected(:A, :B), undirected(:B, :C))
    @test contains(
        sprint(show, cg),
        """UG with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A --- B, B --- C\n""",
    )
end

@testitem "print: bidirected edge (<->)" tags = [:unit, :print] begin
    cg = ADMG(bidirected(:A, :B), bidirected(:B, :C))
    @test contains(
        sprint(show, cg),
        """ADMG with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A <-> B, B <-> C\n""",
    )
end

@testitem "print: partially_directed edge (o->)" tags = [:unit, :print] begin
    cg = UNKNOWN(partially_directed(:A, :B), partially_directed(:B, :C))
    @test contains(
        sprint(show, cg),
        """UNKNOWN with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A o-> B, B o-> C\n""",
    )
end

@testitem "print: partially_undirected edge (o--)" tags = [:unit, :print] begin
    cg = UNKNOWN(partially_undirected(:A, :B), partially_undirected(:B, :C))
    @test contains(
        sprint(show, cg),
        """UNKNOWN with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A o-- B, B o-- C\n""",
    )
end

@testitem "print: partial edge (o-o)" tags = [:unit, :print] begin
    cg = UNKNOWN(partial(:A, :B), partial(:B, :C))
    @test contains(
        sprint(show, cg),
        """UNKNOWN with 3 nodes and 2 edges:\n  nodes: A, B, C\n  edges:\n    A o-o B, B o-o C\n""",
    )
end

@testitem "print: no edges" tags = [:unit, :print] begin
    cg = DAG(node(:A), node(:B))
    @test contains(
        sprint(show, cg),
        """DAG with 2 nodes and 0 edges:\n  nodes: A, B\n  edges:\n    (none)\n""",
    )
end

@testitem "print: singular node/edge labels" tags = [:unit, :print] begin
    cg = DAG(directed(:A, :B))
    @test contains(sprint(show, cg), "DAG with 2 nodes and 1 edge:")
end
