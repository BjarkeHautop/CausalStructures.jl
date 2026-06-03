# Ported from caugi/tests/testthat/test-topological-sort.R
# (igraph comparison tests skipped — require external dependency)

using Test
using CausalGraphInterface

@testitem "topological_sort on simple chain DAG" tags = [:unit] begin
    include("helpers.jl")
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    order = topological_sort(g)
    @test length(order) == 3
    @test Set(order) == Set([:A, :B, :C])
    @test verify_topo_order(g, order)
end

@testitem "topological_sort on diamond DAG" tags = [:unit] begin
    include("helpers.jl")
    g = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )
    order = topological_sort(g)
    @test length(order) == 4
    @test Set(order) == Set([:A, :B, :C, :D])
    @test verify_topo_order(g, order)
end

@testitem "topological_sort with isolated nodes" tags = [:unit] begin
    include("helpers.jl")
    g = caugi(directed(:A, :B), node(:C); class = DAG)
    order = topological_sort(g)
    @test length(order) == 3
    @test Set(order) == Set([:A, :B, :C])
    @test verify_topo_order(g, order)
end

@testitem "topological_sort on empty DAG (only nodes, no edges)" tags = [:unit] begin
    g = caugi(node(:A), node(:B), node(:C); class = DAG)
    order = topological_sort(g)
    @test length(order) == 3
    @test Set(order) == Set([:A, :B, :C])
end

@testitem "topological_sort on single node DAG" tags = [:unit] begin
    g = caugi(node(:A); class = DAG)
    order = topological_sort(g)
    @test order == [:A]
end

@testitem "topological_sort errors on ADMG" tags = [:unit] begin
    g = caugi(directed(:L, :X), directed(:X, :Y), directed(:L, :Y); class = ADMG)
    @test_throws MethodError topological_sort(g)
end

@testitem "topological_sort errors on PDAG" tags = [:unit] begin
    g = caugi(directed(:A, :B), undirected(:B, :C), directed(:C, :D); class = PDAG)
    @test_throws MethodError topological_sort(g)
end

@testitem "topological_sort errors on UG" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError topological_sort(g)
end

@testitem "topological_sort returns all nodes exactly once" tags = [:unit] begin
    include("helpers.jl")
    g = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D),
        node(:E);
        class = DAG,
    )
    order = topological_sort(g)
    @test Set(order) == Set([:A, :B, :C, :D, :E])
    @test length(order) == length(unique(order))
    @test verify_topo_order(g, order)
end

# NetworkX topological sort tests
# https://github.com/networkx/networkx/blob/main/networkx/algorithms/tests/test_dag.py

@testitem "topological_sort NetworkX 1 test" tags = [:unit] begin
    include("helpers.jl")
    # A -> B, A -> C, B -> C
    g = caugi(directed(:A, :B), directed(:A, :C), directed(:B, :C); class = DAG)
    order = topological_sort(g)
    @test order == [:A, :B, :C]
    @test verify_topo_order(g, order)

    # A -> B, A -> C, C -> B
    g2 = caugi(directed(:A, :B), directed(:A, :C), directed(:C, :B); class = DAG)
    order2 = topological_sort(g2)
    @test order2 == [:A, :C, :B]
    @test verify_topo_order(g2, order2)
end

@testitem "topological_sort NetworkX 2 test" tags = [:unit] begin
    include("helpers.jl")
    g = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:C, :D),
        directed(:D, :E);
        class = DAG,
    )
    order = topological_sort(g)
    @test order == [:A, :B, :C, :D, :E]
    @test verify_topo_order(g, order)
end
