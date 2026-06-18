using Test
using CausalStructures

# Classic front-door graph: U --> X --> M --> Y, U --> Y
# M mediates the entire causal effect of X on Y; U is an unmeasured confounder.
# Z = {M} is the canonical front-door set.

@testsnippet JeongGraphs begin
    # ── Jeong, Tian & Bareinboim (2022) Fig. 1 ───────────────────────────────────
    #
    # Fig. 1b: G': X --> A --> {B, C, D} --> Y
    #   Bidirected X <-> Y (latent U1 -> X, U1 -> Y)
    #   Bidirected X <-> D (latent U2 -> X, U2 -> D)
    #
    #   The four valid FD sets relative to (X, Y) are: {A}, {A,B}, {A,C}, {A,B,C}.
    #   D is excluded from every valid set because the BD path X <-- U2 --> D is open.
    #
    # Reference: Jeong, Tian & Bareinboim (2022). Finding and Listing Front-Door
    #   Adjustment Sets. NeurIPS 2022.

    # Fig. 1b as a DAG with explicit latents.
    function _jeong2022_fig1b()
        cgraph(
            directed(:U1, :X),
            directed(:U1, :Y),
            directed(:U2, :X),
            directed(:U2, :D),
            directed(:X, :A),
            directed(:A, :B),
            directed(:A, :C),
            directed(:A, :D),
            directed(:B, :Y),
            directed(:C, :Y),
            directed(:D, :Y);
            class = DAG,
        )
    end

    # Fig. 6a: G with two parallel mediating paths and one latent confounder.
    # 9 valid FD adjustment sets (3^2): each path i can be intercepted by Ai, Bi, or {Ai,Bi}.
    function _jeong2022_fig6a()
        cgraph(
            directed(:U, :X),
            directed(:U, :Y),
            directed(:X, :A1),
            directed(:A1, :B1),
            directed(:B1, :Y),
            directed(:X, :A2),
            directed(:A2, :B2),
            directed(:B2, :Y);
            class = DAG,
        )
    end

    # Fig. 6b: G' = G with a third parallel mediating path added.
    # 27 valid FD adjustment sets (3^3).
    function _jeong2022_fig6b()
        cgraph(
            directed(:U, :X),
            directed(:U, :Y),
            directed(:X, :A1),
            directed(:A1, :B1),
            directed(:B1, :Y),
            directed(:X, :A2),
            directed(:A2, :B2),
            directed(:B2, :Y),
            directed(:X, :A3),
            directed(:A3, :B3),
            directed(:B3, :Y);
            class = DAG,
        )
    end
end

@testitem "is_valid_frontdoor: M satisfies criterion on classic graph" tags = [:unit] begin
    cg = cgraph(
        directed(:U, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:U, :Y);
        class = DAG,
    )
    @test is_valid_frontdoor(cg, :X, :Y, [:M])
end

@testitem "is_valid_frontdoor: empty Z fails when directed path exists" tags = [:unit] begin
    cg = cgraph(
        directed(:U, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:U, :Y);
        class = DAG,
    )
    @test !is_valid_frontdoor(cg, :X, :Y)
end

@testitem "is_valid_frontdoor: U fails condition (i) - does not intercept X -> M -> Y" tags =
    [:unit] begin
    cg = cgraph(
        directed(:U, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:U, :Y);
        class = DAG,
    )
    @test !is_valid_frontdoor(cg, :X, :Y, [:U])
end

@testitem "is_valid_frontdoor: condition (ii) fails when backdoor path from X to Z exists" tags =
    [:unit] begin
    # A -> X, A -> M, X -> M, M -> Y
    # Backdoor path from X to M: X <- A -> M is open.
    cg = cgraph(
        directed(:A, :X),
        directed(:A, :M),
        directed(:X, :M),
        directed(:M, :Y);
        class = DAG,
    )
    @test !is_valid_frontdoor(cg, :X, :Y, [:M])
end

@testitem "is_valid_frontdoor: condition (iii) fails when X does not block backdoor from Z to Y" tags =
    [:unit] begin
    # X --> M, M --> Y, B --> M, B --> Y
    # Backdoor path from M to Y: M <-- B --> Y is not blocked by X.
    cg = cgraph(
        directed(:X, :M),
        directed(:M, :Y),
        directed(:B, :M),
        directed(:B, :Y);
        class = DAG,
    )
    @test !is_valid_frontdoor(cg, :X, :Y, [:M])
end

