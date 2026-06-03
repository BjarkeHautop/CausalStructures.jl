# Ported from caugi/tests/testthat/test-queries.R and test-caugi_graph.R
# Verb-based tests (add_edges, set_edges, etc.) are skipped.

using Test
using CausalGraphInterface
# ── is_caugi ──────────────────────────────────────────────────────────────────

@testitem "is_caugi works" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C), undirected(:C, :D); class = PDAG)
    @test is_caugi(g)
    @test !is_caugi(42)
    @test !is_caugi("not a graph")
end

# ── is_acyclic / is_simple ────────────────────────────────────────────────────

@testitem "is_acyclic returns true for DAG/PDAG by class" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = DAG)
    @test is_acyclic(g)
    @test is_acyclic(g; force_check = true)
end

@testitem "is_acyclic detects cycles in UNKNOWN graphs" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :A); class = UNKNOWN)
    @test !is_acyclic(g)
end

@testitem "is_simple reflects declared state" tags = [:unit] begin
    g_simple = caugi(directed(:A, :B); class = DAG)
    @test is_simple(g_simple)
    @test is_simple(g_simple; force_check = true)

    g_nonsimple =
        caugi(directed(:A, :B), bidirected(:A, :B); class = UNKNOWN, simple = false)
    @test !is_simple(g_nonsimple)
    @test !is_simple(g_nonsimple; force_check = true)
end

# ── is_dag / is_pdag / is_ug / is_admg ───────────────────────────────────────

@testitem "is_dag works" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = DAG)
    @test is_dag(g)

    g2 = caugi(directed(:A, :B), directed(:B, :C), undirected(:C, :D); class = PDAG)
    @test !is_dag(g2)

    # A PDAG with only directed edges is also a DAG
    g3 = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = PDAG)
    @test is_dag(g3)

    g4 = caugi(directed(:A, :B), directed(:B, :C), undirected(:C, :D); class = UNKNOWN)
    @test !is_dag(g4)
end

@testitem "is_pdag works" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C), undirected(:C, :D); class = PDAG)
    @test is_pdag(g)

    # A DAG is also a valid PDAG
    g2 = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = DAG)
    @test is_pdag(g2)

    # Graph with partially-directed edges is not a PDAG
    g3 = caugi(
        directed(:A, :B),
        directed(:B, :C),
        partially_directed(:C, :D);
        class = UNKNOWN,
    )
    @test !is_pdag(g3)
end

@testitem "is_ug works" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:C, :D); class = UG)
    @test is_ug(g)
    @test is_ug(g; force_check = true)

    g2 = caugi(directed(:A, :B), undirected(:B, :C), undirected(:C, :D); class = PDAG)
    @test !is_ug(g2)

    g3 = caugi(
        undirected(:A, :B),
        undirected(:B, :C),
        partially_directed(:C, :D);
        class = UNKNOWN,
    )
    @test !is_ug(g3)
end

@testitem "is_admg works" tags = [:unit] begin
    # A pure DAG is also a valid ADMG
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_admg(g; force_check = true)

    g2 = caugi(directed(:A, :B), bidirected(:A, :C); class = ADMG)
    @test is_admg(g2)

    # UG with only undirected edges is NOT an ADMG
    g3 = caugi(undirected(:A, :B); class = UG)
    @test !is_admg(g3; force_check = true)
end

# ── parents / children / neighbors ───────────────────────────────────────────

@testitem "parents returns expected nodes" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:A, :D),
        directed(:D, :B);
        class = PDAG,
    )
    @test Set(parents(g, :B)) == Set([:A, :D])
    @test isempty(parents(g, :A))
end

@testitem "children returns expected nodes" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:B, :C),
        undirected(:C, :D),
        directed(:D, :E);
        class = PDAG,
    )
    @test children(g, :A) == [:B]
    @test children(g, :B) == [:C]
    @test children(g, :D) == [:E]
end

@testitem "neighbors returns adjacency (directed + undirected)" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:B, :C),
        undirected(:B, :D),
        undirected(:C, :E);
        class = PDAG,
    )
    @test Set(neighbors(g, :B)) == Set([:A, :C, :D])
    @test Set(neighbors(g, :C)) == Set([:B, :E])
end

@testitem "parents/children match by node name" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:B, :C),
        undirected(:B, :D),
        undirected(:C, :E);
        class = PDAG,
    )
    @test children(g, :A) == [:B]
    @test Set(parents(g, :B)) == Set([:A])
    @test Set(neighbors(g, :C)) == Set([:B, :E])
end

@testitem "parents/children are not defined for UG" tags = [:unit] begin
    ug = caugi(undirected(:A, :B); class = UG)
    @test_throws MethodError parents(ug, :A)
    @test_throws MethodError children(ug, :B)
end

