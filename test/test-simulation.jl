# Tests adapted in part from caugi/tests/testthat/test-simulation.R

using Test
using CausalGraphInterface
# ── generate_graph ────────────────────────────────────────────────────────────

@testitem "generate_graph: errors on invalid n" tags = [:unit] begin
    @test_throws ErrorException generate_graph(0; m = 0)
end

@testitem "generate_graph: errors on invalid p" tags = [:unit] begin
    @test_throws ErrorException generate_graph(4; p = -0.1)
    @test_throws ErrorException generate_graph(4; p = 1.1)
end

@testitem "generate_graph: errors on invalid m" tags = [:unit] begin
    n = 4
    tot = n * (n - 1) ÷ 2
    @test_throws ErrorException generate_graph(n; m = -1)
    @test_throws ErrorException generate_graph(n; m = tot + 1)
end

@testitem "generate_graph: errors when neither m nor p supplied" tags = [:unit] begin
    @test_throws ErrorException generate_graph(5)
end

@testitem "generate_graph: errors when both m and p supplied" tags = [:unit] begin
    @test_throws ErrorException generate_graph(5; m = 2, p = 0.1)
end

@testitem "generate_graph: DAG with m=0 yields 0 edges and correct nodes" tags = [:unit] begin
    n = 5
    dag = generate_graph(n; m = 0, class = DAG)
    @test dag isa DAG
    @test length(nodes(dag)) == n
    @test isempty(dag.edges)
    @test Set(nodes(dag)) == Set([Symbol("V$i") for i = 1:n])
end

@testitem "generate_graph: DAG with p=0 yields 0 edges" tags = [:unit] begin
    dag = generate_graph(6; p = 0.0, class = DAG)
    @test isempty(dag.edges)
end

@testitem "generate_graph: m=tot yields full tournament DAG" tags = [:unit] begin
    n = 6
    tot = n * (n - 1) ÷ 2
    dag = generate_graph(n; m = tot, seed = 11, class = DAG)
    @test length(dag.edges) == tot
    @test all(
        e ->
            e.src_end == CausalGraphInterface.Tail &&
            e.dst_end == CausalGraphInterface.Arrow,
        dag.edges,
    )
end

@testitem "generate_graph: reproducible with same seed" tags = [:unit] begin
    g1 = generate_graph(7; m = 8, seed = 42, class = DAG)
    g2 = generate_graph(7; m = 8, seed = 42, class = DAG)
    @test Set(nodes(g1)) == Set(nodes(g2))
    @test length(g1.edges) == length(g2.edges)
end

@testitem "generate_graph: CPDAG class returns CPDAG" tags = [:unit] begin
    dag = generate_graph(6; m = 5, class = CPDAG)
    @test dag isa CPDAG
    @test length(nodes(dag)) == 6
end

@testitem "generate_graph: unsupported class gives TypeError" tags = [:unit] begin
    @test_throws TypeError generate_graph(4; m = 2, class = UG)
end

# ── simulate_data ─────────────────────────────────────────────────────────────

@testitem "simulate_data: errors on non-DAG graph class" tags = [:unit] begin
    pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG)
    @test_throws MethodError simulate_data(pdag; samples = 10)

    ug = caugi(undirected(:A, :B); class = UG)
    @test_throws MethodError simulate_data(ug; samples = 10)
end

@testitem "simulate_data: errors on empty graph" tags = [:unit] begin
    empty_dag = caugi(; class = DAG)
    @test_throws ErrorException simulate_data(empty_dag; samples = 10)
end

@testitem "simulate_data: errors on invalid samples" tags = [:unit] begin
    dag = caugi(directed(:A, :B); class = DAG)
    @test_throws ErrorException simulate_data(dag; samples = 0)
    @test_throws ErrorException simulate_data(dag; samples = -5)
end

@testitem "simulate_data: returns dict with correct keys" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    data = simulate_data(dag; samples = 100, seed = 1)
    @test data isa Dict
    @test Set(keys(data)) == Set([:A, :B, :C])
end

@testitem "simulate_data: correct number of samples" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    data = simulate_data(dag; samples = 100, seed = 1)
    @test all(v -> length(v) == 100, values(data))
end

@testitem "simulate_data: reproducible with seed" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C), directed(:A, :C); class = DAG)
    data1 = simulate_data(dag; samples = 100, seed = 42)
    data2 = simulate_data(dag; samples = 100, seed = 42)
    @test data1[:A] == data2[:A]
    @test data1[:B] == data2[:B]
    @test data1[:C] == data2[:C]
end

@testitem "simulate_data: different seeds produce different data" tags = [:unit] begin
    dag = caugi(directed(:A, :B); class = DAG)
    data1 = simulate_data(dag; samples = 100, seed = 1)
    data2 = simulate_data(dag; samples = 100, seed = 2)
    @test data1[:A] != data2[:A]
end

@testitem "simulate_data: standardize=true yields mean≈0 and sd≈1" tags = [:unit] begin
    using Statistics
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    data = simulate_data(dag; samples = 1000, standardize = true, seed = 123)
    for (_, v) in data
        @test abs(mean(v)) < 1e-10
        @test abs(std(v) - 1.0) < 1e-10
    end
end

@testitem "simulate_data: standardize=false does not standardize" tags = [:unit] begin
    using Statistics
    dag = caugi(directed(:A, :B); class = DAG)
    data = simulate_data(dag; samples = 1000, standardize = false, seed = 42)
    means_zero = all(abs(mean(v)) < 0.01 for (_, v) in data)
    sds_one = all(abs(std(v) - 1.0) < 0.01 for (_, v) in data)
    @test !(means_zero && sds_one)
end

@testitem "simulate_data: endogenous nodes correlate with parents" tags = [:unit] begin
    using Statistics
    dag = caugi(directed(:A, :B); class = DAG)
    data = simulate_data(dag; samples = 10_000, standardize = false, seed = 1)
    r = cor(data[:A], data[:B])
    @test abs(r) > 0.05
end

@testitem "simulate_data: single node graph works" tags = [:unit] begin
    dag = caugi(node(:A); class = DAG)
    data = simulate_data(dag; samples = 50, seed = 1)
    @test haskey(data, :A)
    @test length(data[:A]) == 50
end

@testitem "simulate_data: graph with no edges (all exogenous)" tags = [:unit] begin
    using Statistics
    dag = caugi(node(:A), node(:B), node(:C); class = DAG)
    data = simulate_data(dag; samples = 100, standardize = false, seed = 1)
    @test length(keys(data)) == 3
    @test std(data[:A]) > 0
    @test std(data[:B]) > 0
    @test std(data[:C]) > 0
end

@testitem "simulate_data: deep chain graph" tags = [:unit] begin
    dag = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:C, :D),
        directed(:D, :E);
        class = DAG,
    )
    data = simulate_data(dag; samples = 100, seed = 1)
    @test Set(keys(data)) == Set([:A, :B, :C, :D, :E])
    @test all(v -> length(v) == 100, values(data))
end

@testitem "simulate_data: collider structure A and B independent" tags = [:unit] begin
    using Statistics
    dag = caugi(directed(:A, :C), directed(:B, :C); class = DAG)
    data = simulate_data(dag; samples = 10_000, standardize = false, seed = 1)
    r_ab = cor(data[:A], data[:B])
    @test abs(r_ab) < 0.05
    @test abs(cor(data[:A], data[:C])) > 0.05
    @test abs(cor(data[:B], data[:C])) > 0.05
end
