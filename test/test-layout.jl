# All layout methods require NetworkLayoutExt; tested in
# test-networklayout-ext.jl.

@testitem "layout: unknown method errors with a helpful message" tags = [:unit, :layout] begin
    dag = DAG(directed(:A, :B))
    @test_throws ErrorException layout(dag, :bogus)
end
