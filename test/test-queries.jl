# Tests adapted in part from caugi/tests/testthat/test-queries.R


# ── is_acyclic / is_simple ────────────────────────────────────────────────────

@testitem "is_acyclic returns true for DAG/PDAG by class" tags = [:unit, :queries] begin
    dag = DAG(directed(:A, :B), directed(:B, :C), directed(:C, :D))
    @test is_acyclic(dag)
end

@testitem "is_acyclic detects cycles in UNKNOWN graphs" tags = [:unit, :queries] begin
    unknown = UNKNOWN(directed(:A, :B), directed(:B, :C), directed(:C, :A))
    @test !is_acyclic(unknown)
end

@testitem "is_simple reflects graph content" tags = [:unit, :queries] begin
    g_simple = DAG(directed(:A, :B))
    @test is_simple(g_simple)

    g_nonsimple = UNKNOWN(directed(:A, :B), bidirected(:A, :B))
    @test !is_simple(g_nonsimple)
end

# ── is_dag / is_pdag / is_ug / is_admg ───────────────────────────────────────

@testitem "is_dag works" tags = [:unit, :queries] begin
    dag = DAG(directed(:A, :B), directed(:B, :C), directed(:C, :D))
    @test is_dag(dag)

    g2 = PDAG(directed(:A, :B), directed(:B, :C), undirected(:C, :D))
    @test !is_dag(g2)

    # A PDAG with only directed edges is also a DAG
    g3 = PDAG(directed(:A, :B), directed(:B, :C), directed(:C, :D))
    @test is_dag(g3)

    g4 = UNKNOWN(directed(:A, :B), directed(:B, :C), undirected(:C, :D))
    @test !is_dag(g4)
end

@testitem "is_pdag works" tags = [:unit, :queries] begin
    pdag = PDAG(directed(:A, :B), directed(:B, :C), undirected(:C, :D))
    @test is_pdag(pdag)

    # A DAG is also a valid PDAG
    g2 = DAG(directed(:A, :B), directed(:B, :C), directed(:C, :D))
    @test is_pdag(g2)

    # Graph with partially-directed edges is not a PDAG
    g3 = UNKNOWN(directed(:A, :B), directed(:B, :C), partially_directed(:C, :D))
    @test !is_pdag(g3)
end

@testitem "is_ug works" tags = [:unit, :queries] begin
    ug = UG(undirected(:A, :B), undirected(:B, :C), undirected(:C, :D))
    @test is_ug(ug)
    @test is_ug(ug)

    g2 = PDAG(directed(:A, :B), undirected(:B, :C), undirected(:C, :D))
    @test !is_ug(g2)

    g3 = UNKNOWN(undirected(:A, :B), undirected(:B, :C), partially_directed(:C, :D))
    @test !is_ug(g3)
end

@testitem "is_admg works" tags = [:unit, :queries] begin
    # A pure DAG is also a valid ADMG
    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test is_admg(dag)

    g2 = ADMG(directed(:A, :B), bidirected(:A, :C))
    @test is_admg(g2)

    # UG with only undirected edges is NOT an ADMG
    g3 = UG(undirected(:A, :B))
    @test !is_admg(g3)
end

# ── parents / children / neighbors ───────────────────────────────────────────

@testitem "parents returns expected nodes" tags = [:unit, :queries] begin
    cg = PDAG(directed(:A, :B), directed(:B, :C), directed(:A, :D), directed(:D, :B))
    @test Set(parents(cg, :B)) == Set([:A, :D])
    @test isempty(parents(cg, :A))
end

@testitem "children returns expected nodes" tags = [:unit, :queries] begin
    cg = PDAG(directed(:A, :B), directed(:B, :C), undirected(:C, :D), directed(:D, :E))
    @test children(cg, :A) == [:B]
    @test children(cg, :B) == [:C]
    @test children(cg, :D) == [:E]
end

@testitem "neighbors returns adjacency (directed + undirected)" tags = [:unit, :queries] begin
    cg = PDAG(directed(:A, :B), directed(:B, :C), undirected(:B, :D), undirected(:C, :E))
    @test Set(neighbors(cg, :B)) == Set([:A, :C, :D])
    @test Set(neighbors(cg, :C)) == Set([:B, :E])
