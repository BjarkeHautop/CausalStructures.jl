@testitem "possible_optimal_adjustment_sets matches the worked example (Maathuis, Kalisch & Bühlmann 2009, Fig. 2)" tags =
    [:unit, :possible_adjustment_sets] begin
    cpdag = CPDAG("X1 --- X2 + X3 + X4, X3 + X4 --> Y")
    pas = possible_parent_sets(cpdag, :X1)
    opts = possible_optimal_adjustment_sets(cpdag, :X1, :Y)

    @test length(opts) == length(pas)

    # index i of opts is the O-set for the orientation giving pas[i]
    expected = Dict(
        Symbol[] => Symbol[],
        [:X2] => Symbol[],  # X2 is a dead end: irrelevant to Y, dropped by the O-set
        [:X3] => [:X3],
        [:X4] => [:X4],
    )
    for (pa, opt) in zip(pas, opts)
        @test opt == expected[pa]
    end
end

@testitem "possible_optimal_adjustment_sets: O-set can be a strict subset of the parent set" tags =
    [:unit, :possible_adjustment_sets] begin
    cpdag = CPDAG("X1 --- X2 + X3 + X4, X3 + X4 --> Y")
    pas = possible_parent_sets(cpdag, :X1)
    opts = possible_optimal_adjustment_sets(cpdag, :X1, :Y)
    idx = findfirst(==([:X2]), pas)
    @test idx !== nothing
    @test opts[idx] == Symbol[]
    @test opts[idx] != pas[idx]
end

@testitem "possible_optimal_adjustment_sets: nothing when y is a parent of x for that orientation" tags =
    [:unit, :possible_adjustment_sets] begin
    cpdag = CPDAG("X --- Y")
    pas = possible_parent_sets(cpdag, :X)
    opts = possible_optimal_adjustment_sets(cpdag, :X, :Y)
    @test length(opts) == length(pas)

    idx_parent = findfirst(==([:Y]), pas)
    @test opts[idx_parent] === nothing

    idx_empty = findfirst(==(Symbol[]), pas)
    @test opts[idx_empty] == Symbol[]
end

@testitem "possible_optimal_adjustment_sets: single valid orientation when x has no undirected neighbors" tags =
    [:unit, :possible_adjustment_sets] begin
    # A --> X <-- B protects both edges into X, so the CPDAG leaves X fully resolved
    dag = DAG(directed(:A, :X), directed(:B, :X), directed(:X, :Y))
    cpdag = dag_to_cpdag(dag)
    @test possible_parent_sets(cpdag, :X) == [[:A, :B]]
    # A and B only affect Y through X, so neither confounds X -> Y: O-set is empty
    @test possible_optimal_adjustment_sets(cpdag, :X, :Y) == [Symbol[]]
end

@testitem "possible_optimal_adjustment_sets: agrees with adjustment_set(:optimal) on the oriented MPDAG" tags =
    [:unit, :possible_adjustment_sets] begin
    cpdag = CPDAG("X1 --- X2 + X3 + X4, X3 + X4 --> Y")
    pas = possible_parent_sets(cpdag, :X1)
    opts = possible_optimal_adjustment_sets(cpdag, :X1, :Y)
    sibs = [:X2, :X3, :X4]

    for (pa, opt) in zip(pas, opts)
        away = setdiff(sibs, pa)
        items = Any[
            [required_directed(s, :X1) for s in pa]
            [required_directed(:X1, s) for s in away]
        ]
        mpdag = apply_background_knowledge(cpdag, BackgroundKnowledge(items...))
        @test opt == adjustment_set(mpdag, :X1, :Y; type = :optimal)
    end
end

@testitem "possible_optimal_adjustment_sets works on MPDAG" tags =
    [:unit, :possible_adjustment_sets] begin
    cpdag = CPDAG("X1 --- X2 + X3 + X4, X3 + X4 --> Y")
    # background knowledge resolves the rest of X1's neighborhood via Meek closure
    mpdag = apply_background_knowledge(cpdag, "X3 --> X1")
    @test possible_parent_sets(mpdag, :X1) == [[:X3]]
    @test possible_optimal_adjustment_sets(mpdag, :X1, :Y) == [[:X3]]
end
