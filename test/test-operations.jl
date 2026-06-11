# Tests adapted in part from caugi/tests/testthat/test-operations.R

using Test
using CausalGraphInterface

# ── skeleton ──────────────────────────────────────────────────────────────────

@testitem "skeleton on DAG produces UG with same skeleton" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:C, :D),
        directed(:D, :E),
        node(:F),
        node(:G);
        class = DAG,
    )
    skel = skeleton(cg)
    @test skel isa UG
    @test Set(nodes(skel)) == Set(nodes(cg))
    @test all(
        e ->
            e.src_end == CausalGraphInterface.Tail &&
            e.dst_end == CausalGraphInterface.Tail,
        skel.edges,
    )
end

@testitem "skeleton on PDAG produces UG with same skeleton" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:B, :C),
        undirected(:C, :D),
        directed(:D, :E),
        node(:F),
        node(:G);
        class = PDAG,
    )
    skel = skeleton(cg)
    @test skel isa UG
    @test Set(nodes(skel)) == Set(nodes(cg))
    @test all(
        e ->
            e.src_end == CausalGraphInterface.Tail &&
            e.dst_end == CausalGraphInterface.Tail,
        skel.edges,
    )
end

# ── subgraph ──────────────────────────────────────────────────────────────────

@testitem "subgraph on DAG returns DAG" tags = [:unit] begin
    cg = caugi(directed(:A, :B), directed(:B, :C), directed(:A, :C); class = DAG)
    sg = subgraph(cg, [:A, :B])
    @test sg isa DAG
    @test Set(nodes(sg)) == Set([:A, :B])
    @test has_edge(sg, :A, :B)
end

@testitem "subgraph on CPDAG with v-structure: removing collider orphans directed edge" tags =
    [:unit] begin
    # V-structure: A-->B<--C, A and C not adjacent.
    # A-->B is protected by VS (C-->B, C not adj A).
    # C-->B is protected by VS (A-->B, A not adj C).
    # After removing C, A-->B has no protection -- must downgrade to PDAG.
    cpdag = caugi(directed(:A, :B), directed(:C, :B); class = CPDAG)
    sg = subgraph(cpdag, [:A, :B])
    @test sg isa PDAG
    @test !(sg isa CPDAG)
    @test !is_cpdag(sg)
    @test has_edge(sg, :A, :B)
end

@testitem "subgraph on MPDAG preserves MPDAG class" tags = [:unit] begin
    # Meek rules fire on edge-presence conditions; removing nodes only removes
    # edges, so no new violation can appear.
    mpdag = caugi(directed(:A, :B), directed(:B, :C); class = MPDAG)
    sg = subgraph(mpdag, [:A, :B])
    @test sg isa MPDAG
end

# ── moralize ──────────────────────────────────────────────────────────────────

@testitem "moralize works on DAGs" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:D, :C),
        directed(:E, :C),
        directed(:D, :B),
        node(:F),
        node(:G);
        class = DAG,
    )
    mg = moralize(cg)
    @test mg isa UG
    @test Set(nodes(mg)) == Set(nodes(cg))
    @test all(
        e ->
            e.src_end == CausalGraphInterface.Tail &&
            e.dst_end == CausalGraphInterface.Tail,
        mg.edges,
    )

    has_ug_edge(cg, u, v) = has_edge(cg, u, v) || has_edge(cg, v, u)
    @test has_ug_edge(mg, :A, :B)
    @test has_ug_edge(mg, :B, :C)
    @test has_ug_edge(mg, :D, :E)
    @test has_ug_edge(mg, :B, :D)
    @test has_ug_edge(mg, :B, :E)
    @test has_ug_edge(mg, :C, :D)
    @test has_ug_edge(mg, :C, :E)
end

# NetworkX moralization tests
# https://github.com/networkx/networkx/blob/main/networkx/algorithms/tests/test_moral.py