end

@testitem "parents/children match by node name" tags = [:unit, :queries] begin
    cg = PDAG(directed(:A, :B), directed(:B, :C), undirected(:B, :D), undirected(:C, :E))
    @test children(cg, :A) == [:B]
    @test Set(parents(cg, :B)) == Set([:A])
    @test Set(neighbors(cg, :C)) == Set([:B, :E])
end

@testitem "parents/children are not defined for UG" tags = [:unit, :queries] begin
    ug = UG(undirected(:A, :B))
    @test_throws MethodError parents(ug, :A)
    @test_throws MethodError children(ug, :B)
end

@testitem "neighbors for UG returns undirected adjacency" tags = [:unit, :queries] begin
    ug = UG(undirected(:A, :B), undirected(:B, :C), undirected(:B, :D))
    @test neighbors(ug, :A) == [:B]
    @test Set(neighbors(ug, :B)) == Set([:A, :C, :D])
    @test neighbors(ug, :C) == [:B]
    @test neighbors(ug, :D) == [:B]
end

# ── ancestors / descendants ───────────────────────────────────────────────────

@testitem "ancestors works on DAG" tags = [:unit, :queries] begin
    cg = DAG(directed(:A, :B), directed(:A, :C), directed(:B, :D), directed(:C, :D))
    @test Set(ancestors(cg, :D)) == Set([:A, :B, :C])
    @test Set(ancestors(cg, :B)) == Set([:A])
    @test isempty(ancestors(cg, :A))
end

@testitem "descendants works on DAG" tags = [:unit, :queries] begin
    cg = DAG(directed(:A, :B), directed(:A, :C), directed(:B, :D), directed(:C, :D))
    @test Set(descendants(cg, :A)) == Set([:B, :C, :D])
    @test Set(descendants(cg, :B)) == Set([:D])
    @test isempty(descendants(cg, :D))
end

@testitem "ancestors/descendants open vs closed definition" tags = [:unit, :queries] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    # open = true (default): excludes the node itself
    @test ancestors(dag, :B) == [:A]
    # open = false (closed): includes the node itself
    @test Set(ancestors(dag, :B; open = false)) == Set([:B, :A])
    @test Set(descendants(dag, :A; open = false)) == Set([:A, :B, :C])
end

@testitem "ancestors errors on UG" tags = [:unit, :queries] begin
    ug = UG(undirected(:A, :B), undirected(:B, :C))
    @test_throws MethodError ancestors(ug, :B)
end

@testitem "descendants errors on UG" tags = [:unit, :queries] begin
    ug = UG(undirected(:A, :B), undirected(:B, :C))
    @test_throws MethodError descendants(ug, :B)
end

# NetworkX ancestors/descendants tests
# https://github.com/networkx/networkx/blob/main/networkx/algorithms/tests/test_dag.py

@testitem "ancestors NetworkX 1 test" tags = [:unit, :queries] begin
    cg = DAG(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:D, :E),
        directed(:D, :C),
        directed(:B, :F),
        directed(:E, :F),
    )
    @test Set(ancestors(cg, :F)) == Set([:A, :B, :D, :E])
    @test Set(ancestors(cg, :C)) == Set([:A, :D])
    @test isempty(ancestors(cg, :A))
end

@testitem "descendants NetworkX 1 test" tags = [:unit, :queries] begin
    cg = DAG(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:D, :E),
        directed(:D, :C),
        directed(:B, :F),
        directed(:E, :F),
    )
    @test Set(descendants(cg, :A)) == Set([:B, :C, :F])
    @test Set(descendants(cg, :D)) == Set([:B, :C, :E, :F])
    @test isempty(descendants(cg, :C))
end

# ── markov_blanket ────────────────────────────────────────────────────────────

@testitem "markov_blanket works on DAGs (parents, children, spouses)" tags =
    [:unit, :queries] begin
    cg = DAG(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:B, :E),
        directed(:F, :E),
    )
    @test Set(markov_blanket(cg, :A)) == Set([:B, :C, :D])
    @test Set(markov_blanket(cg, :B)) == Set([:A, :D, :E, :F])
