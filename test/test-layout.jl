# All layout methods require NetworkLayoutExt; tested in
# test-networklayout-ext.jl.

@testitem "layout: unknown method errors with a helpful message" tags = [:unit] begin
    dag = cgraph(directed(:A, :B); class = DAG)
    @test_throws ErrorException layout(dag, :bogus)
end