@testitem "NetworkX moralize test 1" tags = [:unit] begin
    cg = caugi(
        directed(:A, :B),
        directed(:C, :B),
        directed(:D, :A),
        directed(:D, :E),
        directed(:F, :E),
        directed(:G, :E);
        class = DAG,
    )
    mg = moralize(cg)
    @test mg isa UG

    has_ug_edge(cg, u, v) = has_edge(cg, u, v) || has_edge(cg, v, u)
    @test has_ug_edge(mg, :A, :C)
    @test has_ug_edge(mg, :D, :F)
    @test has_ug_edge(mg, :F, :G)
    @test has_ug_edge(mg, :D, :G)
    @test !has_ug_edge(mg, :A, :E)
end

# ── latent_project ───────────────────────────────────────────────────────────

@testitem "latent_project basic confounding" tags = [:unit] begin
    dag = caugi(directed(:U, :X), directed(:U, :Y), directed(:X, :Y); class = DAG)
    admg = latent_project(dag, [:U])
    @test admg isa ADMG
    @test length(nodes(admg)) == 2
    @test has_edge(admg, :X, :Y)
end

@testitem "latent_project with no latents" tags = [:unit] begin
    dag = caugi(directed(:X, :Y), directed(:Y, :Z); class = DAG)
    admg = latent_project(dag, Symbol[])
    @test admg isa ADMG
    @test length(nodes(admg)) == 3
    @test has_edge(admg, :X, :Y)
    @test has_edge(admg, :Y, :Z)
end

@testitem "latent_project with multiple latents" tags = [:unit] begin
    dag = caugi(
        directed(:L1, :X),
        directed(:L1, :Y),
        directed(:L2, :Y),
        directed(:L2, :Z),
        directed(:X, :Y),
        directed(:Y, :Z);
        class = DAG,
    )
    admg = latent_project(dag, [:L1, :L2])
    @test admg isa ADMG
    @test length(nodes(admg)) == 3
    @test Set(nodes(admg)) == Set([:X, :Y, :Z])
end

@testitem "latent_project all nodes latent returns empty" tags = [:unit] begin
    dag = caugi(directed(:L1, :L2); class = DAG)
    admg = latent_project(dag, [:L1, :L2])
    @test admg isa ADMG
    @test length(nodes(admg)) == 0
end

# ── latent_project edge cases ────────────────────────────────────────────────

@testitem "latent_project rejects unknown node name" tags = [:unit] begin
    dag = caugi(directed(:X, :Y); class = DAG)
    @test_throws ErrorException latent_project(dag, [:Z])
end

@testitem "latent_project rejects non-DAG graph" tags = [:unit] begin
    g_pdag = caugi(undirected(:A, :B); class = PDAG)
    @test_throws MethodError latent_project(g_pdag, [:A])
end

# ── exogenize ─────────────────────────────────────────────────────────────────

@testitem "exogenize makes node exogenous, adds parent-to-child edges" tags = [:unit] begin
    cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = exogenize(cg, [:B])
    @test isempty(parents(g2, :B))
    @test :C in children(g2, :B)  # B-->C preserved
    @test :C in children(g2, :A)  # A-->C added (A was parent of B, C was child of B)
end

@testitem "exogenize is idempotent for repeated nodes" tags = [:unit] begin
    cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    g_once = exogenize(cg, [:B])
    g_twice = exogenize(cg, [:B, :B])
    @test Set(nodes(g_once)) == Set(nodes(g_twice))
    @test length(g_once.edges) == length(g_twice.edges)
end

@testitem "exogenize rejects unknown node" tags = [:unit] begin
    cg = caugi(directed(:A, :B); class = DAG)
    @test_throws ErrorException exogenize(cg, [:Z])
end

@testitem "exogenize multiple nodes" tags = [:unit] begin
    cg = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = DAG)
    g2 = exogenize(cg, [:B, :C])
    @test isempty(parents(g2, :B))
    @test isempty(parents(g2, :C))
    @test :D in children(g2, :A)  # A-->D added via chain
end

# ── dag_from_pdag ───────────────────────────────────────

@testitem "dag_from_pdag converts a valid PDAG to a DAG" tags = [:unit] begin
    pdag = caugi(undirected(:A, :B), undirected(:B, :C); class = PDAG)
    dag = dag_from_pdag(pdag)
    @test dag isa DAG
    @test all(
        e ->
            e.src_end == CausalGraphInterface.Tail &&
            e.dst_end == CausalGraphInterface.Arrow,
        dag.edges,
    )
    @test Set(nodes(dag)) == Set(nodes(pdag))
    @test length(dag.edges) == 2