end

@testitem "markov_blanket includes undirected neighbors in PDAGs" tags = [:unit, :queries] begin
    pdag = PDAG(directed(:A, :B), undirected(:B, :C), directed(:D, :B))
    @test Set(markov_blanket(pdag, :B)) == Set([:A, :C, :D])
end

@testitem "markov_blanket multi-parent fixture on DAGs" tags = [:unit, :queries] begin
    cg = DAG(
        directed(:W, :Y),
        directed(:X, :W),
        directed(:Z1, :X),
        directed(:Z1, :Z3),
        directed(:Z2, :Y),
        directed(:Z2, :Z3),
        directed(:Z3, :X),
        directed(:Z3, :Y),
    )
    @test Set(markov_blanket(cg, :Z1)) == Set([:X, :Z2, :Z3])
    @test Set(markov_blanket(cg, :Y)) == Set([:W, :Z2, :Z3])
end

@testitem "markov_blanket errors on UG" tags = [:unit, :queries] begin
    ug = UG(undirected(:A, :B), undirected(:B, :C))
    @test_throws MethodError markov_blanket(ug, :B)
end

# ── exogenous_nodes ───────────────────────────────────────────────────────────

@testitem "exogenous_nodes works on DAG" tags = [:unit, :queries] begin
    cg = DAG(
        directed(:A, :B),
        directed(:A, :C),
        directed(:D, :B),
        directed(:B, :E),
        directed(:F, :E),
    )
    @test Set(exogenous_nodes(cg)) == Set([:A, :D, :F])
end

@testitem "exogenous_nodes works on PDAG" tags = [:unit, :queries] begin
    pdag = PDAG(undirected(:A, :B), directed(:C, :A))
    @test Set(exogenous_nodes(pdag)) == Set([:B, :C])
end

@testitem "exogenous_nodes works on UG" tags = [:unit, :queries] begin
    ug = UG(undirected(:A, :B), undirected(:B, :C))
    @test isempty(exogenous_nodes(ug))
    g_iso = UG(undirected(:A, :B), node(:C))
    @test exogenous_nodes(g_iso) == [:C]
end

# ── possible_ancestors / possible_descendants ─────────────────────────────────

@testitem "possible_ancestors on CPDAG: undirected chain" tags = [:unit, :queries] begin
    # A --- B --- C: all edges reversible
    cpdag = CPDAG(undirected(:A, :B), undirected(:B, :C))
    @test isempty(ancestors(cpdag, :C))
    @test Set(possible_ancestors(cpdag, :C)) == Set([:A, :B])
    @test isempty(ancestors(cpdag, :A))
    @test Set(possible_ancestors(cpdag, :A)) == Set([:B, :C])
end

@testitem "possible_ancestors on CPDAG: compelled v-structure" tags = [:unit, :queries] begin
    # A --> C <-- B: both edges compelled; possible ancestors == definite ancestors
    cpdag = CPDAG(directed(:A, :C), directed(:B, :C))
    @test Set(possible_ancestors(cpdag, :C)) == Set([:A, :B])
    @test Set(ancestors(cpdag, :C)) == Set([:A, :B])
    @test isempty(possible_ancestors(cpdag, :A))
end

@testitem "possible_ancestors on CPDAG: mixed directed and undirected" tags =
    [:unit, :queries] begin
    # Valid CPDAG: B---A, B---D, C-->E<--B, D-->F<--E
    cpdag = CPDAG(
        undirected(:B, :A),
        undirected(:B, :D),
        directed(:C, :E),
        directed(:B, :E),
        directed(:D, :F),
        directed(:E, :F),
    )
    # Definite ancestors of F: D, E, B, C (all via compelled directed paths)
    @test Set(ancestors(cpdag, :F)) == Set([:D, :E, :B, :C])
    # Possible ancestors of F: additionally A (reachable via B---A, and B is a definite ancestor)
    @test Set(possible_ancestors(cpdag, :F)) == Set([:A, :B, :C, :D, :E])
end