@testitem "neighbors for UG returns undirected adjacency" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:B, :D); class = UG)
    @test neighbors(g, :A) == [:B]
    @test Set(neighbors(g, :B)) == Set([:A, :C, :D])
    @test neighbors(g, :C) == [:B]
    @test neighbors(g, :D) == [:B]
end

# ── ancestors / descendants ───────────────────────────────────────────────────

@testitem "ancestors works on DAG" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )
    @test Set(ancestors(g, :D)) == Set([:A, :B, :C])
    @test Set(ancestors(g, :B)) == Set([:A])
    @test isempty(ancestors(g, :A))
end

@testitem "descendants works on DAG" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )
    @test Set(descendants(g, :A)) == Set([:B, :C, :D])
    @test Set(descendants(g, :B)) == Set([:D])
    @test isempty(descendants(g, :D))
end

@testitem "ancestors/descendants open vs closed definition" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    # open = true (default): excludes the node itself
    @test ancestors(g, :B) == [:A]
    # open = false (closed): includes the node itself
    @test Set(ancestors(g, :B; open = false)) == Set([:B, :A])
    @test Set(descendants(g, :A; open = false)) == Set([:A, :B, :C])
end

@testitem "ancestors errors on UG" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError ancestors(g, :B)
end

@testitem "descendants errors on UG" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError descendants(g, :B)
end

# NetworkX ancestors/descendants tests
# https://github.com/networkx/networkx/blob/main/networkx/algorithms/tests/test_dag.py

@testitem "ancestors NetworkX 1 test" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:D, :E),
        directed(:D, :C),
        directed(:B, :F),
        directed(:E, :F);
        class = DAG,
    )
    @test Set(ancestors(g, :F)) == Set([:A, :B, :D, :E])
    @test Set(ancestors(g, :C)) == Set([:A, :D])
    @test isempty(ancestors(g, :A))
end

@testitem "descendants NetworkX 1 test" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:D, :E),
        directed(:D, :C),
        directed(:B, :F),
        directed(:E, :F);
        class = DAG,
    )
    @test Set(descendants(g, :A)) == Set([:B, :C, :F])
    @test Set(descendants(g, :D)) == Set([:B, :C, :E, :F])
    @test isempty(descendants(g, :C))
end

# ── markov_blanket ────────────────────────────────────────────────────────────

@testitem "markov_blanket works on DAGs (parents, children, spouses)" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:B, :E),
        directed(:F, :E);
        class = DAG,
    )
    @test Set(markov_blanket(g, :A)) == Set([:B, :C, :D])
    @test Set(markov_blanket(g, :B)) == Set([:A, :D, :E, :F])
end

@testitem "markov_blanket includes undirected neighbors in PDAGs" tags = [:unit] begin
    g = caugi(directed(:A, :B), undirected(:B, :C), directed(:D, :B); class = PDAG)
    @test Set(markov_blanket(g, :B)) == Set([:A, :C, :D])
end

@testitem "markov_blanket multi-parent fixture on DAGs" tags = [:unit] begin
    g = caugi(
        directed(:W, :Y),
        directed(:X, :W),
        directed(:Z1, :X),
        directed(:Z1, :Z3),
        directed(:Z2, :Y),
        directed(:Z2, :Z3),
        directed(:Z3, :X),
        directed(:Z3, :Y);
        class = DAG,
    )
    @test Set(markov_blanket(g, :Z1)) == Set([:X, :Z2, :Z3])
    @test Set(markov_blanket(g, :Y)) == Set([:W, :Z2, :Z3])
end

@testitem "markov_blanket errors on UG" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError markov_blanket(g, :B)
end

# ── exogenous_nodes ───────────────────────────────────────────────────────────

@testitem "exogenous_nodes works on DAG" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:B, :E),
        directed(:F, :E);
        class = DAG,
    )
    @test Set(exogenous_nodes(g)) == Set([:A, :D, :F])
end

@testitem "exogenous_nodes works on PDAG" tags = [:unit] begin
    g = caugi(undirected(:A, :B), directed(:C, :A); class = PDAG)
    @test Set(exogenous_nodes(g)) == Set([:B, :C])
end

@testitem "exogenous_nodes not implemented for UG (broken)" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_broken !isempty(exogenous_nodes(g))
end

# ── anteriors / posteriors ────────────────────────────────────────────────────

@testitem "anteriors works for DAG (equals ancestors)" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test isempty(anteriors(g, :A))
    @test anteriors(g, :B) == [:A]
    @test Set(anteriors(g, :C)) == Set([:A, :B])
end

