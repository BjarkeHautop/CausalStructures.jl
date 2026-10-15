# Tests for mag_to_pag: the MAG -> PAG (Markov equivalence class) transform.
# Edges below are checked with helper-mag-to-pag.jl's `pag_edge`, which returns
# the edge in standard notation: "-->", "o->", "<->", "o-o", "o--", "---".

# ── Output type & skeleton ──────────────────────────────────────────────────────

@testitem "mag_to_pag: returns an UNKNOWN graph" tags = [:unit, :mag_to_pag] begin
    mag = MAG(directed(:A, :B), directed(:C, :B))
    pag = mag_to_pag(mag)
    @test pag isa PAG
    @test Set(nodes(pag)) == Set([:A, :B, :C])
end

@testitem "mag_to_pag: preserves the skeleton" setup=[PagEdge] tags = [:unit, :mag_to_pag] begin
    mag = MAG(directed(:A, :C), directed(:B, :C), directed(:C, :D), bidirected(:D, :E))
    pag = mag_to_pag(mag)
    @test adjacency_pairs(pag) == adjacency_pairs(mag)
end

@testitem "mag_to_pag: edge count matches the MAG" tags = [:unit, :mag_to_pag] begin
    mag = MAG(directed(:A, :B), directed(:C, :B))
    pag = mag_to_pag(mag)
    @test length(pag.edges) == length(mag.edges)
end

# ── Unshielded colliders ────────────────────────────────────────────────────────

@testitem "mag_to_pag: unshielded collider gets invariant arrowheads (docstring)" setup=[
    PagEdge,
] tags = [:unit, :mag_to_pag] begin
    # A --> B <-- C, A and C non-adjacent => A o-> B <-o C in the PAG.
    mag = MAG(directed(:A, :B), directed(:C, :B))
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o->"
    @test pag_edge(pag, :C, :B) == "o->"
end

@testitem "mag_to_pag: collider from a latent-free DAG" setup=[PagEdge] tags =
    [:unit, :mag_to_pag] begin
    # A --> B --> D <-- C, with A,C and A,D and B,C non-adjacent.
    mag = MAG(directed(:A, :B), directed(:B, :D), directed(:C, :D))
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o-o"   # reversible: no collider at B
    @test pag_edge(pag, :B, :D) == "o->"   # collider at D
    @test pag_edge(pag, :C, :D) == "o->"
end

# ── No collider: everything stays a circle ──────────────────────────────────────

@testitem "mag_to_pag: directed chain has no invariant marks" setup=[PagEdge] tags =
    [:unit, :mag_to_pag] begin
    # A --> B --> C: no unshielded collider, so the PAG is all circles.
    mag = MAG(directed(:A, :B), directed(:B, :C))
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o-o"
    @test pag_edge(pag, :B, :C) == "o-o"
end

@testitem "mag_to_pag: fork is equivalent to the chain" setup=[PagEdge] tags =
    [:unit, :mag_to_pag] begin
    # B --> A, B --> C is Markov equivalent to the chain: same all-circle PAG.
    mag = MAG(directed(:B, :A), directed(:B, :C))
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o-o"
    @test pag_edge(pag, :B, :C) == "o-o"
end

@testitem "mag_to_pag: single directed edge has no invariant marks" setup=[PagEdge] tags =
    [:unit, :mag_to_pag] begin
    mag = MAG(directed(:A, :B))
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o-o"
end

@testitem "mag_to_pag: single bidirected edge has no invariant marks" setup=[PagEdge] tags =
    [:unit, :mag_to_pag] begin
    # With only two adjacent vertices, no endpoint is invariant.
    mag = MAG(bidirected(:A, :B))
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o-o"
end

# ── Orientation rule propagation ────────────────────────────────────────────────

@testitem "mag_to_pag: R1 propagates a tail off a collider" setup=[PagEdge] tags =
    [:unit, :mag_to_pag] begin
    # A --> C <-- B (collider at C), C --> D with A,D and B,D non-adjacent.
    # The collider gives A o-> C <-o B; R1 then orients C --> D.
    mag = MAG(directed(:A, :C), directed(:B, :C), directed(:C, :D))
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :C) == "o->"
    @test pag_edge(pag, :B, :C) == "o->"
    @test pag_edge(pag, :C, :D) == "-->"   # C --> D, tail invariant via R1
end

# ── Determinism ─────────────────────────────────────────────────────────────────

@testitem "mag_to_pag: is deterministic" tags = [:unit, :mag_to_pag] begin
    mag = MAG(directed(:A, :C), directed(:B, :C), directed(:C, :D))
    @test Set(mag_to_pag(mag).edges) == Set(mag_to_pag(mag).edges)
end

# ── Discriminating path (R4) ────────────────────────────────────────────────────