@testitem "possible_ancestors open/closed definition" tags = [:unit, :queries] begin
    cpdag = CPDAG(undirected(:A, :B), undirected(:B, :C))
    @test Set(possible_ancestors(cpdag, :C; open = false)) == Set([:A, :B, :C])
    @test :C ∉ possible_ancestors(cpdag, :C)
end

@testitem "possible_descendants on CPDAG: undirected chain" tags = [:unit, :queries] begin
    cpdag = CPDAG(undirected(:A, :B), undirected(:B, :C))
    @test isempty(descendants(cpdag, :A))
    @test Set(possible_descendants(cpdag, :A)) == Set([:B, :C])
    @test isempty(descendants(cpdag, :C))
    @test Set(possible_descendants(cpdag, :C)) == Set([:A, :B])
end

@testitem "possible_descendants on CPDAG: compelled v-structure" tags = [:unit, :queries] begin
    cpdag = CPDAG(directed(:A, :C), directed(:B, :C))
    @test isempty(possible_descendants(cpdag, :C))
    @test Set(possible_descendants(cpdag, :A)) == Set([:C])
end

@testitem "possible_descendants open/closed definition" tags = [:unit, :queries] begin
    cpdag = CPDAG(undirected(:A, :B), undirected(:B, :C))
    @test Set(possible_descendants(cpdag, :A; open = false)) == Set([:A, :B, :C])
    @test :A ∉ possible_descendants(cpdag, :A)
end

@testitem "possible_ancestors/descendants are supersets of ancestors/descendants" tags =
    [:unit, :queries] begin
    cpdag = CPDAG(
        undirected(:B, :A),
        undirected(:B, :D),
        directed(:C, :E),
        directed(:B, :E),
        directed(:D, :F),
        directed(:E, :F),
    )
    for node in [:A, :B, :C, :D, :E, :F]
        @test issubset(Set(ancestors(cpdag, node)), Set(possible_ancestors(cpdag, node)))
        @test issubset(
            Set(descendants(cpdag, node)),
            Set(possible_descendants(cpdag, node)),
        )
    end
end

@testitem "possible_ancestors/descendants on MPDAG: partially directed cycles are unsound to ignore" tags =
    [:unit, :queries] begin
    # D --> B added as background knowledge to a 4-cycle CPDAG (Perković,
    # Kalisch & Maathuis 2017/2018, Figure 1c): B --- C --- D and B --- A --- D
    # look possibly-directed, but completing either creates a cycle with D --> B.
    mpdag = MPDAG(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:D, :A),
        directed(:D, :B),
    )
    @test :D ∉ possible_descendants(mpdag, :B)
    @test :B ∉ possible_ancestors(mpdag, :D)

    # The compelled edge itself is unaffected.
    @test :B in possible_descendants(mpdag, :D)
    @test :D in possible_ancestors(mpdag, :B)
end

@testitem "possible_ancestors/descendants on CPDAG are unaffected by the MPDAG fix" tags =
    [:unit, :queries] begin
    # The CPDAG the MPDAG above added background knowledge to: same 4-cycle
    # plus a B-D chord (needed for the undirected component to be chordal).
    cpdag = CPDAG(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:D, :A),
        undirected(:B, :D),
    )
    for node in [:A, :B, :C, :D]
        others = setdiff([:A, :B, :C, :D], [node])
        @test Set(possible_descendants(cpdag, node)) == Set(others)
        @test Set(possible_ancestors(cpdag, node)) == Set(others)
    end
end

# ── possible_parent_sets ──────────────────────────────────────────────────────

@testitem "possible_parent_sets matches the worked example (Maathuis, Kalisch & Bühlmann 2009, Fig. 2)" tags =
    [:unit, :queries] begin
    cpdag = CPDAG("X1 --- X2 + X3 + X4, X3 + X4 --> Y")
    result = possible_parent_sets(cpdag, :X1)
    @test length(result) == 4
    @test Set(Set.(result)) == Set([Set{Symbol}(), Set([:X2]), Set([:X3]), Set([:X4])])
end

@testitem "possible_parent_sets returns a single set when x has no undirected neighbors" tags =
    [:unit, :queries] begin
    cpdag = CPDAG(directed(:A, :B), directed(:C, :B))
    @test possible_parent_sets(cpdag, :B) == [[:A, :C]]
    @test possible_parent_sets(cpdag, :A) == [Symbol[]]
