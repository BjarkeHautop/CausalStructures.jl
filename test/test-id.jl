@testitem "id: no confounding gives the conditional" tags = [:unit] begin
    cg = cgraph("X --> Y"; class = DAG)
    @test id(cg, :X, :Y) == prob(:Y; given = [:X])
end

@testitem "id: back-door graph gives the g-formula" tags = [:unit] begin
    cg = cgraph("Z --> X + Y, X --> Y"; class = DAG)
    @test string(id(cg, :X, :Y)) == "Σ_{Z} P(Y | X, Z) P(Z)"
end

@testitem "id: front-door graph" tags = [:unit] begin
    cg = cgraph("X --> M, M --> Y, X <-> Y"; class = ADMG)

    # The inner sum ranges over a value of X distinct from the intervened one,
    # so it must be printed under a fresh name.
    @test string(id(cg, :X, :Y)) == "Σ_{M} P(M | X) (Σ_{X'} P(X') P(Y | M, X'))"
end

@testitem "id: bow arc is not identifiable" tags = [:unit] begin
    cg = cgraph("X --> Y, X <-> Y"; class = ADMG)
    @test id(cg, :X, :Y) === nothing
end

@testitem "id: instrument does not identify nonparametrically" tags = [:unit] begin
    cg = cgraph("Z --> X, X --> Y, X <-> Y"; class = ADMG)
    @test id(cg, :X, :Y) === nothing
end

@testitem "id: latent projection of a confounded DAG reproduces the bow arc" tags = [:unit] begin
    dag = cgraph("U --> X + Y, X --> Y"; class = DAG)
    admg = latent_project(dag, [:U])

    @test id(admg, :X, :Y) === nothing
end

@testitem "id: a DAG argument is treated as an ADMG" tags = [:unit] begin
    dag = cgraph("Z --> X + Y, X --> Y"; class = DAG)
    admg = reclass(dag, ADMG)

    @test id(dag, :X, :Y) == id(admg, :X, :Y)
end

@testitem "id: joint outcomes and multiple interventions" tags = [:unit] begin
    cg = cgraph("Z --> X + Y, X --> Y"; class = DAG)
    @test string(id(cg, [:X], [:Y, :Z])) == "P(Y | X, Z) P(Z)"

    fork = cgraph("X --> Y, Z --> Y"; class = DAG)
    @test id(fork, [:X, :Z], :Y) == prob(:Y; given = [:X, :Z])
end

@testitem "id: effect on a non-descendant is the marginal" tags = [:unit] begin
    cg = cgraph("X --> Y"; class = DAG)
    # Y has no effect on X, so P(X | do(Y)) = P(X).
    @test id(cg, :Y, :X) == prob(:X)
end

@testitem "id: identifiable effect in a graph with two districts" tags = [:unit] begin
    cg = cgraph("A --> B, B --> C, C --> D, A <-> C, B <-> D"; class = ADMG)
    result = id(cg, :B, :D)

    @test result !== nothing
    # Line 3 adds A to the intervention set, so A survives as a free variable.
    @test string(result) ==
          "Σ_{C} (Σ_{A'} P(A') P(C | A', B)) (Σ_{B'} P(B' | A) P(D | A, B', C))"
end

@testitem "id: reproduces the worked example of Shpitser & Pearl (2008)" tags = [:unit] begin
    # Figure 3(a) of the paper, whose structure is pinned down by the four
    # intermediate results quoted in the walkthrough on p. 1953.
    cg = cgraph(
        "W1 --> X, X --> Y1, W2 --> Y2, W1 <-> Y1, W1 <-> W2, W2 <-> Y2";
        class = ADMG,
    )

    # The paper's intermediate steps: C(G \ X) is a single district, and
    # removing W1 as well splits it into {Y1} and {W2, Y2}.
    @test length(districts(subgraph(cg, [:W1, :Y1, :W2, :Y2]))) == 1
    @test Set(Set.(districts(subgraph(cg, [:Y1, :W2, :Y2])))) ==
          Set([Set([:Y1]), Set([:W2, :Y2])])

    # The paper's answer: Σ_{w2} P(w2, y2) Σ_{w1} P(y1 | x, w1) P(w1).
    @test string(id(cg, :X, [:Y1, :Y2])) == "Σ_{W2} P(W2, Y2) (Σ_{W1} P(W1) P(Y1 | W1, X))"
end

@testitem "id: Q[S] conditionals become ratios of marginals" tags = [:unit] begin
    # Line 7 hands a factorized Q[S'] down to a recursive call that reaches
    # line 6 again, so the conditionals there cannot be read off the original
    # joint and are emitted as ratios instead. This is the only branch of
    # `_conditional` that produces a Quotient.
    cg = cgraph(
        "A --> B, A --> D, B --> C, B --> D, C --> E, " *
        "A <-> C, A <-> E, B <-> D, D <-> E";
        class = ADMG,
    )
    result = id(cg, :C, :E)

    @test result isa CausalStructures.Quotient
    @test string(result) ==
          "(Σ_{A} P(A) P(C | A, B) P(E | A, B, C)) / " *
          "(Σ_{A, E'} P(A) P(C | A, B) P(E' | A, B, C))"
end

@testitem "id: rejects malformed queries" tags = [:unit] begin
    cg = cgraph("Z --> X + Y, X --> Y"; class = DAG)

    @test_throws ErrorException id(cg, :X, :X)
    @test_throws ErrorException id(cg, :Q, :Y)
    @test_throws ErrorException id(cg, :X, :Q)
    @test_throws ErrorException id(cg, Symbol[], :Y)
    @test_throws ErrorException id(cg, :X, Symbol[])
end

@testitem "idc: rule 2 moves the conditioning variable into the intervention" tags = [:unit] begin
    cg = cgraph("Z --> X + Y, X --> Y"; class = DAG)

    # Z is a non-descendant of X, so conditioning on it is the same as
    # intervening on it and the g-formula collapses to a single conditional.
    @test idc(cg, :X, :Y; given = :Z) == prob(:Y; given = [:X, :Z])
end

@testitem "idc: with an empty conditioning set it reduces to id" tags = [:unit] begin
    cg = cgraph("Z --> X + Y, X --> Y"; class = DAG)
    @test idc(cg, :X, :Y) == id(cg, :X, :Y)
end

@testitem "idc: front-door graph conditioned on the mediator" tags = [:unit] begin
    cg = cgraph("X --> M, M --> Y, X <-> Y"; class = ADMG)
    @test string(idc(cg, :X, :Y; given = :M)) == "Σ_{X'} P(X') P(Y | M, X')"
end

@testitem "idc: inherits unidentifiability from id" tags = [:unit] begin
    cg = cgraph("X --> Y, X <-> Y, W --> Y"; class = ADMG)
    @test idc(cg, :X, :Y; given = :W) === nothing
end

@testitem "idc: rejects overlapping argument sets" tags = [:unit] begin
    cg = cgraph("Z --> X + Y, X --> Y"; class = DAG)

    @test_throws ErrorException idc(cg, :X, :Y; given = :X)
    @test_throws ErrorException idc(cg, :X, :Y; given = :Y)
    @test_throws ErrorException idc(cg, :X, :Y; given = :Q)
end
