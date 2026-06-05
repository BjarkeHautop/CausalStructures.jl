# Ported from caugi/tests/testthat/test-queries.R and test-caugi_graph.R
# Verb-based tests (add_edges, set_edges, etc.) are skipped.

using Test
using CausalGraphInterface

# ── is_acyclic / is_simple ────────────────────────────────────────────────────

@testitem "is_acyclic returns true for DAG/PDAG by class" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = DAG)
    @test is_acyclic(dag)
end

@testitem "is_acyclic detects cycles in UNKNOWN graphs" tags = [:unit] begin
    unknown = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :A); class = UNKNOWN)
    @test !is_acyclic(unknown)
end

@testitem "is_simple reflects declared state" tags = [:unit] begin
    g_simple = caugi(directed(:A, :B); class = DAG)
    @test is_simple(g_simple)

    g_nonsimple =
        caugi(directed(:A, :B), bidirected(:A, :B); class = UNKNOWN, simple = false)
    @test !is_simple(g_nonsimple)
end

# ── is_dag / is_pdag / is_ug / is_admg ───────────────────────────────────────

@testitem "is_dag works" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = DAG)
    @test is_dag(dag)

    g2 = caugi(directed(:A, :B), directed(:B, :C), undirected(:C, :D); class = PDAG)
    @test !is_dag(g2)

    # A PDAG with only directed edges is also a DAG
    g3 = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = PDAG)
    @test is_dag(g3)

    g4 = caugi(directed(:A, :B), directed(:B, :C), undirected(:C, :D); class = UNKNOWN)
    @test !is_dag(g4)
end

@testitem "is_pdag works" tags = [:unit] begin
    pdag = caugi(directed(:A, :B), directed(:B, :C), undirected(:C, :D); class = PDAG)
    @test is_pdag(pdag)

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
    ug = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:C, :D); class = UG)
    @test is_ug(ug)
    @test is_ug(ug)

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
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_admg(dag)

    g2 = caugi(directed(:A, :B), bidirected(:A, :C); class = ADMG)
    @test is_admg(g2)

    # UG with only undirected edges is NOT an ADMG
    g3 = caugi(undirected(:A, :B); class = UG)
    @test !is_admg(g3)
end

# ── parents / children / neighbors ───────────────────────────────────────────

@testitem "parents returns expected nodes" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:A, :D),
        directed(:D, :B);
        class = PDAG,
    )
    @test Set(parents(cg, :B)) == Set([:A, :D])
    @test isempty(parents(cg, :A))
end

@testitem "children returns expected nodes" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:B, :C),
        undirected(:C, :D),
        directed(:D, :E);
        class = PDAG,
    )
    @test children(cg, :A) == [:B]
    @test children(cg, :B) == [:C]
    @test children(cg, :D) == [:E]
end

@testitem "neighbors returns adjacency (directed + undirected)" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:B, :C),
        undirected(:B, :D),
        undirected(:C, :E);
        class = PDAG,
    )
    @test Set(neighbors(cg, :B)) == Set([:A, :C, :D])
    @test Set(neighbors(cg, :C)) == Set([:B, :E])
end

@testitem "parents/children match by node name" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:B, :C),
        undirected(:B, :D),
        undirected(:C, :E);
        class = PDAG,
    )
    @test children(cg, :A) == [:B]
    @test Set(parents(cg, :B)) == Set([:A])
    @test Set(neighbors(cg, :C)) == Set([:B, :E])
end

@testitem "parents/children are not defined for UG" tags = [:unit] begin
    ug = caugi(undirected(:A, :B); class = UG)
    @test_throws MethodError parents(ug, :A)
    @test_throws MethodError children(ug, :B)
end

@testitem "neighbors for UG returns undirected adjacency" tags = [:unit] begin
    ug = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:B, :D); class = UG)
    @test neighbors(ug, :A) == [:B]
    @test Set(neighbors(ug, :B)) == Set([:A, :C, :D])
    @test neighbors(ug, :C) == [:B]
    @test neighbors(ug, :D) == [:B]
end

# ── ancestors / descendants ───────────────────────────────────────────────────

@testitem "ancestors works on DAG" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )
    @test Set(ancestors(cg, :D)) == Set([:A, :B, :C])
    @test Set(ancestors(cg, :B)) == Set([:A])
    @test isempty(ancestors(cg, :A))
end

@testitem "descendants works on DAG" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )
    @test Set(descendants(cg, :A)) == Set([:B, :C, :D])
    @test Set(descendants(cg, :B)) == Set([:D])
    @test isempty(descendants(cg, :D))
end