end

@testitem "possible_parent_sets excludes subsets that create a new v-structure" tags =
    [:unit, :queries] begin
    # A --- B --- C, A and C not adjacent: {A, C} would create a new v-structure at B
    cpdag = CPDAG(undirected(:A, :B), undirected(:B, :C))
    result = Set(Set.(possible_parent_sets(cpdag, :B)))
    @test result == Set([Set{Symbol}(), Set([:A]), Set([:C])])
    @test Set([:A, :C]) ∉ result
end

@testitem "possible_parent_sets: sets agree with parents over the DAGs in the equivalence class (Theorem 3.2)" tags =
    [:unit, :queries] begin
    cpdag = CPDAG(
        undirected(:B, :A),
        undirected(:B, :D),
        directed(:C, :E),
        directed(:B, :E),
        directed(:D, :F),
        directed(:E, :F),
    )
    dags = enumerate_dags(cpdag)
    for x in [:A, :B, :C, :D, :E, :F]
        from_local = Set(Set.(possible_parent_sets(cpdag, x)))
        from_dags = Set(Set(parents(dag, x)) for dag in dags)
        @test from_local == from_dags
    end
end

# ── possible_ancestors / possible_descendants on PAG ─────────────────────────

@testitem "possible_ancestors on PAG: unshielded collider (o-> edges)" tags =
    [:unit, :queries] begin
    # A --> B <-- C (no A-C edge) produces PAG: A o-> B <-o C
    pag = mag_to_pag(MAG(directed(:A, :B), directed(:C, :B)))
    # A and C are circle-parents of B; their circles can become tails giving A-->B and C-->B
    @test Set(possible_ancestors(pag, :B)) == Set([:A, :C])
    # A has no possible ancestors: B's circle-child arrow at B is a fixed arrowhead
    @test isempty(possible_ancestors(pag, :A))
    @test isempty(possible_ancestors(pag, :C))
end

@testitem "possible_descendants on PAG: unshielded collider (o-> edges)" tags =
    [:unit, :queries] begin
    # A --> B <-- C produces PAG: A o-> B <-o C
    pag = mag_to_pag(MAG(directed(:A, :B), directed(:C, :B)))
    @test Set(possible_descendants(pag, :A)) == Set([:B])
    @test Set(possible_descendants(pag, :C)) == Set([:B])
    # B has no possible descendants: both incident edges have fixed arrowheads at B
    @test isempty(possible_descendants(pag, :B))
end

@testitem "possible_ancestors on PAG: all-circle chain (o-o edges)" tags = [:unit, :queries] begin
    # A --> B --> C: no unshielded collider, so PAG is A o-o B o-o C
    pag = mag_to_pag(MAG(directed(:A, :B), directed(:B, :C)))
    @test Set(possible_ancestors(pag, :C)) == Set([:A, :B])
    @test Set(possible_ancestors(pag, :A)) == Set([:B, :C])
    @test Set(possible_ancestors(pag, :B)) == Set([:A, :C])
end

@testitem "possible_descendants on PAG: all-circle chain (o-o edges)" tags =
    [:unit, :queries] begin
    # A --> B --> C produces PAG: A o-o B o-o C
    pag = mag_to_pag(MAG(directed(:A, :B), directed(:B, :C)))
    @test Set(possible_descendants(pag, :A)) == Set([:B, :C])
    @test Set(possible_descendants(pag, :C)) == Set([:A, :B])
end

@testitem "possible_ancestors on PAG: R1-propagated tail (invariant directed edge)" tags =
    [:unit, :queries] begin
    # A --> C <-- B, C --> D: R1 makes C --> D invariant. PAG: A o-> C <-o B, C --> D
    pag = mag_to_pag(MAG(directed(:A, :C), directed(:B, :C), directed(:C, :D)))
    # Possible ancestors of D: C (definite parent), A and B (possible parents of C)
    @test Set(possible_ancestors(pag, :D)) == Set([:A, :B, :C])
    @test isempty(possible_ancestors(pag, :A))