end

@testitem "dag_from_pdag errors on non-extendable PDAG" tags = [:unit] begin
    # 4-cycle A-B-C-D-A: cannot be oriented into a DAG
    pdag = caugi(
        undirected(:A, :B),
        undirected(:A, :D),
        undirected(:B, :C),
        undirected(:C, :D);
        class = PDAG,
    )
    @test_throws ErrorException dag_from_pdag(pdag)
end

@testitem "dag_from_pdag preserves directed edges in mixed graph" tags = [:unit] begin
    pdag = caugi(
        directed(:A, :B),
        directed(:C, :B),
        undirected(:C, :D),
        undirected(:D, :A);
        class = PDAG,
    )
    dag = dag_from_pdag(pdag)
    @test dag isa DAG
    has_dir(cg, u, v) = any(e -> e.src == u && e.dst == v, cg.edges)
    @test has_dir(dag, :A, :B)
    @test has_dir(dag, :C, :B)
    @test xor(has_dir(dag, :A, :D), has_dir(dag, :D, :A))
    @test xor(has_dir(dag, :C, :D), has_dir(dag, :D, :C))
    @test length(dag.edges) == 4
end

@testitem "dag_from_pdag orients each undirected edge exactly once" tags = [:unit] begin
    pdag = caugi(directed(:A, :C), directed(:B, :C), undirected(:A, :D); class = PDAG)
    dag = dag_from_pdag(pdag)
    @test dag isa DAG
    has_dir(cg, u, v) = any(e -> e.src == u && e.dst == v, cg.edges)
    @test has_dir(dag, :A, :C)
    @test has_dir(dag, :B, :C)
    @test xor(has_dir(dag, :A, :D), has_dir(dag, :D, :A))
    @test !any(
        e ->
            e.src_end == CausalGraphInterface.Tail &&
            e.dst_end == CausalGraphInterface.Tail,
        dag.edges,
    )
    @test length(dag.edges) == 3
end

# ── meek_closure ──────────────────────────────────────────────────────────────

@testitem "meek_closure R1: orient compelled edge" tags = [:unit] begin
    # C --> B --- D, C not adjacent to D --> orient B --> D
    cg = caugi(
        directed(:A, :B),
        directed(:C, :B),
        undirected(:B, :D),
        undirected(:A, :D);
        class = PDAG,
    )
    closed = meek_closure(cg)
    @test closed isa MPDAG
    @test :D in children(closed, :B)
    @test :B in parents(closed, :D)
    # preserved directed edges
    @test :B in children(closed, :A)
    @test :B in children(closed, :C)
end

@testitem "meek_closure R1 collider guard: do not create new unshielded collider" tags =
    [:unit] begin
    # A --> B, D --> C, B --- C: R1 would fire (A not adj C), but orienting B --> C
    # would create unshielded collider D --> C <-- B (D not adj B) - guard blocks it.
    pdag = caugi(directed(:A, :B), directed(:D, :C), undirected(:B, :C); class = PDAG)
    closed = meek_closure(pdag)
    @test closed isa MPDAG
    @test has_edge(closed, :B, :C) || has_edge(closed, :C, :B)  # some edge exists
    @test !(:C in children(closed, :B))  # B --> C must NOT be oriented
end

@testitem "meek_closure R2: orient along directed path" tags = [:unit] begin
    # A --> C --> B and A --- B --> orient A --> B
    cg = caugi(undirected(:A, :B), directed(:A, :C), directed(:C, :B); class = PDAG)
    closed = meek_closure(cg)
    @test closed isa MPDAG
    @test :B in children(closed, :A)
    @test :B in children(closed, :C)
end

