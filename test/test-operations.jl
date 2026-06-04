# Ported from caugi/tests/testthat/test-operations.R
# Verb-based tests (add_edge, set_edges, etc.) are skipped.
# Unimplemented operations are marked @test_broken.

using Test
using CausalGraphInterface

# ── skeleton ──────────────────────────────────────────────────────────────────

@testitem "skeleton on DAG produces UG with same skeleton" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:C, :D),
        directed(:D, :E),
        node(:F),
        node(:G);
        class = DAG,
    )
    skel = skeleton(g)
    @test skel isa UG
    @test Set(nodes(skel)) == Set(nodes(g))
    @test all(
        e ->
            e.src_end == CausalGraphInterface.Tail &&
            e.dst_end == CausalGraphInterface.Tail,
        skel.edges,
    )
end

@testitem "skeleton on PDAG produces UG with same skeleton" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:B, :C),
        undirected(:C, :D),
        directed(:D, :E),
        node(:F),
        node(:G);
        class = PDAG,
    )
    skel = skeleton(g)
    @test skel isa UG
    @test Set(nodes(skel)) == Set(nodes(g))
    @test all(
        e ->
            e.src_end == CausalGraphInterface.Tail &&
            e.dst_end == CausalGraphInterface.Tail,
        skel.edges,
    )
end

# ── moralize ──────────────────────────────────────────────────────────────────

@testitem "moralize works on DAGs" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:D, :C),
        directed(:E, :C),
        directed(:D, :B),
        node(:F),
        node(:G);
        class = DAG,
    )
    mg = moralize(g)
    @test mg isa UG
    @test Set(nodes(mg)) == Set(nodes(g))
    @test all(
        e ->
            e.src_end == CausalGraphInterface.Tail &&
            e.dst_end == CausalGraphInterface.Tail,
        mg.edges,
    )

    has_ug_edge(g, u, v) = has_edge(g, u, v) || has_edge(g, v, u)
    @test has_ug_edge(mg, :A, :B)
    @test has_ug_edge(mg, :B, :C)
    @test has_ug_edge(mg, :D, :E)
    @test has_ug_edge(mg, :B, :D)
    @test has_ug_edge(mg, :B, :E)
    @test has_ug_edge(mg, :C, :D)
    @test has_ug_edge(mg, :C, :E)
end

@testitem "moralize fails on non-DAGs" tags = [:unit] begin
    # Julia: no method defined for PDAG/UG → MethodError
    # R: explicit error message "moralize() can only be applied to DAGs."
    g_pdag = caugi(directed(:A, :B), directed(:B, :C), undirected(:C, :D); class = PDAG)
    @test_throws MethodError moralize(g_pdag)

    g_ug = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError moralize(g_ug)
end

# NetworkX moralization tests
# https://github.com/networkx/networkx/blob/main/networkx/algorithms/tests/test_moral.py

@testitem "NetworkX moralize test 1" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:C, :B),
        directed(:D, :A),
        directed(:D, :E),
        directed(:F, :E),
        directed(:G, :E);
        class = DAG,
    )
    mg = moralize(g)
    @test mg isa UG

    has_ug_edge(g, u, v) = has_edge(g, u, v) || has_edge(g, v, u)
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

# ── exogenize (not yet implemented) ──────────────────────────────────────────

@testitem "exogenize (broken)" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test_broken begin
        g2 = exogenize(g, [:B])
        isempty(parents(g2, :B)) && !isempty(parents(g2, :C))
    end
end

# ── dag_from_pdag (not yet implemented) ───────────────────────────────────────

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
    has_dir(g, u, v) = any(e -> e.src == u && e.dst == v, g.edges)
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
    has_dir(g, u, v) = any(e -> e.src == u && e.dst == v, g.edges)
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

# ── meek_closure (not yet implemented) ────────────────────────────────────────

@testitem "meek_closure R1: orient compelled edge (broken)" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:C, :B),
        undirected(:B, :D),
        undirected(:A, :D);
        class = PDAG,
    )
    @test_broken begin
        closed = meek_closure(g)
        :D in children(closed, :B)
    end
end

@testitem "meek_closure R2: orient along directed path (broken)" tags = [:unit] begin
    g = caugi(undirected(:A, :B), directed(:A, :C), directed(:C, :B); class = PDAG)
    @test_broken begin
        closed = meek_closure(g)
        :B in children(closed, :A)
    end
end

@testitem "meek_closure matches causal-learn regression (broken)" tags = [:unit] begin
    g = caugi(
        undirected(:A, :B),
        undirected(:B, :C),
        directed(:A, :D),
        directed(:C, :D),
        undirected(:B, :D),
        undirected(:D, :E),
        undirected(:C, :E);
        class = PDAG,
    )
    @test_broken begin
        closed = meek_closure(g)
        :D in children(closed, :B) &&
            :E in children(closed, :D) &&
            :E in children(closed, :C)
    end
end

# ── condition_marginalize (not yet implemented) ───────────────────────────────

@testitem "condition_marginalize marginalization (broken)" tags = [:unit] begin
    g = caugi(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:A, :X),
        directed(:B, :Y);
        class = DAG,
    )
    @test_broken begin
        mg = condition_marginalize(g; marg_vars = [:U])
        mg isa ADMG
    end
end

@testitem "condition_marginalize conditioning (broken)" tags = [:unit] begin
    g = caugi(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:A, :X),
        directed(:B, :Y);
        class = DAG,
    )
    @test_broken begin
        mg = condition_marginalize(g; cond_vars = [:U])
        length(nodes(mg)) == 4
    end
end