end

@testitem "possible_descendants on PAG: R1-propagated tail" tags = [:unit, :queries] begin
    # A --> C <-- B, C --> D: PAG: A o-> C <-o B, C --> D
    pag = mag_to_pag(MAG(directed(:A, :C), directed(:B, :C), directed(:C, :D)))
    @test Set(possible_descendants(pag, :A)) == Set([:C, :D])
    @test isempty(possible_descendants(pag, :D))
end

@testitem "possible_ancestors on PAG: open/closed kwarg" tags = [:unit, :queries] begin
    pag = mag_to_pag(MAG(directed(:A, :B), directed(:C, :B)))
    @test :B ∉ possible_ancestors(pag, :B)
    @test :B ∈ possible_ancestors(pag, :B; open = false)
end

# ── anteriors / posteriors ────────────────────────────────────────────────────

@testitem "anteriors works for DAG (equals ancestors)" tags = [:unit, :queries] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test isempty(anteriors(dag, :A))
    @test anteriors(dag, :B) == [:A]
    @test Set(anteriors(dag, :C)) == Set([:A, :B])
end

@testitem "anteriors works for ADMG (equals ancestors)" tags = [:unit, :queries] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C), bidirected(:A, :C))
    @test isempty(anteriors(admg, :A))
    @test anteriors(admg, :B) == [:A]
    @test Set(anteriors(admg, :C)) == Set([:A, :B])
end

@testitem "anteriors works for PDAG with mixed edges" tags = [:unit, :queries] begin
    # A -> B --- C, B -> D
    pdag = PDAG(directed(:A, :B), undirected(:B, :C), directed(:B, :D))
    @test isempty(anteriors(pdag, :A))
    @test Set(anteriors(pdag, :B)) == Set([:A, :C])
    @test Set(anteriors(pdag, :C)) == Set([:A, :B])
    @test Set(anteriors(pdag, :D)) == Set([:A, :B, :C])
end

@testitem "anteriors works for PDAG with undirected cycle" tags = [:unit, :queries] begin
    # A --- B --- C --- A (triangle)
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C), undirected(:C, :A))
    @test Set(anteriors(pdag, :A)) == Set([:B, :C])
    @test Set(anteriors(pdag, :B)) == Set([:A, :C])
    @test Set(anteriors(pdag, :C)) == Set([:A, :B])
end

@testitem "anteriors errors on UG" tags = [:unit, :queries] begin
    ug = UG(undirected(:A, :B), undirected(:B, :C))
    @test_throws MethodError anteriors(ug, :B)
end

@testitem "posteriors works for DAG (equals descendants)" tags = [:unit, :queries] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test Set(posteriors(dag, :A)) == Set([:B, :C])
    @test posteriors(dag, :B) == [:C]
    @test isempty(posteriors(dag, :C))
end

@testitem "posteriors works for ADMG (equals descendants)" tags = [:unit, :queries] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C), bidirected(:A, :C))
    @test Set(posteriors(admg, :A)) == Set([:B, :C])
    @test posteriors(admg, :B) == [:C]
    @test isempty(posteriors(admg, :C))
end

@testitem "posteriors works for PDAG with mixed edges" tags = [:unit, :queries] begin
    # A -> B --- C, B -> D
    pdag = PDAG(directed(:A, :B), undirected(:B, :C), directed(:B, :D))
    @test Set(posteriors(pdag, :A)) == Set([:B, :C, :D])
    @test Set(posteriors(pdag, :B)) == Set([:C, :D])
    @test Set(posteriors(pdag, :C)) == Set([:B, :D])
    @test isempty(posteriors(pdag, :D))
end

@testitem "posteriors works for PDAG with undirected cycle" tags = [:unit, :queries] begin
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C), undirected(:C, :A))
    @test Set(posteriors(pdag, :A)) == Set([:B, :C])
    @test Set(posteriors(pdag, :B)) == Set([:A, :C])
    @test Set(posteriors(pdag, :C)) == Set([:A, :B])
end

@testitem "posteriors errors on UG" tags = [:unit, :queries] begin
    ug = UG(undirected(:A, :B), undirected(:B, :C))
    @test_throws MethodError posteriors(ug, :B)
