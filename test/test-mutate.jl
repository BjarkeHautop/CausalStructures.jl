using Test
using CausalStructures

# ── add_edge ──────────────────────────────────────────────────────────────────

@testitem "add_edge adds edge and preserves class" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_edge(g, directed(:B, :C))
    @test g2 isa DAG
    @test length(g2.edges) == 2
    @test Set(nodes(g2)) == Set([:A, :B, :C])
end

@testitem "add_edge auto-adds new nodes from edge" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_edge(g, directed(:B, :Z))
    @test :Z in nodes(g2)
    @test length(g2.edges) == 2
end

@testitem "add_edge does not mutate original" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    _ = add_edge(g, directed(:B, :C))
    @test length(g.edges) == 1
    @test Set(nodes(g)) == Set([:A, :B])
end

@testitem "add_edge works on PDAG" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = PDAG)
    g2 = add_edge(g, undirected(:B, :C))
    @test g2 isa PDAG
    @test length(g2.edges) == 2
end

@testitem "add_edge rejects invalid edge type for class" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    @test_throws Exception add_edge(g, undirected(:B, :C))
end

@testitem "add_edge on UNKNOWN preserves simple flag" tags = [:unit] begin
    g = cgraph(directed(:A, :B); simple = false, class = UNKNOWN)
    g2 = add_edge(g, directed(:A, :B))  # duplicate allowed
    @test g2 isa UNKNOWN
    @test length(g2.edges) == 2
end

# ── remove_edge ───────────────────────────────────────────────────────────────

@testitem "remove_edge removes the correct edge" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = remove_edge(g, directed(:A, :B))
    @test length(g2.edges) == 1
    @test g2.edges[1] == directed(:B, :C)
end

@testitem "remove_edge retains now-isolated nodes" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = remove_edge(g, directed(:A, :B))
    @test Set(nodes(g2)) == Set([:A, :B])
    @test length(g2.edges) == 0
end

@testitem "remove_edge throws on missing edge" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    @test_throws ArgumentError remove_edge(g, directed(:B, :C))
end

@testitem "remove_edge does not mutate original" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    _ = remove_edge(g, directed(:A, :B))
    @test length(g.edges) == 2
end

# ── add_node ──────────────────────────────────────────────────────────────────

@testitem "add_node adds an isolated node" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_node(g, :C)
    @test :C in nodes(g2)
    @test length(g2.edges) == 1
end

@testitem "add_node is idempotent for existing node" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_node(g, :A)
    @test g2 === g
end

# ── remove_node ───────────────────────────────────────────────────────────────

@testitem "remove_node removes node and incident edges" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = remove_node(g, :B)
    @test Set(nodes(g2)) == Set([:A, :C])
    @test length(g2.edges) == 0
end

@testitem "remove_node removes only incident edges" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:A, :C), directed(:B, :C); class = DAG)
    g2 = remove_node(g, :B)
    @test Set(nodes(g2)) == Set([:A, :C])
    @test length(g2.edges) == 1
    @test g2.edges[1] == directed(:A, :C)
end

@testitem "remove_node throws on missing node" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    @test_throws ArgumentError remove_node(g, :Z)
end

# ── reclass ───────────────────────────────────────────────────────────────────

@testitem "reclass changes graph class" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    p = reclass(g, PDAG)
    @test p isa PDAG
    @test Set(nodes(p)) == Set(nodes(g))
    @test length(p.edges) == length(g.edges)
end

@testitem "reclass throws on invalid edges for target class" tags = [:unit] begin
    g = cgraph(directed(:A, :B), undirected(:B, :C); class = PDAG)
    @test_throws Exception reclass(g, DAG)
end

@testitem "reclass to UNKNOWN with simple=false allows duplicates afterward" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    u = reclass(g, UNKNOWN; simple = false)
    @test u isa UNKNOWN
    u2 = add_edge(u, directed(:A, :B))
    @test length(u2.edges) == 2
end