@testitem "anteriors works for PDAG with mixed edges" tags = [:unit] begin
    # A -> B --- C, B -> D
    g = caugi(directed(:A, :B), undirected(:B, :C), directed(:B, :D); class = PDAG)
    @test isempty(anteriors(g, :A))
    @test Set(anteriors(g, :B)) == Set([:A, :C])
    @test Set(anteriors(g, :C)) == Set([:A, :B])
    @test Set(anteriors(g, :D)) == Set([:A, :B, :C])
end

@testitem "anteriors works for PDAG with undirected cycle" tags = [:unit] begin
    # A --- B --- C --- A (triangle)
    g = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:C, :A); class = PDAG)
    @test Set(anteriors(g, :A)) == Set([:B, :C])
    @test Set(anteriors(g, :B)) == Set([:A, :C])
    @test Set(anteriors(g, :C)) == Set([:A, :B])
end

@testitem "anteriors errors on UG" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError anteriors(g, :B)
end

@testitem "posteriors works for DAG (equals descendants)" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test Set(posteriors(g, :A)) == Set([:B, :C])
    @test posteriors(g, :B) == [:C]
    @test isempty(posteriors(g, :C))
end

@testitem "posteriors works for PDAG with mixed edges" tags = [:unit] begin
    # A -> B --- C, B -> D
    g = caugi(directed(:A, :B), undirected(:B, :C), directed(:B, :D); class = PDAG)
    @test Set(posteriors(g, :A)) == Set([:B, :C, :D])
    @test Set(posteriors(g, :B)) == Set([:C, :D])
    @test Set(posteriors(g, :C)) == Set([:B, :D])
    @test isempty(posteriors(g, :D))
end

@testitem "posteriors works for PDAG with undirected cycle" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:C, :A); class = PDAG)
    @test Set(posteriors(g, :A)) == Set([:B, :C])
    @test Set(posteriors(g, :B)) == Set([:A, :C])
    @test Set(posteriors(g, :C)) == Set([:A, :B])
end

@testitem "posteriors errors on UG" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError posteriors(g, :B)
end

@testitem "posteriors excludes the node itself" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test !(:A in posteriors(g, :A))
end

@testitem "posteriors does not return duplicates in undirected cycles" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:C, :A); class = PDAG)
    res = posteriors(g, :A)
    @test length(res) == length(unique(res))
end

@testitem "posteriors handles multi-step mixed reachability" tags = [:unit] begin
    # A -> B --- C --- D -> E
    g = caugi(
        directed(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        directed(:D, :E);
        class = PDAG,
    )
    @test Set(posteriors(g, :A)) == Set([:B, :C, :D, :E])
end

@testitem "posteriors handles disconnected components" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:C, :D); class = DAG)
    @test posteriors(g, :A) == [:B]
    @test !(:A in posteriors(g, :C))
end

@testitem "closed definition for ancestors/anteriors/descendants/posteriors" tags = [:unit] begin
    g = caugi(directed(:A, :B), undirected(:B, :C), directed(:B, :D); class = PDAG)

    @test ancestors(g, :A; open = false) == [:A]
    @test Set(ancestors(g, :B; open = false)) == Set([:B, :A])

    @test anteriors(g, :A; open = false) == [:A]
    @test Set(anteriors(g, :C; open = false)) == Set([:C, :A, :B])

    @test Set(descendants(g, :A; open = false)) == Set([:A, :B, :D])
    @test Set(descendants(g, :B; open = false)) == Set([:B, :D])

    @test Set(posteriors(g, :A; open = false)) == Set([:A, :B, :C, :D])
    @test Set(posteriors(g, :B; open = false)) == Set([:B, :C, :D])
end

# ── subgraph ──────────────────────────────────────────────────────────────────

@testitem "subgraph on DAG" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )
    sg = subgraph(g, [:A, :B, :D])
    @test sg isa DAG
    @test Set(nodes(sg)) == Set([:A, :B, :D])
    @test has_edge(sg, :A, :B)
    @test !(:C in nodes(sg))
end

@testitem "subgraph on UG" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    sg = subgraph(g, [:A, :B])
    @test sg isa UG
    @test Set(nodes(sg)) == Set([:A, :B])
    @test has_edge(sg, :A, :B)
end

@testitem "subgraph on PDAG" tags = [:unit] begin
    g = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG)
    sg = subgraph(g, [:A, :B])
    @test sg isa PDAG
    @test Set(nodes(sg)) == Set([:A, :B])
    @test has_edge(sg, :A, :B)
end

# ── spouses / districts (not yet implemented) ─────────────────────────────────

@testitem "spouses works for ADMG" tags = [:unit] begin
    g = caugi(directed(:A, :B), bidirected(:B, :C); class = ADMG)
    @test !isempty(spouses(g, :B))
end

@testitem "districts works for ADMG" tags = [:unit] begin
    g = caugi(bidirected(:A, :B), bidirected(:B, :C), directed(:C, :D); class = ADMG)
    @test length(districts(g)) == 2
end