@testitem "meek_closure matches causal-learn regression" tags = [:unit] begin
    # R3 fires: B --> D (B is undirected nbr of A,C ∈ pa[D], A-C not adjacent)
    # R1 fires: D --> E (parent A of D not adjacent to E)
    # R2 fires: C --> E (C --> D --> E and C --- E)
    cg = caugi(
        undirected(:A, :B),
        undirected(:B, :C),
        directed(:A, :D),
        directed(:C, :D),
        undirected(:B, :D),
        undirected(:D, :E),
        undirected(:C, :E);
        class = PDAG,
    )
    closed = meek_closure(cg)
    @test closed isa MPDAG
    @test :D in children(closed, :B)
    @test :E in children(closed, :D)
    @test :E in children(closed, :C)
    # skeleton preserved
    has_edge_either(cg, u, v) = has_edge(cg, u, v) || has_edge(cg, v, u)
    @test has_edge_either(closed, :A, :B)
    @test has_edge_either(closed, :B, :C)
    # preserved original directed edges
    @test :D in children(closed, :A)
    @test :D in children(closed, :C)
end

# ── normalize_latent_structure ────────────────────────────────────────────────

@testitem "normalize_latent_structure drops singleton latent" tags = [:unit] begin
    # U-->X only: U has ≤1 child --> removed
    dag = caugi(directed(:U, :X); class = DAG)
    norm = normalize_latent_structure(dag, [:U])
    @test :U ∉ nodes(norm)
    @test :X in nodes(norm)
end

@testitem "normalize_latent_structure exogenizes then keeps latent with 2+ children" tags =
    [:unit] begin
    # A-->U-->X, U-->Y: U has 2 children --> kept; A-->X, A-->Y added by exogenize
    dag = caugi(directed(:A, :U), directed(:U, :X), directed(:U, :Y); class = DAG)
    norm = normalize_latent_structure(dag, [:U])
    @test :U in nodes(norm)
    @test isempty(parents(norm, :U))   # exogenized
    @test :X in children(norm, :A)
    @test :Y in children(norm, :A)
end

@testitem "normalize_latent_structure removes nested child set" tags = [:unit] begin
    # U-->{X,Y,Z}, W-->{X,Y}: W's child set ⊂ U's --> W dropped
    dag = caugi(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:U, :Z),
        directed(:W, :X),
        directed(:W, :Y);
        class = DAG,
    )
    norm = normalize_latent_structure(dag, [:U, :W])
    @test :U in nodes(norm)
    @test :W ∉ nodes(norm)
end

@testitem "normalize_latent_structure rejects unknown latent" tags = [:unit] begin
    dag = caugi(directed(:X, :Y); class = DAG)
    @test_throws ErrorException normalize_latent_structure(dag, [:Z])
end

@testitem "normalize_latent_structure empty latent list returns same graph" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    norm = normalize_latent_structure(dag, Symbol[])
    @test Set(nodes(norm)) == Set(nodes(dag))
end

@testitem "normalize_latent_structure preserves latent_project equivalence" tags = [:unit] begin
    # latent_project on dag and norm should give same ADMG
    dag = caugi(directed(:A, :U), directed(:U, :X), directed(:U, :Y); class = DAG)
    norm = normalize_latent_structure(dag, [:U])
    admg1 = latent_project(dag, [:U])
    admg2 = latent_project(norm, [:U])
    @test Set(nodes(admg1)) == Set(nodes(admg2))
    # Both should have X<->Y (shared latent)
    @test :Y in spouses(admg1, :X)
    @test :Y in spouses(admg2, :X)
end

# ── condition_marginalize ─────────────────────────────────────────────────────

@testitem "condition_marginalize: marginalize yields bidirected edge" tags = [:unit] begin
    # Figure 10 (Richardson & Spirtes 2002): U-->X, U-->Y, A-->X, B-->Y
    # Marginalizing U: X<->Y added, A-->X and B-->Y preserved
    cg = caugi(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:A, :X),
        directed(:B, :Y);
        class = DAG,
    )
    mg = condition_marginalize(cg; marg_vars = [:U])
    @test mg isa AG
    @test Set(nodes(mg)) == Set([:A, :B, :X, :Y])
    has_edge_type(cg, u, v, f) = any(e -> e.src == u && e.dst == v && f(e), cg.edges)
    @test has_edge_type(mg, :A, :X, e -> CausalGraphInterface.is_directed(e))
    @test has_edge_type(mg, :B, :Y, e -> CausalGraphInterface.is_directed(e))
    @test any(
        e -> CausalGraphInterface.is_bidirected(e) && Set([e.src, e.dst]) == Set([:X, :Y]),
        mg.edges,
    )
