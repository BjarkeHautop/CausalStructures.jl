# ── add_edges ─────────────────────────────────────────────────────────────────

@testitem "add_edges adds edge and preserves class" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_edges(g, directed(:B, :C))
    @test g2 isa DAG
    @test length(g2.edges) == 2
    @test Set(nodes(g2)) == Set([:A, :B, :C])
end

@testitem "add_edges adds multiple edges at once" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_edges(g, directed(:B, :C), directed(:C, :D))
    @test length(g2.edges) == 3
    @test Set(nodes(g2)) == Set([:A, :B, :C, :D])
end

@testitem "add_edges auto-adds new nodes from edge" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_edges(g, directed(:B, :Z))
    @test :Z in nodes(g2)
    @test length(g2.edges) == 2
end

@testitem "add_edges does not mutate original" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    _ = add_edges(g, directed(:B, :C))
    @test length(g.edges) == 1
    @test Set(nodes(g)) == Set([:A, :B])
end

@testitem "add_edges works on PDAG" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = PDAG)
    g2 = add_edges(g, undirected(:B, :C))
    @test g2 isa PDAG
    @test length(g2.edges) == 2
end

@testitem "add_edges rejects invalid edge type for class" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    @test_throws Exception add_edges(g, undirected(:B, :C))
end

@testitem "add_edges on UNKNOWN preserves simple flag" tags = [:unit] begin
    g = cgraph(directed(:A, :B); simple = false, class = UNKNOWN)
    g2 = add_edges(g, directed(:A, :B))  # duplicate allowed
    @test g2 isa UNKNOWN
    @test length(g2.edges) == 2
end

# ── remove_edges ──────────────────────────────────────────────────────────────

@testitem "remove_edges removes the correct edge" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = remove_edges(g, directed(:A, :B))
    @test length(g2.edges) == 1
    @test g2.edges[1] == directed(:B, :C)
end

@testitem "remove_edges removes multiple edges at once" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:B, :C), directed(:A, :C); class = DAG)
    g2 = remove_edges(g, directed(:A, :B), directed(:B, :C))
    @test length(g2.edges) == 1
    @test g2.edges[1] == directed(:A, :C)
end

@testitem "remove_edges retains now-isolated nodes" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = remove_edges(g, directed(:A, :B))
    @test Set(nodes(g2)) == Set([:A, :B])
    @test length(g2.edges) == 0
end

@testitem "remove_edges throws on missing edge" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    @test_throws ArgumentError remove_edges(g, directed(:B, :C))
end

@testitem "remove_edges does not mutate original" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    _ = remove_edges(g, directed(:A, :B))
    @test length(g.edges) == 2
end

# ── add_nodes ─────────────────────────────────────────────────────────────────

@testitem "add_nodes adds an isolated node" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_nodes(g, :C)
    @test :C in nodes(g2)
    @test length(g2.edges) == 1
end

@testitem "add_nodes adds multiple isolated nodes" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_nodes(g, :C, :D)
    @test :C in nodes(g2)
    @test :D in nodes(g2)
    @test length(nodes(g2)) == 4
end

@testitem "add_nodes is idempotent for existing nodes" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_nodes(g, :A)
    @test g2 === g
end

@testitem "add_nodes ignores already-present nodes in a mixed call" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    g2 = add_nodes(g, :A, :C)
    @test Set(nodes(g2)) == Set([:A, :B, :C])
end

# ── remove_nodes ──────────────────────────────────────────────────────────────

@testitem "remove_nodes removes node and incident edges" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = remove_nodes(g, :B)
    @test Set(nodes(g2)) == Set([:A, :C])
    @test length(g2.edges) == 0
end

@testitem "remove_nodes removes multiple nodes and their incident edges" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:B, :C), directed(:A, :C); class = DAG)
    g2 = remove_nodes(g, :A, :B)
    @test Set(nodes(g2)) == Set([:C])
    @test length(g2.edges) == 0
end

@testitem "remove_nodes removes only incident edges" tags = [:unit] begin
    g = cgraph(directed(:A, :B), directed(:A, :C), directed(:B, :C); class = DAG)
    g2 = remove_nodes(g, :B)
    @test Set(nodes(g2)) == Set([:A, :C])
    @test length(g2.edges) == 1
    @test g2.edges[1] == directed(:A, :C)
end

@testitem "remove_nodes throws on missing node" tags = [:unit] begin
    g = cgraph(directed(:A, :B); class = DAG)
    @test_throws ArgumentError remove_nodes(g, :Z)
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
    u2 = add_edges(u, directed(:A, :B))
    @test length(u2.edges) == 2
end