end

@testitem "posteriors excludes the node itself" tags = [:unit, :queries] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test !(:A in posteriors(dag, :A))
end

@testitem "posteriors does not return duplicates in undirected cycles" tags =
    [:unit, :queries] begin
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C), undirected(:C, :A))
    res = posteriors(pdag, :A)
    @test length(res) == length(unique(res))
end

@testitem "posteriors handles multi-step mixed reachability" tags = [:unit, :queries] begin
    # A -> B --- C --- D -> E
    cg = PDAG(directed(:A, :B), undirected(:B, :C), undirected(:C, :D), directed(:D, :E))
    @test Set(posteriors(cg, :A)) == Set([:B, :C, :D, :E])
end

@testitem "posteriors handles disconnected components" tags = [:unit, :queries] begin
    dag = DAG(directed(:A, :B), directed(:C, :D))
    @test posteriors(dag, :A) == [:B]
    @test !(:A in posteriors(dag, :C))
end

@testitem "closed definition for ancestors/anteriors/descendants/posteriors" tags =
    [:unit, :queries] begin
    pdag = PDAG(directed(:A, :B), undirected(:B, :C), directed(:B, :D))

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

@testitem "subgraph on DAG" tags = [:unit, :queries] begin
    cg = DAG(directed(:A, :B), directed(:A, :C), directed(:B, :D), directed(:C, :D))
    sg = subgraph(cg, [:A, :B, :D])
    @test sg isa DAG
    @test Set(nodes(sg)) == Set([:A, :B, :D])
    @test has_edge(sg, :A, :B)
    @test !(:C in nodes(sg))
end

@testitem "subgraph on UG" tags = [:unit, :queries] begin
    ug = UG(undirected(:A, :B), undirected(:B, :C))
    sg = subgraph(ug, [:A, :B])
    @test sg isa UG
    @test Set(nodes(sg)) == Set([:A, :B])
    @test has_edge(sg, :A, :B)
end

@testitem "subgraph on PDAG" tags = [:unit, :queries] begin
    pdag = PDAG(directed(:A, :B), undirected(:B, :C))
    sg = subgraph(pdag, [:A, :B])
    @test sg isa PDAG
    @test Set(nodes(sg)) == Set([:A, :B])
    @test has_edge(sg, :A, :B)
end

# ── spouses / districts ─────────────────────────────────

@testitem "spouses works for ADMG" tags = [:unit, :queries] begin
    admg = ADMG(directed(:A, :B), bidirected(:B, :C))
    @test !isempty(spouses(admg, :B))
end

@testitem "districts works for ADMG" tags = [:unit, :queries] begin
    admg = ADMG(bidirected(:A, :B), bidirected(:B, :C), directed(:C, :D))
    @test length(districts(admg)) == 2
end

@testitem "districts works for AG" tags = [:unit, :queries] begin
    ag = AG(bidirected(:A, :B), bidirected(:B, :C), directed(:C, :D))
    @test length(districts(ag)) == 2
end

@testitem "districts works for MAG" tags = [:unit, :queries] begin
    mag = MAG(bidirected(:A, :C), directed(:A, :B), directed(:C, :B))
    dists = districts(mag)
    @test length(dists) == 2
    @test any(d -> Set(d) == Set([:A, :C]), dists)
end

# ── is_cpdag ──────────────────────────────────────────────────────────────────

@testitem "is_cpdag: CPDAG class is always true" tags = [:unit, :queries] begin
    cpdag = CPDAG(directed(:A, :C), directed(:B, :C))
    @test is_cpdag(cpdag)
end

