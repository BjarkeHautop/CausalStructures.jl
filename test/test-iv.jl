# Classic IV setup: Z --> X --> Y, U --> X, U --> Y
@testsnippet ClassicIVGraph begin
    function _classic_iv()
        cgraph(
            directed(:Z, :X),
            directed(:X, :Y),
            directed(:U, :X),
            directed(:U, :Y);
            class = DAG,
        )
    end
end

@testitem "is_valid_iv: Z is valid instrument in classic IV graph" setup = [ClassicIVGraph] tags =
    [:unit] begin
    cg = _classic_iv()
    @test is_valid_iv(cg, :X, :Y, [:Z])
end

@testitem "is_valid_iv: confounder U fails exclusion restriction" setup = [ClassicIVGraph] tags =
    [:unit] begin
    cg = _classic_iv()
    @test !is_valid_iv(cg, :X, :Y, [:U])
end

@testitem "is_valid_iv: empty set fails relevance condition" setup = [ClassicIVGraph] tags =
    [:unit] begin
    cg = _classic_iv()
    @test !is_valid_iv(cg, :X, :Y, Symbol[])
end

@testitem "is_valid_iv: X and Y are rejected from z" setup = [ClassicIVGraph] tags = [:unit] begin
    cg = _classic_iv()
    @test !is_valid_iv(cg, :X, :Y, [:X])
    @test !is_valid_iv(cg, :X, :Y, [:Y])
end

@testitem "is_valid_iv: isolated node fails relevance" tags = [:unit] begin
    cg = cgraph(
        directed(:Z, :X),
        directed(:X, :Y),
        directed(:U, :X),
        directed(:U, :Y),
        node(:W);
        class = DAG,
    )
    @test !is_valid_iv(cg, :X, :Y, [:W])
end

@testitem "is_valid_iv: direct effect Z --> Y violates exclusion restriction" tags = [:unit] begin
    cg = cgraph(directed(:Z, :X), directed(:Z, :Y), directed(:X, :Y); class = DAG)
    @test !is_valid_iv(cg, :X, :Y, [:Z])
end

@testitem "is_valid_iv: set with multiple valid instruments" tags = [:unit] begin
    cg = cgraph(
        directed(:Z1, :X),
        directed(:Z2, :X),
        directed(:X, :Y),
        directed(:U, :X),
        directed(:U, :Y);
        class = DAG,
    )
    @test is_valid_iv(cg, :X, :Y, [:Z1])
    @test is_valid_iv(cg, :X, :Y, [:Z2])
    @test is_valid_iv(cg, :X, :Y, [:Z1, :Z2])
end

@testitem "is_valid_iv: instrument with path through confounder is invalid" tags = [:unit] begin
    # Z --> U --> Y and U --> X: Z is d-connected to Y via Z --> U --> Y even given X
    cg = cgraph(
        directed(:Z, :U),
        directed(:U, :X),
        directed(:U, :Y),
        directed(:X, :Y);
        class = DAG,
    )
    @test !is_valid_iv(cg, :X, :Y, [:Z])
end

@testitem "all_iv_sets: returns the single valid instrument" setup = [ClassicIVGraph] tags =
    [:unit] begin
    cg = _classic_iv()
    sets = all_iv_sets(cg, :X, :Y)
    @test length(sets) == 1
    @test sets[1] == [:Z]
end

@testitem "all_iv_sets: returns multiple minimal IV sets" tags = [:unit] begin
    cg = cgraph(
        directed(:Z1, :X),
        directed(:Z2, :X),
        directed(:X, :Y),
        directed(:U, :X),
        directed(:U, :Y);
        class = DAG,
    )
    sets = all_iv_sets(cg, :X, :Y; minimal = true)
    @test length(sets) == 2
    @test any(s -> s == [:Z1], sets)
    @test any(s -> s == [:Z2], sets)
end

@testitem "all_iv_sets: non-minimal includes supersets" tags = [:unit] begin
    cg = cgraph(
        directed(:Z1, :X),
        directed(:Z2, :X),
        directed(:X, :Y),
        directed(:U, :X),
        directed(:U, :Y);
        class = DAG,
    )
    sets = all_iv_sets(cg, :X, :Y; minimal = false, max_size = 2)
    @test any(s -> s == [:Z1], sets)
    @test any(s -> s == [:Z2], sets)
    @test any(s -> sort(s) == [:Z1, :Z2], sets)
end

@testitem "all_iv_sets: no valid IV when all paths to X are confounded" tags = [:unit] begin
    # Only U --> X and U --> Y: no variable d-separated from Y given X in G_{do_x}
    cg = cgraph(directed(:U, :X), directed(:U, :Y), directed(:X, :Y); class = DAG)
    sets = all_iv_sets(cg, :X, :Y)
    @test isempty(sets)
end

# ── ADMG ──────────────────────────────────────────────────────────────────────

@testitem "is_valid_iv (ADMG): Z is valid instrument with bidirected confounder" tags =
    [:unit] begin
    # X <-> Y encodes the hidden common cause; Z --> X is the instrument
    admg = cgraph(bidirected(:X, :Y), directed(:Z, :X), directed(:X, :Y); class = ADMG)
    @test is_valid_iv(admg, :X, :Y, [:Z])
end

@testitem "is_valid_iv (ADMG): isolated node fails relevance" tags = [:unit] begin
    admg = cgraph(bidirected(:X, :Y), directed(:Z, :X), directed(:X, :Y); class = ADMG)
    @test !is_valid_iv(admg, :X, :Y, [:X])
    @test !is_valid_iv(admg, :X, :Y, [:Y])
    @test !is_valid_iv(admg, :X, :Y, Symbol[])
end

@testitem "is_valid_iv (ADMG): bidirected Z <-> Y violates exclusion restriction" tags =
    [:unit] begin
    # Z <-> Y creates a hidden path from Z to Y not through X
    admg = cgraph(
        bidirected(:X, :Y),
        bidirected(:Z, :Y),
        directed(:Z, :X),
        directed(:X, :Y);
        class = ADMG,
    )
    @test !is_valid_iv(admg, :X, :Y, [:Z])
end

@testitem "all_iv_sets (ADMG): finds the valid instrument" tags = [:unit] begin
    admg = cgraph(bidirected(:X, :Y), directed(:Z, :X), directed(:X, :Y); class = ADMG)
    sets = all_iv_sets(admg, :X, :Y)
    @test length(sets) == 1
    @test sets[1] == [:Z]
end

@testitem "all_iv_sets (ADMG): consistent with DAG latent projection" tags = [:unit] begin
    dag = cgraph(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:Z, :X),
        directed(:X, :Y);
        class = DAG,
    )
    admg = latent_project(dag, [:U])
    @test all_iv_sets(dag, :X, :Y) == all_iv_sets(admg, :X, :Y)
end