@testitem "is_valid_frontdoor: X --> Y direct edge violates condition (i)" tags = [:unit] begin
    # If there is a direct edge X --> Y alongside X --> M --> Y, then M alone does
    # not intercept the direct path.
    cg = cgraph(
        directed(:U, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:X, :Y),
        directed(:U, :Y);
        class = DAG,
    )
    @test !is_valid_frontdoor(cg, :X, :Y, [:M])
    # Both M and the direct path must be intercepted - no single node suffices.
    @test !is_valid_frontdoor(cg, :X, :Y, [:U])
end

@testitem "is_valid_frontdoor: chain mediators - each singleton is valid" tags = [:unit] begin
    # U --> X --> M1 --> M2 --> Y, U --> Y
    # Both {M1} and {M2} individually intercept all directed paths.
    cg = cgraph(
        directed(:U, :X),
        directed(:X, :M1),
        directed(:M1, :M2),
        directed(:M2, :Y),
        directed(:U, :Y);
        class = DAG,
    )
    @test is_valid_frontdoor(cg, :X, :Y, [:M1])
    @test is_valid_frontdoor(cg, :X, :Y, [:M2])
    @test is_valid_frontdoor(cg, :X, :Y, [:M1, :M2])
end

@testitem "is_valid_frontdoor: no causal path - empty Z valid" tags = [:unit] begin
    # X --> A, B --> Y: no directed path from X to Y at all.
    # Empty Z vacuously intercepts all (zero) directed paths.
    cg = cgraph(directed(:X, :A), directed(:B, :Y); class = DAG)
    @test is_valid_frontdoor(cg, :X, :Y)
end

# ── is_valid_frontdoor on G' (Fig. 1b) ───────────────────────────────────────

@testitem "is_valid_frontdoor: Jeong Fig 1b - four valid sets" setup=[JeongGraphs] tags =
    [:unit] begin
    cg = _jeong2022_fig1b()
    @test is_valid_frontdoor(cg, :X, :Y, [:A])
    @test is_valid_frontdoor(cg, :X, :Y, [:A, :B])
    @test is_valid_frontdoor(cg, :X, :Y, [:A, :C])
    @test is_valid_frontdoor(cg, :X, :Y, [:A, :B, :C])
end

@testitem "is_valid_frontdoor: Jeong Fig 1b - invalid sets" setup=[JeongGraphs] tags =
    [:unit] begin
    cg = _jeong2022_fig1b()
    @test !is_valid_frontdoor(cg, :X, :Y, [:B])       # condition (i): A -> C -> Y bypasses B
    @test !is_valid_frontdoor(cg, :X, :Y, [:C])       # condition (i): A -> B -> Y bypasses C
    @test !is_valid_frontdoor(cg, :X, :Y, [:D])       # condition (ii): BD path X <- U2 -> D
    @test !is_valid_frontdoor(cg, :X, :Y, [:A, :D])   # condition (ii): D has BD path from X
end

# ── Example 2: GETCAND2NDFDC ─────────────────────────────────────────────────
#
# With I = ∅ and R = {A, B, C, D}, GETCAND2NDFDC outputs {A, B, C}.
# D is excluded because TESTSEP(G_X, X, D, ∅) = false: the BD path X <- U2 -> D is open.

@testitem "GETCAND2NDFDC: Jeong (2022) Example 2 - D excluded, A B C retained" setup=[
    JeongGraphs,
] tags = [:unit] begin
    cg = _jeong2022_fig1b()
    B = cg.backend
    n = length(B.nodes)
    gx = CausalStructures._build_gx(cg, :X)

    # I = ∅, R = {A, B, C, D}
    i_mask = falses(n)
    r_mask = falses(n)
    for s in [:A, :B, :C, :D]
        r_mask[CausalStructures.node_index(cg, s)] = true
    end

    r_prime = CausalStructures._getcand2ndfdc(gx, :X, B.nodes, i_mask, r_mask)

    @test r_prime !== nothing
    @test Set(B.nodes[v] for v = 1:n if r_prime[v]) == Set([:A, :B, :C])
end

@testitem "GETCAND2NDFDC: Jeong (2022) Example 2 - infeasible when D ∈ I" setup=[
    JeongGraphs,
] tags = [:unit] begin
    cg = _jeong2022_fig1b()
    B = cg.backend
    n = length(B.nodes)
    gx = CausalStructures._build_gx(cg, :X)

    # I = {D}: D must be included but has a BD path from X --> infeasible
    i_mask = falses(n)
    i_mask[CausalStructures.node_index(cg, :D)] = true
    r_mask = falses(n)
    for s in [:A, :B, :C, :D]
        r_mask[CausalStructures.node_index(cg, s)] = true
    end

    @test CausalStructures._getcand2ndfdc(gx, :X, B.nodes, i_mask, r_mask) === nothing