end

@testitem "condition_marginalize: conditioning removes node, keeps structure" tags = [:unit] begin
    # Conditioning on U: removes U from graph, remaining nodes A,B,X,Y
    cg = caugi(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:A, :X),
        directed(:B, :Y);
        class = DAG,
    )
    mg = condition_marginalize(cg; cond_vars = [:U])
    @test mg isa AG
    @test Set(nodes(mg)) == Set([:A, :B, :X, :Y])
    @test :U ∉ nodes(mg)
end

@testitem "condition_marginalize: Figure 11 conditioning on S" tags = [:unit] begin
    # Richardson & Spirtes Figure 11:
    # A-->L1-->B, L2-->B, L2-->C, B-->S, S-->D, D-->C (DAG)
    # Condition on S --> edges become undirected for nodes sharing S in anterior
    f11 = caugi(
        directed(:A, :L1),
        directed(:L1, :B),
        directed(:L2, :B),
        directed(:L2, :C),
        directed(:B, :S),
        directed(:S, :D),
        directed(:D, :C);
        class = DAG,
    )
    result = condition_marginalize(f11; cond_vars = [:S])
    @test result isa AG
    @test Set(nodes(result)) == Set([:A, :B, :C, :D, :L1, :L2])
    has_e(cg, u, v) = has_edge(cg, u, v) || has_edge(cg, v, u)
    # Undirected edges expected
    @test has_e(result, :A, :L1)
    @test has_e(result, :L1, :B)
    @test has_e(result, :L1, :L2)
    @test has_e(result, :L2, :B)
    # Directed edges expected
    @test has_edge(result, :L2, :C) || has_edge(result, :D, :C)
end

@testitem "condition_marginalize: Figure 11 marginalizing L1,L2" tags = [:unit] begin
    f11 = caugi(
        directed(:A, :L1),
        directed(:L1, :B),
        directed(:L2, :B),
        directed(:L2, :C),
        directed(:B, :S),
        directed(:S, :D),
        directed(:D, :C);
        class = DAG,
    )
    result = condition_marginalize(f11; marg_vars = [:L1, :L2])
    @test result isa AG
    @test Set(nodes(result)) == Set([:A, :B, :C, :D, :S])
    has_dir(cg, u, v) =
        any(e -> e.src == u && e.dst == v && CausalGraphInterface.is_directed(e), cg.edges)
    @test has_dir(result, :A, :B)
    @test has_dir(result, :B, :S)
    @test has_dir(result, :S, :D)
    @test has_dir(result, :D, :C)
end

@testitem "condition_marginalize: errors on empty cond/marg" tags = [:unit] begin
    cg = caugi(directed(:A, :B); class = DAG)
    @test_throws ErrorException condition_marginalize(cg)
end

@testitem "condition_marginalize: errors on overlapping cond/marg" tags = [:unit] begin
    cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test_throws ErrorException condition_marginalize(
        cg;
        cond_vars = [:B],
        marg_vars = [:B],
    )
end

@testitem "condition_marginalize: single remaining node returns empty AG" tags = [:unit] begin
    cg = caugi(directed(:A, :B); class = DAG)
    result = condition_marginalize(cg; marg_vars = [:B])
    @test result isa AG
    @test length(nodes(result)) <= 1
end

@testitem "condition_marginalize: accepts AG input" tags = [:unit] begin
    cg = caugi(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:A, :X),
        directed(:B, :Y),
        bidirected(:X, :Z);
        class = AG,
    )
    mg = condition_marginalize(cg; cond_vars = [:U])
    @test mg isa AG
    @test :U ∉ nodes(mg)
end

@testitem "condition_marginalize: accepts MAG input" tags = [:unit] begin
    mag = caugi(directed(:X, :Y), directed(:X, :Z), bidirected(:Y, :Z); class = MAG)
    result = condition_marginalize(mag; marg_vars = [:Z])
    @test result isa AG
    @test :Z ∉ nodes(result)
    @test :X ∈ nodes(result) && :Y ∈ nodes(result)