@testitem "mag_to_pag: discriminating path orients the collider (R4)" setup=[PagEdge] tags =
    [:unit, :mag_to_pag] begin
    # Discriminating path <D, A, B, C> for B: D <-> A <-> B with A --> C and D
    # not adjacent to C. Here B <-> C, so B is a collider on the path and R4
    # orients B <-> C with both arrowheads invariant.
    mag = MAG(bidirected(:D, :A), bidirected(:A, :B), directed(:A, :C), bidirected(:B, :C))
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :B, :C) == "<->"   # R4: collider => B <-> C
    @test pag_edge(pag, :A, :C) == "-->"
end

@testitem "mag_to_pag: discriminating path orients the non-collider (R4)" setup=[PagEdge] tags =
    [:unit, :mag_to_pag] begin
    # Same configuration but with B --> C, so B is a non-collider on the
    # discriminating path and R4 orients B --> C (tail at B invariant).
    mag = MAG(bidirected(:D, :A), bidirected(:A, :B), directed(:A, :C), directed(:B, :C))
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :B, :C) == "-->"   # R4: non-collider => B --> C
    @test pag_edge(pag, :A, :C) == "-->"
end

@testitem "mag_to_pag: R4 distinguishes non-equivalent MAGs" tags = [:unit, :mag_to_pag] begin
    # The two MAGs above share their skeleton and unshielded collider but differ
    # only in the discriminating-path triple at B.
    m_collider =
        MAG(bidirected(:D, :A), bidirected(:A, :B), directed(:A, :C), bidirected(:B, :C))
    m_noncollider =
        MAG(bidirected(:D, :A), bidirected(:A, :B), directed(:A, :C), directed(:B, :C))
    @test m_separated(m_collider, :D, :C, [:A]) != m_separated(m_noncollider, :D, :C, [:A])
    @test Set(mag_to_pag(m_collider).edges) != Set(mag_to_pag(m_noncollider).edges)
end

@testitem "mag_to_pag: discriminating path with an intermediate parent vertex orients the collider (R4)" setup=[
    PagEdge,
] tags = [:unit, :mag_to_pag] begin
    # Discriminating path <D, X, A, B, C> for B: D <-> X <-> A <-> B, with X
    # and A both parents of C and D not adjacent to C.
    mag = MAG(
        bidirected(:D, :X),
        bidirected(:X, :A),
        bidirected(:A, :B),
        directed(:X, :C),
        directed(:A, :C),
        bidirected(:B, :C),
    )
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :B, :C) == "<->"   # R4: collider => B <-> C
end

@testitem "mag_to_pag: discriminating path with an intermediate parent vertex orients the non-collider (R4)" setup=[
    PagEdge,
] tags = [:unit, :mag_to_pag] begin
    # Same configuration as above but with B --> C, so B is a non-collider on
    # the discriminating path and R4 orients B --> C (tail at B invariant).
    mag = MAG(
        bidirected(:D, :X),
        bidirected(:X, :A),
        bidirected(:A, :B),
        directed(:X, :C),
        directed(:A, :C),
        directed(:B, :C),
    )
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :B, :C) == "-->"   # R4: non-collider => B --> C
end

@testitem "_pag_rule_r10!: fires with two disjoint uncovered p.d. paths to gamma's parents" tags =
    [:unit, :mag_to_pag] begin
    Endpoint = CausalStructures.Endpoint
    Circle, Arrow, Tail =
        CausalStructures.Circle, CausalStructures.Arrow, CausalStructures.Tail

    # alpha o-> gamma, beta --> gamma <-- delta, with uncovered p.d. paths
    # alpha-mu-beta and alpha-omega-delta; mu and omega are distinct and
    # non-adjacent.
    n = 6
    alpha, gamma, beta, delta, mu, omega = 1, 2, 3, 4, 5, 6
    adj = falses(n, n)
    for (i, j) in [
        (alpha, gamma),
        (beta, gamma),
        (delta, gamma),
        (alpha, mu),
        (mu, beta),
        (alpha, omega),
        (omega, delta),
    ]
        adj[i, j] = adj[j, i] = true
    end
    mark = fill(Circle, n, n)
    mark[alpha, gamma], mark[gamma, alpha] = Arrow, Circle
    mark[beta, gamma], mark[gamma, beta] = Arrow, Tail
    mark[delta, gamma], mark[gamma, delta] = Arrow, Tail

    @test CausalStructures._pag_rule_r10!(adj, mark, n)
    @test mark[gamma, alpha] == Tail   # R10: alpha -> gamma
end

