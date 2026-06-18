# Simulation-based tests: generate random graphs and data to verify that
# structural and statistical properties hold empirically across many instances.


# ── Random-graph structural tests ─────────────────────────────────────────────

@testitem "sim: adjustment_set :backdoor is always valid on random DAGs" tags = [:sim] begin
    for seed = 1:25
        dag = generate_graph(6; p = 0.4, class = DAG, seed = seed)
        ns = nodes(dag)
        x, y = ns[1], ns[2]
        z = adjustment_set(dag, x, y; type = :backdoor)
        @test is_valid_backdoor(dag, x, y, z)
    end
end

@testitem "sim: adjustment_set :parents is always valid on random DAGs" tags = [:sim] begin
    for seed = 1:25
        dag = generate_graph(6; p = 0.4, class = DAG, seed = seed)
        ns = nodes(dag)
        x, y = ns[1], ns[2]
        z = adjustment_set(dag, x, y; type = :parents)
        @test is_valid_backdoor(dag, x, y, z)
    end
end

@testitem "sim: all_backdoor_sets - every returned set is valid" tags = [:sim] begin
    for seed = 1:15
        dag = generate_graph(5; p = 0.45, class = DAG, seed = seed)
        ns = nodes(dag)
        x, y = ns[1], ns[2]
        sets = all_backdoor_sets(dag, x, y; minimal = false, max_size = 3)
        for s in sets
            @test is_valid_backdoor(dag, x, y, s)
        end
    end
end

@testitem "sim: all_backdoor_sets minimal=true - no proper subset is also in the list" tags =
    [:sim] begin
    for seed = 1:15
        dag = generate_graph(5; p = 0.45, class = DAG, seed = seed)
        ns = nodes(dag)
        x, y = ns[1], ns[2]
        sets = all_backdoor_sets(dag, x, y; minimal = true)
        for (i, s) in enumerate(sets)
            for (j, t) in enumerate(sets)
                i == j && continue
                @test !(issubset(Set(t), Set(s)) && length(t) < length(s))
            end
        end
    end
end

@testitem "sim: topological sort - every parent precedes its child" tags = [:sim] begin
    for seed = 1:25
        dag = generate_graph(8; p = 0.35, class = DAG, seed = seed)
        order = topological_sort(dag)
        pos = Dict(v => i for (i, v) in enumerate(order))
        for e in dag.edges
            @test pos[e.src] < pos[e.dst]
        end
    end
end

@testitem "sim: ancestors/descendants are mutual in random DAGs" tags = [:sim] begin
    for seed = 1:15
        dag = generate_graph(7; p = 0.35, class = DAG, seed = seed)
        ns = nodes(dag)
        for x in ns[1:min(3, end)]
            for y in ns
                x == y && continue
                @test (y in ancestors(dag, x)) == (x in descendants(dag, y))
            end
        end
    end
end

@testitem "sim: Markov blanket separates node from non-blanket nodes" tags = [:sim] begin
    for seed = 1:15
        dag = generate_graph(6; p = 0.4, class = DAG, seed = seed)
        ns = nodes(dag)
        for v in ns[1:min(3, end)]
            mb = Set(markov_blanket(dag, v))
            for w in ns
                w == v && continue
                w in mb && continue
                @test d_separated(dag, v, w, collect(mb))
            end
        end
    end
end

# ── Data-simulation tests ─────────────────────────────────────────────────────

@testitem "sim: fork - marginal dependence, conditional independence given common cause" tags =
    [:sim] begin
    using Statistics
    # B --> A, B --> C: A and C share a common cause.
    # d_sep(A, C) = false; d_sep(A, C, [B]) = true.
    dag = cgraph(directed(:B, :A), directed(:B, :C); class = DAG)
    data = simulate_data(dag; samples = 50_000, standardize = false, seed = 1)
    n = 50_000

    @test !d_separated(dag, :A, :C)
    @test d_separated(dag, :A, :C, [:B])

    @test abs(cor(data[:A], data[:C])) > 0.1

    Z = hcat(ones(n), data[:B])
    rA = data[:A] - Z * (Z \ data[:A])
    rC = data[:C] - Z * (Z \ data[:C])
    @test abs(cor(rA, rC)) < 0.02
end

@testitem "sim: chain - marginal dependence, conditional independence given mediator" tags =
    [:sim] begin
    using Statistics
    # A --> B --> C: A and C are d-connected marginally but d-separated given B.
    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    data = simulate_data(dag; samples = 50_000, standardize = false, seed = 2)
    n = 50_000

    @test !d_separated(dag, :A, :C)
    @test d_separated(dag, :A, :C, [:B])

    @test abs(cor(data[:A], data[:C])) > 0.1

    Z = hcat(ones(n), data[:B])
    rA = data[:A] - Z * (Z \ data[:A])
    rC = data[:C] - Z * (Z \ data[:C])
    @test abs(cor(rA, rC)) < 0.02
end

@testitem "sim: collider - marginal independence, activation by conditioning on collider" tags =
    [:sim] begin
    using Statistics
    # A --> C <-- B: A and B are d-separated marginally but d-connected given C.
    dag = cgraph(directed(:A, :C), directed(:B, :C); class = DAG)
    data = simulate_data(dag; samples = 50_000, standardize = false, seed = 3)
    n = 50_000

    @test d_separated(dag, :A, :B)
    @test !d_separated(dag, :A, :B, [:C])

    @test abs(cor(data[:A], data[:B])) < 0.02

    Z = hcat(ones(n), data[:C])
    rA = data[:A] - Z * (Z \ data[:A])
    rB = data[:B] - Z * (Z \ data[:B])
    @test abs(cor(rA, rB)) > 0.1
end

@testitem "sim: adjustment set removes confounding in regression" tags = [:sim] begin
    using Statistics
    # A --> X, A --> Y, X --> Y (all coefficients fixed to 1.0).
    # True causal effect X --> Y = 1.0.
    # Without adjustment: OLS coefficient of Y ~ X is biased away from 1.
    # Adjusted for valid backdoor set {A}: coefficient of Y ~ X + A converges to 1.
    dag = cgraph(directed(:A, :X), directed(:A, :Y), directed(:X, :Y); class = DAG)

    z = adjustment_set(dag, :X, :Y; type = :backdoor)
    @test :A in z

    data = simulate_data(
        dag;
        samples = 100_000,
        standardize = false,
        coef_range = (1.0, 1.0),
        error_sd = 1.0,
        seed = 1405,
    )
    A, X, Y = data[:A], data[:X], data[:Y]
    n = length(X)

    β_unadj = hcat(ones(n), X) \ Y
    β_adj = hcat(ones(n), X, A) \ Y

    @test abs(β_unadj[2] - 1.0) > 0.1    # biased without adjustment
    @test abs(β_adj[2] - 1.0) < 0.05     # unbiased with adjustment
end
