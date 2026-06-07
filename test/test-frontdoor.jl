using Test
using CausalGraphInterface

# Classic front-door graph: U -> X -> M -> Y, U -> Y
# M mediates the entire causal effect of X on Y; U is an unmeasured confounder.
# Z = {M} is the canonical front-door set.

@testitem "is_valid_frontdoor: M satisfies criterion on classic graph" tags = [:unit] begin
    cg = caugi(
        directed(:U, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:U, :Y);
        class = DAG,
    )
    @test is_valid_frontdoor(cg, :X, :Y, [:M])
end

@testitem "is_valid_frontdoor: empty Z fails when directed path exists" tags = [:unit] begin
    cg = caugi(
        directed(:U, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:U, :Y);
        class = DAG,
    )
    @test !is_valid_frontdoor(cg, :X, :Y)
end

@testitem "is_valid_frontdoor: U fails condition (i) — does not intercept X -> M -> Y" tags =
    [:unit] begin
    cg = caugi(
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
    cg = caugi(
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
    # X -> M, M -> Y, B -> M, B -> Y
    # Backdoor path from M to Y: M <- B -> Y is not blocked by X.
    cg = caugi(
        directed(:X, :M),
        directed(:M, :Y),
        directed(:B, :M),
        directed(:B, :Y);
        class = DAG,
    )
    @test !is_valid_frontdoor(cg, :X, :Y, [:M])
end

@testitem "is_valid_frontdoor: X -> Y direct edge violates condition (i)" tags = [:unit] begin
    # If there is a direct edge X -> Y alongside X -> M -> Y, then M alone does
    # not intercept the direct path.
    cg = caugi(
        directed(:U, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:X, :Y),
        directed(:U, :Y);
        class = DAG,
    )
    @test !is_valid_frontdoor(cg, :X, :Y, [:M])
    # Both M and the direct path must be intercepted — no single node suffices.
    @test !is_valid_frontdoor(cg, :X, :Y, [:U])
end

@testitem "is_valid_frontdoor: chain mediators — each singleton is valid" tags = [:unit] begin
    # U -> X -> M1 -> M2 -> Y, U -> Y
    # Both {M1} and {M2} individually intercept all directed paths.
    cg = caugi(
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

@testitem "is_valid_frontdoor: no causal path — empty Z valid" tags = [:unit] begin
    # X -> A, B -> Y: no directed path from X to Y at all.
    # Empty Z vacuously intercepts all (zero) directed paths.
    cg = caugi(directed(:X, :A), directed(:B, :Y); class = DAG)
    @test is_valid_frontdoor(cg, :X, :Y)
end
