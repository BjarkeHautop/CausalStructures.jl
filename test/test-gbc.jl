# Tests for backdoor_set (Generalized Backdoor Criterion, Maathuis & Colombo 2015).


# ── DAG (Corollary 4.1) ───────────────────────────────────────────────────────

@testitem "backdoor_set DAG: classic confounder" tags = [:unit, :gbc] begin
    cg = DAG("A --> X --> Y, A --> Y")
    @test sort(backdoor_set(cg, :X, :Y)) == [:A]
    @test backdoor_set(cg, :Y, :A) === nothing  # A is a parent of Y
end

@testitem "backdoor_set DAG: no parents gives empty set" tags = [:unit, :gbc] begin
    cg = DAG(directed(:X, :Y))
    @test backdoor_set(cg, :X, :Y) == Symbol[]
end

@testitem "backdoor_set DAG: agrees with a valid adjustment set when it exists" tags =
    [:unit, :gbc] begin
    cg = DAG("C --> X, X --> F, X --> D --> Y, A --> X, A --> K --> Y, D --> G, Y --> H")
    z = backdoor_set(cg, :X, :Y)
    @test z !== nothing
    @test is_valid_adjustment(cg, :X, :Y, z)
end

# ── CPDAG (Corollary 4.2) ─────────────────────────────────────────────────────

@testitem "backdoor_set CPDAG: unshielded colliders protect the parents" tags =
    [:unit, :gbc] begin
    # A --> X <-- C protects both edges into X; X --> Y is the edge of interest.
    cpdag = CPDAG("A --> X <-- C, X --> Y")
    @test sort(backdoor_set(cpdag, :X, :Y)) == [:A, :C]
end

@testitem "backdoor_set CPDAG: undirected edge to Y makes Y a possible descendant" tags =
    [:unit, :gbc] begin
    cpdag = CPDAG("A --> X <-- C, D --> Y <-- E, X --- Y")
    @test backdoor_set(cpdag, :X, :Y) === nothing
end

@testitem "backdoor_set CPDAG: Y a parent of X has no generalized back-door set" tags =
    [:unit, :gbc] begin
    cpdag = CPDAG("A --> X <-- C, X --> Y")
    @test backdoor_set(cpdag, :Y, :X) === nothing  # X is a parent of Y
end

@testitem "backdoor_set: no method for MPDAG or plain PDAG (unproven scope)" tags =
    [:unit, :gbc] begin
    # Corollary 4.2 doesn't generalize to MPDAG/PDAG -- see the docstring.
    mpdag = MPDAG("Y --> X")
    @test_throws MethodError backdoor_set(mpdag, :X, :Y)

    pdag = PDAG("Y --> X")
    @test_throws MethodError backdoor_set(pdag, :X, :Y)
end

@testitem "backdoor_set CPDAG: agrees with is_valid_adjustment when it exists" tags =
    [:unit, :gbc] begin
    cpdag = CPDAG("A --> X <-- C, X --> Y")
    z = backdoor_set(cpdag, :X, :Y)
    @test z !== nothing
    @test is_valid_adjustment(cpdag, :X, :Y, z)
end

# ── MAG (Corollary 4.3) ───────────────────────────────────────────────────────

@testitem "backdoor_set MAG: confounder blocks the backdoor path" tags = [:unit, :gbc] begin
    mag = MAG(bidirected(:A, :X), directed(:A, :M), directed(:M, :Y), directed(:X, :Y))
    z = backdoor_set(mag, :X, :Y)
    @test z == [:A]
    @test is_valid_adjustment(mag, :X, :Y, z)
end

@testitem "backdoor_set MAG: invisible edge is not identifiable" tags = [:unit, :gbc] begin
    # X --> Y with no other nodes: no witness exists, so the edge is invisible
    # and Y remains adjacent to X in M_X.
    mag = MAG(directed(:X, :Y))
    @test backdoor_set(mag, :X, :Y) === nothing
end

@testitem "backdoor_set MAG: bidirected edge unrelated to Y needs no adjustment" tags =
    [:unit, :gbc] begin
    # A <-> X confounds A and X only; it does not open a path to Y.
    mag = MAG(bidirected(:A, :X), directed(:X, :Y))
    @test backdoor_set(mag, :X, :Y) == Symbol[]
end

@testitem "backdoor_set MAG: rejects graphs with undirected (selection-variable) edges" tags =
    [:unit, :gbc] begin
    mag = MAG(undirected(:A, :X), directed(:X, :Y))
    @test_throws ArgumentError backdoor_set(mag, :X, :Y)
end

# ── PAG (Theorem 4.1) ─────────────────────────────────────────────────────────

@testitem "backdoor_set PAG: agrees with the underlying MAG when the class is fully resolved" tags =
    [:unit, :gbc] begin
    # A and B are both witnesses for a definite arrowhead into X: A o-> X and
    # B o-> X, so every MAG in the class has A, B as into-X edges (k matches).
    mag = MAG(directed(:B, :X), bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y))
    pag = mag_to_pag(mag)
    z_mag = backdoor_set(mag, :X, :Y)
    z_pag = backdoor_set(pag, :X, :Y)
    @test z_mag == [:A, :B]
    @test sort(z_pag) == [:A, :B]
    @test is_valid_adjustment(pag, :X, :Y, z_pag)
end

@testitem "backdoor_set PAG: circle uncertainty at X can make no set identifiable" tags =
    [:unit, :gbc] begin
    # A o-o M and A o-o X: some MAGs in the class direct X --> A, opening a
    # path through A that no single adjustment set blocks for every member.
    mag = MAG(bidirected(:A, :X), directed(:A, :M), directed(:M, :Y), directed(:X, :Y))
    pag = mag_to_pag(mag)
    @test backdoor_set(pag, :X, :Y) === nothing
end

@testitem "backdoor_set PAG: rejects graphs with undirected (selection-variable) edges" tags =
    [:unit, :gbc] begin
    # A 4-cycle of undirected edges is a closed selection-bias PAG (forced by
    # Meek-style rule R5) that round-trips through mag_to_pag as literal ---.
    mag =
        MAG(undirected(:A, :B), undirected(:B, :C), undirected(:C, :D), undirected(:A, :D))
    pag = mag_to_pag(mag)
    @test_throws ArgumentError backdoor_set(pag, :A, :B)
end
