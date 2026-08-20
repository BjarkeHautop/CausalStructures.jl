# Tests adapted in part from caugi/tests/testthat/test-topological-sort.R


@testitem "topological_sort on simple chain DAG" setup=[DagHelpers] tags =
    [:unit, :topological_sort] begin
    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    order = topological_sort(dag)
    @test length(order) == 3
    @test Set(order) == Set([:A, :B, :C])
    @test verify_topo_order(dag, order)
end

@testitem "topological_sort on diamond DAG" setup=[DagHelpers] tags =
    [:unit, :topological_sort] begin
    cg = cgraph(
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

@testitem "topological_sort with isolated nodes" setup=[DagHelpers] tags =
    [:unit, :topological_sort] begin
    dag = cgraph(directed(:A, :B), node(:C); class = DAG)
    order = topological_sort(dag)
    @test length(order) == 3
    @test Set(order) == Set([:A, :B, :C])
    @test verify_topo_order(dag, order)
end

@testitem "topological_sort on empty DAG (only nodes, no edges)" tags =
    [:unit, :topological_sort] begin
    dag = cgraph(node(:A), node(:B), node(:C); class = DAG)
    order = topological_sort(dag)
    @test length(order) == 3
    @test Set(order) == Set([:A, :B, :C])
end

@testitem "topological_sort on single node DAG" tags = [:unit, :topological_sort] begin
    dag = cgraph(node(:A); class = DAG)
    order = topological_sort(dag)
    @test order == [:A]
end

@testitem "topological_sort errors on ADMG" tags = [:unit, :topological_sort] begin
    admg = cgraph(directed(:L, :X), directed(:X, :Y), directed(:L, :Y); class = ADMG)
    @test_throws MethodError topological_sort(admg)
end

@testitem "topological_sort errors on PDAG" tags = [:unit, :topological_sort] begin
    pdag = cgraph(directed(:A, :B), undirected(:B, :C), directed(:C, :D); class = PDAG)
    @test_throws MethodError topological_sort(pdag)
end

@testitem "topological_sort errors on UG" tags = [:unit, :topological_sort] begin
    ug = cgraph(undirected(:A, :B), undirected(:B, :C); class = UG)
    @test_throws MethodError topological_sort(ug)
end

@testitem "topological_sort returns all nodes exactly once" setup=[DagHelpers] tags =
    [:unit, :topological_sort] begin
    cg = cgraph(
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

@testitem "topological_sort NetworkX 1 test" setup=[DagHelpers] tags =
    [:unit, :topological_sort] begin
    # A -> B, A -> C, B -> C
    dag = cgraph(directed(:A, :B), directed(:A, :C), directed(:B, :C); class = DAG)
    order = topological_sort(dag)
    @test order == [:A, :B, :C]
    @test verify_topo_order(dag, order)

    # A -> B, A -> C, C -> B
    g2 = cgraph(directed(:A, :B), directed(:A, :C), directed(:C, :B); class = DAG)
    order2 = topological_sort(g2)
    @test order2 == [:A, :C, :B]
    @test verify_topo_order(g2, order2)
end

@testitem "topological_sort NetworkX 2 test" setup=[DagHelpers] tags =
    [:unit, :topological_sort] begin
    cg = cgraph(
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
