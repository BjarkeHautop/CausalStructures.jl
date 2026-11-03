@testitem "identification functions reject x and y sharing a node" tags = [:unit] begin
    dag = DAG("U --> X --> Y")
    admg = ADMG("U --> X --> Y")
    mag = MAG("U --> X --> Y")
    pag = mag_to_pag(mag)
    cpdag = dag_to_cpdag(dag)
    mpdag = MPDAG("U --> X --> Y")
    pdag = PDAG("U --> X --> Y")
    overlaps = ((:X, :X), (:Y, :Y), ([:U, :X], :X), (:X, [:X, :Y]))

    for cg in (dag, admg, mag, pag, cpdag, mpdag, pdag), (x, y) in overlaps
        @test_throws ArgumentError is_valid_adjustment(cg, x, y)
        @test_throws ArgumentError all_adjustment_sets(cg, x, y)
        @test_throws ArgumentError adjustment_set(cg, x, y)
    end

    for type in (:parents, :backdoor, :optimal)
        @test_throws ArgumentError adjustment_set(dag, :X, :X; type)
    end
    @test_throws ArgumentError adjustment_set(cpdag, :X, :X; type = :parents)

    for cg in (dag, admg), (x, y) in overlaps
        @test_throws ArgumentError is_valid_backdoor(cg, x, y)
        @test_throws ArgumentError all_backdoor_sets(cg, x, y)
        @test_throws ArgumentError is_valid_frontdoor(cg, x, y)
        @test_throws ArgumentError frontdoor_set(cg, x, y)
        @test_throws ArgumentError all_frontdoor_sets(cg, x, y)
    end

    for cg in (dag, admg, mag, pag, cpdag)
        @test_throws ArgumentError backdoor_set(cg, :X, :X)
    end
    for cg in (dag, admg)
        @test_throws ArgumentError backdoor_set(cg, :X, :X; restrict = [:U])
        @test_throws ArgumentError is_valid_iv(cg, :X, [:X, :Y], :U)
        @test_throws ArgumentError iv_set(cg, :X, :X)
        @test_throws ArgumentError all_iv_sets(cg, :X, [:X, :Y])
    end

    @test_throws ArgumentError possible_optimal_adjustment_sets(cpdag, :X, :X)
    @test_throws ArgumentError pagcauses(pag, :X, :X)

    # Separation of a node from itself stays a well-posed query with answer "no".
    @test minimal_separator(dag, :X, :X) === nothing
    @test !d_separated(dag, :X, :X)
end