end

# ── Example 3: GETCAND3RDFDC ─────────────────────────────────────────────────
#
# Given I = {} and R' = {A, B, C}, GETCAND3RDFDC outputs R'' = {A, B, C}
# because GETDEP succeeds for every v in R'.

@testitem "GETCAND3RDFDC: Jeong (2022) Example 3 - all of R' retained" setup=[JeongGraphs] tags =
    [:unit] begin
    cg = _jeong2022_fig1b()
    B = cg.backend
    n = length(B.nodes)

    x_idx = CausalStructures.node_index(cg, :X)
    x_set = falses(n)
    x_set[x_idx] = true

    y_mask = falses(n)
    y_mask[CausalStructures.node_index(cg, :Y)] = true

    i_mask = falses(n)
    r_prime_mask = falses(n)
    for s in [:A, :B, :C]
        r_prime_mask[CausalStructures.node_index(cg, s)] = true
    end

    r_dbl_prime = CausalStructures._getcand3rdfdc(B, x_set, y_mask, i_mask, r_prime_mask)

    @test r_dbl_prime !== nothing
    @test Set(B.nodes[v] for v = 1:n if r_dbl_prime[v]) == Set([:A, :B, :C])
end

@testitem "GETCAND3RDFDC: Jeong (2022) Example 3 - infeasible when v in I fails GETDEP" setup=[
    JeongGraphs,
] tags = [:unit] begin
    # R' = {B, C}: GETDEP returns nothing for v=B (Example 5), so if B is required
    # via I, GETCAND3RDFDC must return nothing.
    cg = _jeong2022_fig1b()
    B = cg.backend
    n = length(B.nodes)

    x_idx = CausalStructures.node_index(cg, :X)
    x_set = falses(n)
    x_set[x_idx] = true

    y_mask = falses(n)
    y_mask[CausalStructures.node_index(cg, :Y)] = true

    i_mask = falses(n)
    i_mask[CausalStructures.node_index(cg, :B)] = true  # B required, but GETDEP fails
    r_prime_mask = falses(n)
    for s in [:B, :C]
        r_prime_mask[CausalStructures.node_index(cg, s)] = true
    end

    @test CausalStructures._getcand3rdfdc(B, x_set, y_mask, i_mask, r_prime_mask) ===
          nothing
end

# ── Example 4: GETDEP ────────────────────────────────────────────────────────
#
# G' from Fig. 1b, I = {}, R' = {A, B, C} (output of GETCAND2NDFDC).
#   v = A => T = {A}, GETDEP returns Z' = {}
#   v = B => T = {B}, GETDEP returns Z' = {A}   (Example 4 in the paper)
#   v = C => T = {C}, GETDEP returns Z' = {A}

@testitem "GETDEP: Jeong (2022) Example 4 - T={A}" setup=[JeongGraphs] tags = [:unit] begin
    cg = _jeong2022_fig1b()
    B = cg.backend
    n = length(B.nodes)

    x_idx = CausalStructures.node_index(cg, :X)
    x_set = falses(n)
    x_set[x_idx] = true

    y_mask = falses(n)
    y_mask[CausalStructures.node_index(cg, :Y)] = true

    r_prime_mask = falses(n)
    for s in [:A, :B, :C]
        r_prime_mask[CausalStructures.node_index(cg, s)] = true
    end

    t_mask = falses(n)
    t_mask[CausalStructures.node_index(cg, :A)] = true

    z_prime = CausalStructures._get_dep(B, x_set, y_mask, t_mask, r_prime_mask)

    @test z_prime !== nothing
    @test Set(B.nodes[v] for v = 1:n if z_prime[v]) == Set{Symbol}()
end

@testitem "GETDEP: Jeong (2022) Example 4 - T={B}" setup=[JeongGraphs] tags = [:unit] begin
    cg = _jeong2022_fig1b()
    B = cg.backend
    n = length(B.nodes)

    x_idx = CausalStructures.node_index(cg, :X)
    x_set = falses(n)
    x_set[x_idx] = true

    y_mask = falses(n)
    y_mask[CausalStructures.node_index(cg, :Y)] = true

    r_prime_mask = falses(n)
    for s in [:A, :B, :C]
        r_prime_mask[CausalStructures.node_index(cg, s)] = true
    end

    t_mask = falses(n)
    t_mask[CausalStructures.node_index(cg, :B)] = true

    z_prime = CausalStructures._get_dep(B, x_set, y_mask, t_mask, r_prime_mask)

    @test z_prime !== nothing
    @test Set(B.nodes[v] for v = 1:n if z_prime[v]) == Set([:A])
