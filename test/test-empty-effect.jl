@testitem "identification functions reject an empty x or y" tags = [:unit] begin
    dag = DAG("U --> X --> Y")
    admg = ADMG("U --> X --> Y")
    mag = MAG("U --> X --> Y")
    pag = mag_to_pag(mag)
    cpdag = dag_to_cpdag(dag)
    none = Symbol[]

    for cg in (dag, admg, mag, pag, cpdag), (x, y) in ((:X, none), (none, :Y))
        @test_throws ArgumentError adjustment_set(cg, x, y)
        @test_throws ArgumentError is_valid_adjustment(cg, x, y, [:U])
        @test_throws ArgumentError all_adjustment_sets(cg, x, y)
    end

    for type in (:parents, :backdoor, :optimal)
        @test_throws ArgumentError adjustment_set(dag, :X, none; type)
        @test_throws ArgumentError adjustment_set(dag, none, :Y; type)
    end

    for cg in (dag, admg), (x, y) in ((:X, none), (none, :Y))
        @test_throws ArgumentError is_valid_backdoor(cg, x, y, [:U])
        @test_throws ArgumentError all_backdoor_sets(cg, x, y)
        @test_throws ArgumentError is_valid_frontdoor(cg, x, y, none)
        @test_throws ArgumentError frontdoor_set(cg, x, y)
        @test_throws ArgumentError all_frontdoor_sets(cg, x, y)
    end

    for cg in (dag, admg)
        @test_throws ArgumentError is_valid_iv(cg, :X, none, :U)
        @test_throws ArgumentError iv_set(cg, :X, none)
        @test_throws ArgumentError all_iv_sets(cg, :X, none)
    end

    # Separation with an empty side stays vacuously true.
    @test d_separated(dag, none, :Y)
end