@testitem "ancestors/descendants open vs closed definition" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    # open = true (default): excludes the node itself
    @test ancestors(dag, :B) == [:A]
    # open = false (closed): includes the node itself
    @test Set(ancestors(dag, :B; open = false)) == Set([:B, :A])
    @test Set(descendants(dag, :A; open = false)) == Set([:A, :B, :C])
end

@testitem "ancestors errors on UG" tags = [:unit] begin
    ug = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError ancestors(ug, :B)
end

@testitem "descendants errors on UG" tags = [:unit] begin
    ug = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError descendants(ug, :B)
end

# NetworkX ancestors/descendants tests
# https://github.com/networkx/networkx/blob/main/networkx/algorithms/tests/test_dag.py

@testitem "ancestors NetworkX 1 test" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:D, :E),
        directed(:D, :C),
        directed(:B, :F),
        directed(:E, :F);
        class = DAG,
    )
    @test Set(ancestors(cg, :F)) == Set([:A, :B, :D, :E])
    @test Set(ancestors(cg, :C)) == Set([:A, :D])
    @test isempty(ancestors(cg, :A))
end

@testitem "descendants NetworkX 1 test" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:D, :E),
        directed(:D, :C),
        directed(:B, :F),
        directed(:E, :F);
        class = DAG,
    )
    @test Set(descendants(cg, :A)) == Set([:B, :C, :F])
    @test Set(descendants(cg, :D)) == Set([:B, :C, :E, :F])
    @test isempty(descendants(cg, :C))
end

# ── markov_blanket ────────────────────────────────────────────────────────────

@testitem "markov_blanket works on DAGs (parents, children, spouses)" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:B, :E),
        directed(:F, :E);
        class = DAG,
    )
    @test Set(markov_blanket(cg, :A)) == Set([:B, :C, :D])
    @test Set(markov_blanket(cg, :B)) == Set([:A, :D, :E, :F])
end

@testitem "markov_blanket includes undirected neighbors in PDAGs" tags = [:unit] begin
    pdag = caugi(directed(:A, :B), undirected(:B, :C), directed(:D, :B); class = PDAG)
    @test Set(markov_blanket(pdag, :B)) == Set([:A, :C, :D])
end

@testitem "markov_blanket multi-parent fixture on DAGs" tags = [:unit] begin
    cg = caugi(
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
    @test Set(markov_blanket(cg, :Z1)) == Set([:X, :Z2, :Z3])
    @test Set(markov_blanket(cg, :Y)) == Set([:W, :Z2, :Z3])
end

@testitem "markov_blanket errors on UG" tags = [:unit] begin
    ug = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError markov_blanket(ug, :B)
end

# ── exogenous_nodes ───────────────────────────────────────────────────────────

@testitem "exogenous_nodes works on DAG" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:B, :E),
        directed(:F, :E);
        class = DAG,
    )
    @test Set(exogenous_nodes(cg)) == Set([:A, :D, :F])
end

@testitem "exogenous_nodes works on PDAG" tags = [:unit] begin
    pdag = caugi(undirected(:A, :B), directed(:C, :A); class = PDAG)
    @test Set(exogenous_nodes(pdag)) == Set([:B, :C])
end

@testitem "exogenous_nodes works on UG" tags = [:unit] begin
    ug = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test isempty(exogenous_nodes(ug))
    g_iso = caugi(undirected(:A, :B), node(:C); class = UG)
    @test exogenous_nodes(g_iso) == [:C]
end

# ── anteriors / posteriors ────────────────────────────────────────────────────

@testitem "anteriors works for DAG (equals ancestors)" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test isempty(anteriors(dag, :A))
    @test anteriors(dag, :B) == [:A]
    @test Set(anteriors(dag, :C)) == Set([:A, :B])
end

@testitem "anteriors works for PDAG with mixed edges" tags = [:unit] begin
    # A -> B --- C, B -> D
    pdag = caugi(directed(:A, :B), undirected(:B, :C), directed(:B, :D); class = PDAG)
    @test isempty(anteriors(pdag, :A))
    @test Set(anteriors(pdag, :B)) == Set([:A, :C])
    @test Set(anteriors(pdag, :C)) == Set([:A, :B])
    @test Set(anteriors(pdag, :D)) == Set([:A, :B, :C])
end

@testitem "anteriors works for PDAG with undirected cycle" tags = [:unit] begin
    # A --- B --- C --- A (triangle)
    pdag = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:C, :A); class = PDAG)
    @test Set(anteriors(pdag, :A)) == Set([:B, :C])
    @test Set(anteriors(pdag, :B)) == Set([:A, :C])
    @test Set(anteriors(pdag, :C)) == Set([:A, :B])