end

@testitem "GETDEP: Jeong (2022) Example 4 - T={C}" setup=[JeongGraphs] tags = [:unit] begin
    cg = _jeong2022_fig1b()
    B = cg.backend
    n = length(B.nodes)

    x_idx = CausalStructures.node_index(cg, :X)
    x_set = falses(n)
    x_set[x_idx] = true

    y_mask = falses(n)
    y_mask[CausalStructures.node_index(cg, :Y)] = true

    r_prime_mask = falses(n)
    for s in [:A, :B, :C]
        r_prime_mask[CausalStructures.node_index(cg, s)] = true
    end

    t_mask = falses(n)
    t_mask[CausalStructures.node_index(cg, :C)] = true

    z_prime = CausalStructures._get_dep(B, x_set, y_mask, t_mask, r_prime_mask)

    @test z_prime !== nothing
    @test Set(B.nodes[v] for v = 1:n if z_prime[v]) == Set([:A])
end

# ── Example 5: GETDEP with smaller R' => returns nothing ─────────────────────
#
# With R' = {B, C} and T = {B}, GETDEP cannot disconnect all BD paths from T to
# Y while staying within R' \ T = {C}.  The BFS reaches Y (through D --> Y in M)
# before exhausting the queue, so GETDEP returns nothing.
#
# BFS trace (explicit latent-node DAG):
#   u=B  => NR={} (A not in R'), N'={A}              => Q=[A]
#   u=A  => NR={C}, update M to G'_{B,C},
#           N'={C,D,U2}, NR'={C}                     => Q=[C,D,U2]
#   u=C  => NR={}, N'={}
#   u=D  => NR={} (Y,U1 not in R'), N'={Y,U1}        => Q grows
#   u=U2 => all neighbors visited
#   u=Y  => u in Y => return nothing

@testitem "GETDEP: Jeong (2022) Example 5 - R'={B,C}, T={B} returns nothing" setup=[
    JeongGraphs,
] tags = [:unit] begin
    cg = _jeong2022_fig1b()
    B = cg.backend
    n = length(B.nodes)

    x_idx = CausalStructures.node_index(cg, :X)
    x_set = falses(n)
    x_set[x_idx] = true

    y_mask = falses(n)
    y_mask[CausalStructures.node_index(cg, :Y)] = true

    # R' = {B, C} — smaller candidate pool than Example 4
    r_prime_mask = falses(n)
    for s in [:B, :C]
        r_prime_mask[CausalStructures.node_index(cg, s)] = true
    end

    t_mask = falses(n)
    t_mask[CausalStructures.node_index(cg, :B)] = true

    @test CausalStructures._get_dep(B, x_set, y_mask, t_mask, r_prime_mask) === nothing
end

# ── Example 7: GETCAUSALPATHGRAPH ────────────────────────────────────────────
#
# G' from Fig. 1b, X = {X}, Y = {Y}.
# PCP = (De(X) \ X) ∩ An(Y, G_{overline{X}}) = {A, B, C, D} (and Y itself).
# CPG nodes = {X, A, B, C, D, Y}  (latent U1, U2 excluded).
# CPG edges: X --> A --> {B, C, D} --> Y (incoming to X and outgoing from Y removed).

@testitem "GETCAUSALPATHGRAPH: Jeong (2022) Example 7 - node set" setup=[JeongGraphs] tags =
    [:unit] begin
    cg = _jeong2022_fig1b()
    B = cg.backend
    n = length(B.nodes)

    x_set = falses(n)
    x_set[CausalStructures.node_index(cg, :X)] = true
    y_mask = falses(n)
    y_mask[CausalStructures.node_index(cg, :Y)] = true

    cpg_mask, _ = CausalStructures._get_causal_path_graph(B, x_set, y_mask)

    @test Set(B.nodes[v] for v = 1:n if cpg_mask[v]) == Set([:X, :A, :B, :C, :D, :Y])
end

@testitem "GETCAUSALPATHGRAPH: Jeong (2022) Example 7 - edges" setup=[JeongGraphs] tags =
    [:unit] begin
    cg = _jeong2022_fig1b()
    B = cg.backend
    n = length(B.nodes)

    x_set = falses(n)
    x_set[CausalStructures.node_index(cg, :X)] = true
    y_mask = falses(n)
    y_mask[CausalStructures.node_index(cg, :Y)] = true

    _, cpg_children = CausalStructures._get_causal_path_graph(B, x_set, y_mask)

    children(s) = Set(B.nodes[c] for c in cpg_children[CausalStructures.node_index(cg, s)])
    @test children(:X) == Set([:A])
    @test children(:A) == Set([:B, :C, :D])
    @test children(:B) == Set([:Y])
    @test children(:C) == Set([:Y])
    @test children(:D) == Set([:Y])
    @test children(:Y) == Set{Symbol}()   # outgoing from Y removed