@testitem "is_cpdag: PDAG v-structure is a valid CPDAG" tags = [:unit, :queries] begin
    pdag = PDAG(directed(:A, :C), directed(:B, :C))
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: PDAG single directed edge is not a CPDAG" tags = [:unit, :queries] begin
    # A-->B has no v-structure protecting it
    pdag = PDAG(directed(:A, :B))
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: pure directed chain is not a CPDAG" tags = [:unit, :queries] begin
    pdag = PDAG(directed(:A, :B), directed(:B, :C), directed(:C, :D))
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: undirected edge is a valid CPDAG" tags = [:unit, :queries] begin
    pdag = PDAG(undirected(:A, :B))
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: undirected chain is a valid CPDAG" tags = [:unit, :queries] begin
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C))
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: undirected triangle is a valid CPDAG" tags = [:unit, :queries] begin
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C), undirected(:A, :C))
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: triangle with adjacent parents is not a CPDAG" tags = [:unit, :queries] begin
    # A-->C, B-->C, A---B: A and B are adjacent so no v-structure at C; arrows not protected
    pdag = PDAG(directed(:A, :C), directed(:B, :C), undirected(:A, :B))
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: isolated nodes are a valid CPDAG" tags = [:unit, :queries] begin
    pdag = PDAG(node(:A), node(:B), node(:C))
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: v-structure + isolated nodes is a valid CPDAG" tags = [:unit, :queries] begin
    pdag = PDAG(directed(:A, :C), directed(:B, :C), node(:D), node(:E))
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: non-chordal 4-cycle is not a CPDAG" tags = [:unit, :queries] begin
    cg =
        PDAG(undirected(:A, :B), undirected(:B, :C), undirected(:C, :D), undirected(:D, :A))
    @test !is_cpdag(cg)
end

@testitem "is_cpdag: rejects Meek R1 violation" tags = [:unit, :queries] begin
    # A-->B, B---C, A not adjacent to C: R1 would orient B-->C
    pdag = PDAG(directed(:A, :B), undirected(:B, :C))
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: rejects Meek R2 violation" tags = [:unit, :queries] begin
    # A---B with A-->C-->B: R2 would orient A-->B
    pdag = PDAG(undirected(:A, :B), directed(:A, :C), directed(:C, :B))
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: rejects Meek R3 violation" tags = [:unit, :queries] begin
    # A---B, C-->B, D-->B, C not adj D, A---C, A---D: R3 would orient A-->B
    cg = PDAG(
        undirected(:A, :B),
        directed(:C, :B),
        directed(:D, :B),
        undirected(:A, :C),
        undirected(:A, :D),
    )
    @test !is_cpdag(cg)
end

@testitem "is_cpdag: rejects Meek R4 violation" tags = [:unit, :queries] begin
    # A---B with directed path A-->C-->D-->B: R4 would orient A-->B
    cg = PDAG(undirected(:A, :B), directed(:A, :C), directed(:C, :D), directed(:D, :B))
    @test !is_cpdag(cg)
end

@testitem "is_cpdag: complex valid CPDAG with v-structure + undirected components" tags =
    [:unit, :queries] begin
    # B---A, B---D, C-->E<--B, D-->F<--E
    cg = PDAG(
        undirected(:B, :A),
        undirected(:B, :D),
        directed(:C, :E),
        directed(:B, :E),
        directed(:D, :F),
        directed(:E, :F),
    )
    @test is_cpdag(cg)
end

@testitem "is_cpdag: v-structure with R1 cascade (C-->E<--B, E-->F) is valid" tags =
    [:unit, :queries] begin
    # C-->E, B-->E protects both; E-->F is protected by SP2 (B-->E-->F)
    pdag = PDAG(directed(:A, :C), directed(:B, :C), directed(:C, :D))
    @test is_cpdag(pdag)
end

@testitem "is_cpdag: PDAG with B-->A and B-->C (fork) is not a CPDAG" tags =
    [:unit, :queries] begin
    # B-->A, B-->C: neither edge is protected (no v-structure)
    pdag = PDAG(directed(:B, :A), directed(:B, :C))
    @test !is_cpdag(pdag)
end

@testitem "is_cpdag: CPDAG constructor rejects invalid graph" tags = [:unit, :queries] begin
    @test_throws ErrorException CPDAG(directed(:A, :B))
end

@testitem "is_cpdag: generate_graph(CPDAG) produces valid CPDAGs" tags = [:unit, :queries] begin
    using Random
    for seed = 1:10
        cpdag = generate_graph(Random.Xoshiro(seed), 6; m = 5, class = CPDAG)
        @test is_cpdag(cpdag)
    end
end