end

# ── markov_equivalent ─────────────────────────────────────────────────────

@testitem "markov_equivalent: identical DAGs are equivalent" tags = [:unit] begin
    g1 = caugi(directed(:A, :B), directed(:C, :B); class = DAG)
    g2 = caugi(directed(:A, :B), directed(:C, :B); class = DAG)
    @test markov_equivalent(g1, g2)
end

@testitem "markov_equivalent: reversed chain is equivalent" tags = [:unit] begin
    # A --> B --> C and C --> B --> A have the same skeleton and no v-structures
    g1 = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = caugi(directed(:C, :B), directed(:B, :A); class = DAG)
    @test markov_equivalent(g1, g2)
end

@testitem "markov_equivalent: fork equivalent to chain" tags = [:unit] begin
    # B --> A, B --> C (fork) vs A --> B --> C (chain) -- same skeleton, no v-structures
    fork = caugi(directed(:B, :A), directed(:B, :C); class = DAG)
    chain = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test markov_equivalent(fork, chain)
end

@testitem "markov_equivalent: v-structure vs chain is not equivalent" tags = [:unit] begin
    # A --> B <-- C (v-structure, A-C not adjacent)
    # vs A --> B --> C (chain, no v-structure)
    vstr = caugi(directed(:A, :B), directed(:C, :B); class = DAG)
    chain = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test !markov_equivalent(vstr, chain)
end

@testitem "markov_equivalent: different skeletons are not equivalent" tags = [:unit] begin
    g1 = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = caugi(directed(:A, :B), directed(:A, :C); class = DAG)
    @test !markov_equivalent(g1, g2)
end

@testitem "markov_equivalent: different node sets are not equivalent" tags = [:unit] begin
    g1 = caugi(directed(:A, :B); class = DAG)
    g2 = caugi(directed(:A, :C); class = DAG)
    @test !markov_equivalent(g1, g2)
end

@testitem "markov_equivalent: single-node DAGs are equivalent" tags = [:unit] begin
    g1 = caugi(node(:A); class = DAG)
    g2 = caugi(node(:A); class = DAG)
    @test markov_equivalent(g1, g2)
end

@testitem "markov_equivalent: shielded collider does not count as v-structure" tags =
    [:unit] begin
    # A --> B <-- C with A-C adjacent is shielded -- all orientations of this
    # triangle are equivalent (no v-structure distinguishes them).
    triangle_v = caugi(directed(:A, :B), directed(:C, :B), directed(:A, :C); class = DAG)
    triangle_c = caugi(directed(:A, :B), directed(:C, :B), directed(:C, :A); class = DAG)
    @test markov_equivalent(triangle_v, triangle_c)
end

@testitem "markov_equivalent: consistent with dag_to_cpdag" tags = [:unit] begin
    # Enumerate all DAGs on 3 nodes and verify: g1,g2 Markov equivalent
    # iff dag_to_cpdag gives the same edge set.
    function cpdag_edges(g)
        cp = dag_to_cpdag(g)
        Set(Set([e.src, e.dst]) => (e.src_end, e.dst_end) for e in cp.edges)
    end
    same_cpdag(g1, g2) = begin
        cp1 = dag_to_cpdag(g1)
        cp2 = dag_to_cpdag(g2)
        Set(cp1.edges) == Set(cp2.edges)
    end
    nodes3 = [:X, :Y, :Z]
    all_edges = [
        directed(:X, :Y),
        directed(:Y, :X),
        directed(:X, :Z),
        directed(:Z, :X),
        directed(:Y, :Z),
        directed(:Z, :Y),
    ]
    # Build all acyclic subsets
    dags = DAG[]
    for mask = 0:(2^6-1)
        selected = [all_edges[i] for i = 1:6 if (mask >> (i-1)) & 1 == 1]
        try
            g = caugi(selected..., node(:X), node(:Y), node(:Z); class = DAG)
            push!(dags, g)
        catch
        end
    end
    for i in eachindex(dags), j in eachindex(dags)
        @test markov_equivalent(dags[i], dags[j]) == same_cpdag(dags[i], dags[j])
    end
end