end

# ── Example 1: FindFDSet ──────────────────────────────────────────────────────

@testitem "FindFDSet: Jeong (2022) Example 1 - include={}, restrict={A,B,C,D}" setup=[
    JeongGraphs,
] tags = [:unit] begin
    cg = _jeong2022_fig1b()
    z = frontdoor_set(cg, :X, :Y; restrict = [:A, :B, :C, :D])
    @test z !== nothing
    @test Set(z) == Set([:A, :B, :C])
end

@testitem "FindFDSet: Jeong (2022) Example 1 - I={C}, R={A,C}" setup=[JeongGraphs] tags =
    [:unit] begin
    cg = _jeong2022_fig1b()
    z = frontdoor_set(cg, :X, :Y; include = [:C], restrict = [:A, :C])
    @test z !== nothing
    @test Set(z) == Set([:A, :C])
end

@testitem "FindFDSet: Jeong (2022) Example 1 - I={D}, R={A,B,C,D} infeasible" setup=[
    JeongGraphs,
] tags = [:unit] begin
    cg = _jeong2022_fig1b()
    @test frontdoor_set(cg, :X, :Y; include = [:D], restrict = [:A, :B, :C, :D]) === nothing
end

# ── ListFDSets ────────────────────────────────────────────────────────────────

@testitem "ListFDSets: classic single mediator" tags = [:unit] begin
    cg = cgraph(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:X, :Z),
        directed(:Z, :Y);
        class = DAG,
    )
    @test all_frontdoor_sets(cg, :X, :Y; restrict = [:Z]) == [[:Z]]
end

@testitem "ListFDSets: Jeong (2022) Fig. 1b - all 4 valid sets" setup=[JeongGraphs] tags =
    [:unit] begin
    cg = _jeong2022_fig1b()
    zs = all_frontdoor_sets(cg, :X, :Y; restrict = [:A, :B, :C, :D])
    @test Set(zs) == Set([[:A], [:A, :B], [:A, :C], [:A, :B, :C]])
end

@testitem "ListFDSets: Jeong (2022) Fig. 1b - required C restricts listing" setup=[
    JeongGraphs,
] tags = [:unit] begin
    cg = _jeong2022_fig1b()
    zs = all_frontdoor_sets(cg, :X, :Y; include = [:C], restrict = [:A, :B, :C, :D])
    @test Set(zs) == Set([[:A, :C], [:A, :B, :C]])
end

@testitem "ListFDSets: Jeong (2022) Fig. 1b - required D returns empty" setup=[JeongGraphs] tags =
    [:unit] begin
    cg = _jeong2022_fig1b()
    @test isempty(
        all_frontdoor_sets(cg, :X, :Y; include = [:D], restrict = [:A, :B, :C, :D]),
    )
end

# ── Fig. 6 graphs ─────────────────────────────────────────────────────────────
# Each parallel path X --> Ai --> Bi --> Y can be intercepted by {Ai}, {Bi}, or
# {Ai,Bi}, giving 3^n valid FD sets for n parallel paths (Example 9 in the paper).

@testitem "ListFDSets: Jeong (2022) Fig. 6a - 9 valid sets (3^2)" setup=[JeongGraphs] tags =
    [:unit] begin
    cg = _jeong2022_fig6a()
    zs = all_frontdoor_sets(cg, :X, :Y; restrict = [:A1, :B1, :A2, :B2])
    @test length(zs) == 9
    # Alphabetical node order: A1 < A2 < B1 < B2
    @test Set(zs) == Set([
        [:A1, :A2],
        [:A1, :B2],
        [:A1, :A2, :B2],
        [:A2, :B1],
        [:B1, :B2],
        [:A2, :B1, :B2],
        [:A1, :A2, :B1],
        [:A1, :B1, :B2],
        [:A1, :A2, :B1, :B2],
    ])
end

@testitem "ListFDSets: Jeong (2022) Fig. 6b - 27 valid sets (3^3)" setup=[JeongGraphs] tags =
    [:unit] begin
    cg = _jeong2022_fig6b()
    zs = all_frontdoor_sets(cg, :X, :Y; restrict = [:A1, :B1, :A2, :B2, :A3, :B3])
    @test length(zs) == 27
end