@testitem "_pag_rule_r10!: does not fire when the two paths' first vertices are adjacent" tags =
    [:unit, :mag_to_pag] begin
    Circle, Arrow, Tail =
        CausalStructures.Circle, CausalStructures.Arrow, CausalStructures.Tail

    # Same as above but mu and omega are adjacent, violating R10's
    # non-adjacency requirement on the paths' first vertices.
    n = 6
    alpha, gamma, beta, delta, mu, omega = 1, 2, 3, 4, 5, 6
    adj = falses(n, n)
    for (i, j) in [
        (alpha, gamma),
        (beta, gamma),
        (delta, gamma),
        (alpha, mu),
        (mu, beta),
        (alpha, omega),
        (omega, delta),
        (mu, omega),
    ]
        adj[i, j] = adj[j, i] = true
    end
    mark = fill(Circle, n, n)
    mark[alpha, gamma], mark[gamma, alpha] = Arrow, Circle
    mark[beta, gamma], mark[gamma, beta] = Arrow, Tail
    mark[delta, gamma], mark[gamma, delta] = Arrow, Tail

    @test !CausalStructures._pag_rule_r10!(adj, mark, n)
    @test mark[gamma, alpha] == Circle
end

# ── R8 premise ──────────────────────────────────────────────────────────────────

@testitem "_pag_rule_r8!: needs a tail at alpha on the alpha-beta edge" tags =
    [:unit, :mag_to_pag] begin
    Circle, Arrow, Tail =
        CausalStructures.Circle, CausalStructures.Arrow, CausalStructures.Tail

    # alpha o-> gamma, beta --> gamma, and alpha-beta with the given marks.
    function r8_fires(mark_at_alpha, mark_at_beta)
        n = 3
        alpha, beta, gamma = 1, 2, 3
        adj = falses(n, n)
        for (i, j) in [(alpha, beta), (beta, gamma), (alpha, gamma)]
            adj[i, j] = adj[j, i] = true
        end
        mark = fill(Circle, n, n)
        mark[alpha, gamma], mark[gamma, alpha] = Arrow, Circle
        mark[beta, gamma], mark[gamma, beta] = Arrow, Tail
        mark[beta, alpha], mark[alpha, beta] = mark_at_alpha, mark_at_beta
        fired = CausalStructures._pag_rule_r8!(adj, mark, n)
        return fired && mark[gamma, alpha] == Tail
    end

    @test r8_fires(Tail, Arrow)    # alpha --> beta
    @test r8_fires(Tail, Circle)   # alpha --o beta
    @test !r8_fires(Circle, Arrow) # alpha o-> beta: alpha <-> beta is possible
    @test !r8_fires(Circle, Circle)
    @test !r8_fires(Arrow, Arrow)
end

@testitem "mag_to_pag: R8 must not orient alpha o-> beta as a witness (regression)" setup=[
    PagEdge,
] tags = [:unit, :mag_to_pag] begin
    # The only member of its Markov equivalence class, so every mark of the PAG
    # is the corresponding mark of the MAG.
    mag = MAG(
        bidirected(:A, :B),
        bidirected(:A, :E),
        directed(:C, :B),
        directed(:E, :B),
        bidirected(:C, :D),
        bidirected(:C, :E),
        directed(:E, :D),
    )
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "<->"
    @test pag_edge(pag, :A, :E) == "<->"
    @test pag_edge(pag, :C, :B) == "-->"
    @test pag_edge(pag, :E, :B) == "-->"
    @test pag_edge(pag, :C, :D) == "<->"
    @test pag_edge(pag, :C, :E) == "<->"
    @test pag_edge(pag, :E, :D) == "-->"

    # ... so the PAG validates and round-trips.
    @test PAG(nodes(pag), pag.edges) isa PAG
end

# ── Potentially directed paths (R9, R10) ────────────────────────────────────────

@testitem "_pag_rule_r9!: p.d. path rejects an arrowhead at V_i or a tail at V_i+1" tags =
    [:unit, :mag_to_pag] begin
    Circle, Arrow, Tail =
        CausalStructures.Circle, CausalStructures.Arrow, CausalStructures.Tail

    # alpha o-> gamma and the uncovered path alpha - beta - theta - gamma, with
    # alpha,theta and beta,gamma non-adjacent. `ab` and `bt` give the marks
    # (at the first node, at the second node) of alpha-beta and beta-theta;
    # theta o-o gamma. Zhang (2008), Def. 10: an edge V_i - V_i+1 on a p.d.
    # path is neither into V_i nor out of V_i+1.
    function r9_fires(ab, bt)
        n = 4
        alpha, beta, theta, gamma = 1, 2, 3, 4
        adj = falses(n, n)
        for (i, j) in [(alpha, gamma), (alpha, beta), (beta, theta), (theta, gamma)]
            adj[i, j] = adj[j, i] = true
        end
        mark = fill(Circle, n, n)
        mark[alpha, gamma], mark[gamma, alpha] = Arrow, Circle
        mark[beta, alpha], mark[alpha, beta] = ab
        mark[theta, beta], mark[beta, theta] = bt
        fired = CausalStructures._pag_rule_r9!(adj, mark, n)
        return fired && mark[gamma, alpha] == Tail
    end

    @test r9_fires((Circle, Circle), (Circle, Circle))   # o-o, o-o
    @test r9_fires((Tail, Arrow), (Tail, Arrow))         # -->, -->
    @test r9_fires((Circle, Circle), (Circle, Arrow))    # o-o, o->
    @test r9_fires((Tail, Circle), (Circle, Circle))     # --o, o-o
    @test !r9_fires((Circle, Circle), (Tail, Tail))      # beta --- theta
    @test !r9_fires((Circle, Circle), (Circle, Tail))    # beta o-- theta
    @test !r9_fires((Circle, Circle), (Arrow, Circle))   # beta <-o theta
    @test !r9_fires((Circle, Tail), (Circle, Circle))    # alpha o-- beta (first edge)
    @test !r9_fires((Tail, Tail), (Circle, Circle))      # alpha --- beta (first edge)
