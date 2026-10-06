@testitem "include/restrict: all_adjustment_sets and all_backdoor_sets" tags = [:unit] begin
    dag = DAG("A --> X, B --> X, X --> Y, A --> Y")
    @test all_adjustment_sets(dag, :X, :Y; include = :B) == [[:A, :B]]
    @test isempty(all_adjustment_sets(dag, :X, :Y; restrict = :B))
    @test isempty(all_adjustment_sets(dag, :X, :Y; include = :Y))
    @test isempty(all_adjustment_sets(dag, :X, :Y; include = :B, max_size = 1))
    @test all_backdoor_sets(dag, :X, :Y; include = :B) == [[:A, :B]]
    @test isempty(all_backdoor_sets(dag, :X, :Y; include = :B, restrict = :B))
end

@testitem "include/restrict: single-set finders" tags = [:unit] begin
    dag = DAG("A --> X, B --> X, X --> Y, A --> C --> Y")
    @test adjustment_set(dag, :X, :Y; type = :backdoor, restrict = [:B, :C]) == [:C]
    @test adjustment_set(dag, :X, :Y; type = :backdoor, include = :B) == [:A, :B]
    @test_throws ArgumentError adjustment_set(dag, :X, :Y; include = :B)
    @test_throws ArgumentError adjustment_set(dag, :X, :Y; type = :parents, restrict = :A)
    @test backdoor_set(dag, :X, :Y) == [:A, :B]  # unconstrained: parents of X
    @test backdoor_set(dag, :X, :Y; restrict = [:B, :C]) == [:C]
    @test backdoor_set(dag, :X, :Y; restrict = :B) === nothing
    admg = ADMG("A --> X, B --> X, X --> Y, A --> C --> Y")
    @test adjustment_set(admg, :X, :Y; restrict = [:B, :C]) == [:C]
    @test backdoor_set(admg, :X, :Y; include = :B) == [:A, :B]
    mag = MAG("A <-> X, A --> M --> Y, X --> Y")
    @test adjustment_set(mag, :X, :Y; restrict = :M) == [:M]
    @test adjustment_set(mag, :X, :Y; include = :M) == [:M]
end

@testitem "include/restrict: all_iv_sets" tags = [:unit, :iv] begin
    dag = DAG("Z1 --> X, Z2 --> X, X --> Y, U --> X + Y, Z3")
    @test all_iv_sets(dag, :X, :Y; restrict = :Z2) == [[:Z2]]
    @test all_iv_sets(dag, :X, :Y; include = :Z3) == [[:Z1, :Z3], [:Z2, :Z3]]
    @test all_iv_sets(dag, :X, :Y; include = :Z1) == [[:Z1]]
    @test isempty(all_iv_sets(dag, :X, :Y; include = :U))
end

@testitem "include/restrict: agrees with filtering unconstrained results" tags = [:unit] begin
    using Random
    minimal_of(sets) = [s for s in sets if !any(t -> t != s && issubset(t, s), sets)]
    rng = Xoshiro(3)
    for trial = 1:300
        cls = (DAG, ADMG, MAG, PAG, CPDAG)[mod1(trial, 5)]
        latents = cls in (DAG, CPDAG) ? 0 : 2
        cg = generate_graph(rng, 6; p = 0.35, class = cls, latents = latents)
        ns = nodes(cg)
        length(ns) < 3 && continue
        x, y = ns[randperm(rng, length(ns))[1:2]]
        others = setdiff(ns, [x, y])
        R = rand(rng) < 0.3 ? nothing : others[rand(rng, length(others)) .< 0.7]
        pool = R === nothing ? others : R
        I = isempty(pool) || rand(rng) < 0.4 ? Symbol[] : [rand(rng, pool)]
        in_window(s) = issubset(I, s) && (R === nothing || issubset(s, R))

        finders = Any[all_adjustment_sets]
        cls in (DAG, ADMG) && push!(finders, all_backdoor_sets, all_iv_sets)
        for f in finders
            expected = Set(sort.(filter(in_window, f(cg, x, y; minimal = false))))
            @test Set(f(cg, x, y; minimal = false, include = I, restrict = R)) == expected
            @test Set(f(cg, x, y; include = I, restrict = R)) ==
                  Set(minimal_of(collect(expected)))
        end

        singles = Any[]
        if cls in (ADMG, MAG, PAG)
            push!(singles, (adjustment_set(cg, x, y; include = I, restrict = R), :adj))
        end
        # Unconstrained backdoor_set on a DAG returns the (non-minimal) parents of x.
        if cls == ADMG || (cls == DAG && (!isempty(I) || R !== nothing))
            push!(singles, (backdoor_set(cg, x, y; include = I, restrict = R), :bd))
        end
        if cls == DAG
            r = adjustment_set(cg, x, y; type = :backdoor, include = I, restrict = R)
            push!(singles, (r, :bd))
        end
        for (r, kind) in singles
            valid(z) =
                kind === :adj ? is_valid_adjustment(cg, x, y, z) :
                is_valid_backdoor(cg, x, y, z)
            all_sets = kind === :adj ? all_adjustment_sets : all_backdoor_sets
            exists = any(in_window, all_sets(cg, x, y; minimal = false, max_size = 6))
            @test (r !== nothing) == exists
            if r !== nothing
                @test in_window(r) && valid(r)
                @test all(v -> !valid(setdiff(r, [v])), setdiff(r, I))  # minimal
            end
        end
    end
end
