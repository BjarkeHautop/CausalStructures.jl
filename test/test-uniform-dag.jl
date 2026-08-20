# ── uniform_dag ─────────────────────────────────────────────────────────────

@testitem "uniform_dag: errors on invalid n" tags = [:unit, :uniform_dag] begin
    @test_throws ErrorException uniform_dag(0)
    @test_throws ErrorException uniform_dag(-3)
end

@testitem "uniform_dag: n=1 yields a single node and no edges" tags = [:unit, :uniform_dag] begin
    using Random
    dag = uniform_dag(Random.Xoshiro(1), 1)
    @test dag isa DAG
    @test nodes(dag) == [:V1]
    @test isempty(dag.edges)
end

@testitem "uniform_dag: returns a valid DAG with correct nodes" tags = [:unit, :uniform_dag] begin
    using Random
    n = 8
    dag = uniform_dag(Random.Xoshiro(7), n)
    @test dag isa DAG
    @test is_dag(dag)
    @test is_acyclic(dag)
    @test Set(nodes(dag)) == Set([Symbol("V$i") for i = 1:n])
end

@testitem "uniform_dag: reproducible with same seed" tags = [:unit, :uniform_dag] begin
    using Random
    g1 = uniform_dag(Random.Xoshiro(42), 9)
    g2 = uniform_dag(Random.Xoshiro(42), 9)
    @test Set((e.src, e.dst) for e in g1.edges) == Set((e.src, e.dst) for e in g2.edges)
end

@testitem "uniform_dag: DAG counts match A003024 (labelled DAGs by n)" tags =
    [:unit, :uniform_dag] begin
    a = CausalStructures._uniform_dag_counts(8)
    a_n = [sum(a[m]) for m = 1:8]
    @test a_n == BigInt[1, 3, 25, 543, 29281, 3781503, 1138779265, 783702329343]
end

@testitem "uniform_dag: outpoint counts for n=5 match Kuipers & Moffa Table 1" tags =
    [:unit, :uniform_dag] begin
    a = CausalStructures._uniform_dag_counts(5)
    @test a[5] == BigInt[16885, 10710, 1610, 75, 1]
end

@testitem "uniform_dag: reproduces the Kuipers & Moffa worked example" tags =
    [:unit, :uniform_dag] begin
    # Section 4.3: for n=5, drawing r=28405 yields the outpoint sequence
    # k_1=3, k_2=1, k_3=1.
    a = CausalStructures._uniform_dag_counts(5)
    ks = CausalStructures._uniform_dag_outpoints(a, 5, BigInt(28405))
    @test ks == [3, 1, 1]
end

@testitem "uniform_dag: outpoint sequences always sum to n" tags = [:unit, :uniform_dag] begin
    n = 12
    a = CausalStructures._uniform_dag_counts(n)
    a_n = sum(a[n])
    for r in BigInt[1, 2, a_n, a_n÷2, a_n-1]
        ks = CausalStructures._uniform_dag_outpoints(a, n, r)
        @test sum(ks) == n
        @test all(>=(1), ks)
    end
end

@testitem "uniform_dag: exhaustive uniformity check against brute force (n=3)" tags =
    [:unit, :uniform_dag] begin
    using Random

    # Brute-force every labelled DAG on 3 nodes: 3 states (none, i->j, j->i)
    # per unordered pair, filtered to acyclic configurations.
    function brute_force_dags(n::Int)
        pairs = [(i, j) for i = 1:n for j = (i+1):n]
        dags = Set{Set{Tuple{Int,Int}}}()
        for code = 0:(3^length(pairs)-1)
            c = code
            es = Tuple{Int,Int}[]
            for (i, j) in pairs
                d = c % 3
                c = c ÷ 3
                d == 1 && push!(es, (i, j))
                d == 2 && push!(es, (j, i))
            end
            adj = [Int[] for _ = 1:n]
            for (s, t) in es
                push!(adj[s], t)
            end
            color = zeros(Int, n)
            acyclic = true
            for start = 1:n
                color[start] != 0 && continue
                # simple recursive DFS via closure over `color`/`acyclic`
                function dfs(u)
                    color[u] = 1
                    for v in adj[u]
                        if color[v] == 1
                            acyclic = false
                            return
                        elseif color[v] == 0
                            dfs(v)
                            acyclic || return
                        end
                    end
                    color[u] = 2
                end
                dfs(start)
                acyclic || break
            end
            acyclic && push!(dags, Set(es))
        end
        return dags
    end

    n = 3
    bf = brute_force_dags(n)
    @test length(bf) == 25

    rng = Random.Xoshiro(2)
    nsamples = 50_000
    counts = Dict{Set{Tuple{Int,Int}},Int}()
    for _ = 1:nsamples
        dag = uniform_dag(rng, n)
        key = Set(
            (parse(Int, String(e.src)[2:end]), parse(Int, String(e.dst)[2:end])) for
            e in dag.edges
        )
        @test key in bf
        counts[key] = get(counts, key, 0) + 1
    end

    @test length(counts) == length(bf)  # full coverage

    expected = nsamples / length(bf)
    chi2 = sum((c - expected)^2 / expected for c in values(counts))
    # Generous threshold: for df=24, chi2 should be nowhere near e.g. 60
    @test chi2 < 60
end
