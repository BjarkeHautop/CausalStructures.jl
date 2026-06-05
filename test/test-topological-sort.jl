# Ported from caugi/tests/testthat/test-topological-sort.R

using Test
using CausalGraphInterface

@testitem "topological_sort on simple chain DAG" tags = [:unit] begin
    include("helpers.jl")
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    order = topological_sort(dag)
    @test length(order) == 3
    @test Set(order) == Set([:A, :B, :C])
    @test verify_topo_order(dag, order)
end

@testitem "topological_sort on diamond DAG" tags = [:unit] begin
    include("helpers.jl")
    cg = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )
    order = topological_sort(cg)
    @test length(order) == 4
    @test Set(order) == Set([:A, :B, :C, :D])
    @test verify_topo_order(cg, order)
end

@testitem "topological_sort with isolated nodes" tags = [:unit] begin
    include("helpers.jl")
    dag = caugi(directed(:A, :B), node(:C); class = DAG)
    order = topological_sort(dag)
    @test length(order) == 3
    @test Set(order) == Set([:A, :B, :C])
    @test verify_topo_order(dag, order)
end

@testitem "topological_sort on empty DAG (only nodes, no edges)" tags = [:unit] begin
    dag = caugi(node(:A), node(:B), node(:C); class = DAG)
    order = topological_sort(dag)
    @test length(order) == 3
    @test Set(order) == Set([:A, :B, :C])
end

@testitem "topological_sort on single node DAG" tags = [:unit] begin
    dag = caugi(node(:A); class = DAG)
    order = topological_sort(dag)
    @test order == [:A]
end

@testitem "topological_sort errors on ADMG" tags = [:unit] begin
    admg = caugi(directed(:L, :X), directed(:X, :Y), directed(:L, :Y); class = ADMG)
    @test_throws MethodError topological_sort(admg)
end

@testitem "topological_sort errors on PDAG" tags = [:unit] begin
    pdag = caugi(directed(:A, :B), undirected(:B, :C), directed(:C, :D); class = PDAG)
    @test_throws MethodError topological_sort(pdag)
end

@testitem "topological_sort errors on UG" tags = [:unit] begin
    ug = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError topological_sort(ug)
end

@testitem "topological_sort returns all nodes exactly once" tags = [:unit] begin
    include("helpers.jl")
    cg = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D),
        node(:E);
        class = DAG,
    )
    order = topological_sort(cg)
    @test Set(order) == Set([:A, :B, :C, :D, :E])
    @test length(order) == length(unique(order))
    @test verify_topo_order(cg, order)
end

# NetworkX topological sort tests
# https://github.com/networkx/networkx/blob/main/networkx/algorithms/tests/test_dag.py

@testitem "topological_sort NetworkX 1 test" tags = [:unit] begin
    include("helpers.jl")
    # A -> B, A -> C, B -> C
    dag = caugi(directed(:A, :B), directed(:A, :C), directed(:B, :C); class = DAG)
    order = topological_sort(dag)
    @test order == [:A, :B, :C]
    @test verify_topo_order(dag, order)

    # A -> B, A -> C, C -> B
    g2 = caugi(directed(:A, :B), directed(:A, :C), directed(:C, :B); class = DAG)
    order2 = topological_sort(g2)
    @test order2 == [:A, :C, :B]
    @test verify_topo_order(g2, order2)
end

@testitem "topological_sort NetworkX 2 test" tags = [:unit] begin
    include("helpers.jl")
    cg = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:C, :D),
        directed(:D, :E);
        class = DAG,
    )
    order = topological_sort(cg)
    @test order == [:A, :B, :C, :D, :E]
    @test verify_topo_order(cg, order)
end
