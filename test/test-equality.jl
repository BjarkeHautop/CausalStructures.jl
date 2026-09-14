@testitem "graph equality ignores edge and node insertion order" tags = [:unit, :equality] begin
    @test ADMG("A <-> B") == ADMG("B <-> A")
    @test DAG("A --> B --> C") == DAG(directed(:B, :C), directed(:A, :B))
    @test DAG(node(:B), node(:A)) == DAG(node(:A), node(:B))
end

@testitem "graph equality distinguishes different graph classes" tags = [:unit, :equality] begin
    @test DAG("A --> B") != ADMG("A --> B")
    @test PDAG("A --- B --- C") != MPDAG("A --- B --- C")
end

@testitem "graph equality distinguishes different nodes or edges" tags = [:unit, :equality] begin
    @test DAG(directed(:A, :B)) != DAG(directed(:A, :B), node(:C))
    @test DAG(directed(:A, :B), node(:C)) != DAG(directed(:A, :B), node(:D))
    @test ADMG("A --> B") != ADMG("A <-> B")
    @test DAG("A --> B --> C") != DAG("A --> B")
end

@testitem "graph equality supports Set and Dict" tags = [:unit, :equality] begin
    s = Set([ADMG("A <-> B"), ADMG("B <-> A"), ADMG("A --> B")])
    @test length(s) == 2
end

@testitem "graph equality respects parallel edges in UNKNOWN" tags = [:unit, :equality] begin
    a = UNKNOWN(directed(:A, :B), directed(:A, :B))
    b = UNKNOWN(directed(:A, :B))
    @test a != b
end