end

@testitem "anteriors errors on UG" tags = [:unit] begin
    ug = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError anteriors(ug, :B)
end

@testitem "posteriors works for DAG (equals descendants)" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test Set(posteriors(dag, :A)) == Set([:B, :C])
    @test posteriors(dag, :B) == [:C]
    @test isempty(posteriors(dag, :C))
end

@testitem "posteriors works for PDAG with mixed edges" tags = [:unit] begin
    # A -> B --- C, B -> D
    pdag = caugi(directed(:A, :B), undirected(:B, :C), directed(:B, :D); class = PDAG)
    @test Set(posteriors(pdag, :A)) == Set([:B, :C, :D])
    @test Set(posteriors(pdag, :B)) == Set([:C, :D])
    @test Set(posteriors(pdag, :C)) == Set([:B, :D])
    @test isempty(posteriors(pdag, :D))
end

@testitem "posteriors works for PDAG with undirected cycle" tags = [:unit] begin
    pdag = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:C, :A); class = PDAG)
    @test Set(posteriors(pdag, :A)) == Set([:B, :C])
    @test Set(posteriors(pdag, :B)) == Set([:A, :C])
    @test Set(posteriors(pdag, :C)) == Set([:A, :B])
end

@testitem "posteriors errors on UG" tags = [:unit] begin
    ug = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError posteriors(ug, :B)
end

@testitem "posteriors excludes the node itself" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test !(:A in posteriors(dag, :A))
end

@testitem "posteriors does not return duplicates in undirected cycles" tags = [:unit] begin
    pdag = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:C, :A); class = PDAG)
    res = posteriors(pdag, :A)
    @test length(res) == length(unique(res))
end

@testitem "posteriors handles multi-step mixed reachability" tags = [:unit] begin
    # A -> B --- C --- D -> E
    cg = caugi(
        directed(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        directed(:D, :E);
        class = PDAG,
    )
    @test Set(posteriors(cg, :A)) == Set([:B, :C, :D, :E])
end

@testitem "posteriors handles disconnected components" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:C, :D); class = DAG)
    @test posteriors(dag, :A) == [:B]
    @test !(:A in posteriors(dag, :C))
end

@testitem "closed definition for ancestors/anteriors/descendants/posteriors" tags = [:unit] begin
    pdag = caugi(directed(:A, :B), undirected(:B, :C), directed(:B, :D); class = PDAG)

    @test ancestors(pdag, :A; open = false) == [:A]
    @test Set(ancestors(pdag, :B; open = false)) == Set([:B, :A])

    @test anteriors(pdag, :A; open = false) == [:A]
    @test Set(anteriors(pdag, :C; open = false)) == Set([:C, :A, :B])

    @test Set(descendants(pdag, :A; open = false)) == Set([:A, :B, :D])
    @test Set(descendants(pdag, :B; open = false)) == Set([:B, :D])

    @test Set(posteriors(pdag, :A; open = false)) == Set([:A, :B, :C, :D])
    @test Set(posteriors(pdag, :B; open = false)) == Set([:B, :C, :D])
end

# ── subgraph ──────────────────────────────────────────────────────────────────

@testitem "subgraph on DAG" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )
    sg = subgraph(cg, [:A, :B, :D])
    @test sg isa DAG
    @test Set(nodes(sg)) == Set([:A, :B, :D])
    @test has_edge(sg, :A, :B)
    @test !(:C in nodes(sg))
end

@testitem "subgraph on UG" tags = [:unit] begin
    ug = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    sg = subgraph(ug, [:A, :B])
    @test sg isa UG
    @test Set(nodes(sg)) == Set([:A, :B])
    @test has_edge(sg, :A, :B)
end

@testitem "subgraph on PDAG" tags = [:unit] begin
    pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG)
    sg = subgraph(pdag, [:A, :B])
    @test sg isa PDAG
    @test Set(nodes(sg)) == Set([:A, :B])
    @test has_edge(sg, :A, :B)
end

# ── spouses / districts (not yet implemented) ─────────────────────────────────

@testitem "spouses works for ADMG" tags = [:unit] begin
    admg = caugi(directed(:A, :B), bidirected(:B, :C); class = ADMG)
    @test !isempty(spouses(admg, :B))
end

@testitem "districts works for ADMG" tags = [:unit] begin
    admg = caugi(bidirected(:A, :B), bidirected(:B, :C), directed(:C, :D); class = ADMG)
    @test length(districts(admg)) == 2
end

# ── is_cpdag ──────────────────────────────────────────────────────────────────