end

@testitem "_pag_rule_r10!: a p.d. path may start with alpha o-> gamma" tags =
    [:unit, :mag_to_pag] begin
    Circle, Arrow, Tail =
        CausalStructures.Circle, CausalStructures.Arrow, CausalStructures.Tail

    # alpha o-> gamma, beta --> gamma <-- theta. The only uncovered p.d. path
    # from alpha to beta is alpha o-> gamma o-o x o-o y o-o beta, so mu = gamma;
    # the path to theta is alpha o-o omega o-o theta. mu and omega are distinct
    # and non-adjacent. Zhang's R10 places no restriction on gamma appearing on
    # either path, so it fires.
    n = 7
    alpha, gamma, beta, theta, x, y, omega = 1:7
    adj = falses(n, n)
    for (i, j) in [
        (alpha, gamma),
        (beta, gamma),
        (theta, gamma),
        (gamma, x),
        (x, y),
        (y, beta),
        (alpha, omega),
        (omega, theta),
    ]
        adj[i, j] = adj[j, i] = true
    end
    mark = fill(Circle, n, n)
    mark[alpha, gamma], mark[gamma, alpha] = Arrow, Circle
    mark[beta, gamma], mark[gamma, beta] = Arrow, Tail
    mark[theta, gamma], mark[gamma, theta] = Arrow, Tail

    @test CausalStructures._pag_rule_r10!(adj, mark, n)
    @test mark[gamma, alpha] == Tail   # R10: alpha --> gamma

    # Breaking the path through gamma (x o-- y has a tail at y) leaves no witness.
    mark2 = fill(Circle, n, n)
    mark2[alpha, gamma], mark2[gamma, alpha] = Arrow, Circle
    mark2[beta, gamma], mark2[gamma, beta] = Arrow, Tail
    mark2[theta, gamma], mark2[gamma, theta] = Arrow, Tail
    mark2[x, y] = Tail
    @test !CausalStructures._pag_rule_r10!(adj, mark2, n)
    @test mark2[gamma, alpha] == Circle
end

# ── R4 consequent ───────────────────────────────────────────────────────────────

@testitem "_pag_rule_r4!: a collider is oriented A <-> beta <-> gamma" tags =
    [:unit, :mag_to_pag] begin
    Circle, Arrow, Tail =
        CausalStructures.Circle, CausalStructures.Arrow, CausalStructures.Tail

    # Discriminating path <D, A, beta, gamma> for beta: D o-> A <-o beta, with
    # A --> gamma, beta o-o gamma and D not adjacent to gamma. Zhang (2008)
    # orients the whole triple <A, beta, gamma>, so the circle at beta on
    # A - beta becomes an arrowhead too when beta is a collider in the MAG.
    function run_r4(collider)
        n = 4
        d, a, beta, gamma = 1, 2, 3, 4
        adj = falses(n, n)
        for (i, j) in [(d, a), (a, beta), (a, gamma), (beta, gamma)]
            adj[i, j] = adj[j, i] = true
        end
        mark = fill(Circle, n, n)
        mark[d, a] = Arrow                                # D o-> A
        mark[beta, a] = Arrow                             # A <-o beta
        mark[a, gamma], mark[gamma, a] = Arrow, Tail      # A --> gamma
        mmark = fill(Tail, n, n)
        mmark[gamma, beta] = collider ? Arrow : Tail      # mark at beta on beta-gamma
        @test CausalStructures._pag_rule_r4!(adj, mark, n, mmark)
        return mark
    end

    m = run_r4(true)
    @test m[2, 3] == Arrow                            # A <-> beta
    @test m[3, 4] == Arrow && m[4, 3] == Arrow        # beta <-> gamma

    m = run_r4(false)
    @test m[2, 3] == Circle                           # A <-o beta untouched
    @test m[3, 4] == Arrow && m[4, 3] == Tail         # beta --> gamma
end