@testitem "is_cpdag: CPDAG class is always true" tags = [:unit] begin
    cpdag = caugi(directed(:A, :C), directed(:B, :C); class = CPDAG)
    @test is_cpdag(cpdag)
end

@testitem "is_cpdag: PDAG v-structure is a valid CPDAG" tags = [:unit] begin
    pdag = caugi(directed(:A, :C), directed(:B, :C); class = PDAG)
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: PDAG single directed edge is not a CPDAG" tags = [:unit] begin
    # A→B has no v-structure protecting it
    pdag = caugi(directed(:A, :B); class = PDAG)
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: pure directed chain is not a CPDAG" tags = [:unit] begin
    pdag = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = PDAG)
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: undirected edge is a valid CPDAG" tags = [:unit] begin
    pdag = caugi(undirected(:A, :B); class = PDAG)
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: undirected chain is a valid CPDAG" tags = [:unit] begin
    pdag = caugi(undirected(:A, :B), undirected(:B, :C); class = PDAG)
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: undirected triangle is a valid CPDAG" tags = [:unit] begin
    pdag = caugi(undirected(:A, :B), undirected(:B, :C), undirected(:A, :C); class = PDAG)
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: triangle with adjacent parents is not a CPDAG" tags = [:unit] begin
    # A→C, B→C, A—B: A and B are adjacent so no v-structure at C; arrows not protected
    pdag = caugi(directed(:A, :C), directed(:B, :C), undirected(:A, :B); class = PDAG)
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: isolated nodes are a valid CPDAG" tags = [:unit] begin
    pdag = caugi(node(:A), node(:B), node(:C); class = PDAG)
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: v-structure + isolated nodes is a valid CPDAG" tags = [:unit] begin
    pdag = caugi(directed(:A, :C), directed(:B, :C), node(:D), node(:E); class = PDAG)
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: non-chordal 4-cycle is not a CPDAG" tags = [:unit] begin
    cg = caugi(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:D, :A);
        class = PDAG,
    )
    @test !is_cpdag(cg)
end

@testitem "is_cpdag: rejects Meek R1 violation" tags = [:unit] begin
    # A→B, B—C, A not adjacent to C: R1 would orient B→C
    pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG)
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: rejects Meek R2 violation" tags = [:unit] begin
    # A—B with A→C→B: R2 would orient A→B
    pdag = caugi(undirected(:A, :B), directed(:A, :C), directed(:C, :B); class = PDAG)
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: rejects Meek R3 violation" tags = [:unit] begin
    # A—B, C→B, D→B, C not adj D, A—C, A—D: R3 would orient A→B
    cg = caugi(
        undirected(:A, :B),
        directed(:C, :B),
        directed(:D, :B),
        undirected(:A, :C),
        undirected(:A, :D);
        class = PDAG,
    )
    @test !is_cpdag(cg)
end

@testitem "is_cpdag: rejects Meek R4 violation" tags = [:unit] begin
    # A—B with directed path A→C→D→B: R4 would orient A→B
    cg = caugi(
        undirected(:A, :B),
        directed(:A, :C),
        directed(:C, :D),
        directed(:D, :B);
        class = PDAG,
    )
    @test !is_cpdag(cg)
end

@testitem "is_cpdag: complex valid CPDAG with v-structure + undirected components" tags =
    [:unit] begin
    # B—A, B—D, C→E←B, D→F←E
    cg = caugi(
        undirected(:B, :A),
        undirected(:B, :D),
        directed(:C, :E),
        directed(:B, :E),
        directed(:D, :F),
        directed(:E, :F);
        class = PDAG,
    )
    @test is_cpdag(cg)
end

@testitem "is_cpdag: v-structure with R1 cascade (C→E←B, E→F) is valid" tags = [:unit] begin
    # C→E, B→E protects both; E→F is protected by SP2 (B→E→F)
    pdag = caugi(directed(:A, :C), directed(:B, :C), directed(:C, :D); class = PDAG)
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: PDAG with B→A and B→C (fork) is not a CPDAG" tags = [:unit] begin
    # B→A, B→C: neither edge is protected (no v-structure)
    pdag = caugi(directed(:B, :A), directed(:B, :C); class = PDAG)
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: CPDAG constructor rejects invalid graph" tags = [:unit] begin
    @test_throws ErrorException caugi(directed(:A, :B); class = CPDAG)
end

@testitem "is_cpdag: generate_graph(CPDAG) produces valid CPDAGs" tags = [:unit] begin
    for seed = 1:10
        cpdag = generate_graph(6; m = 5, class = CPDAG, seed = seed)
        @test is_cpdag(cpdag)
    end
end
