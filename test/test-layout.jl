# The :circle method and the layout() dispatcher are always available (no
# extension needed); :spring/:stress/etc. require NetworkLayoutExt and are
# tested in test-networklayout-ext.jl instead.

@testitem "layout: :circle places nodes evenly on a unit circle" tags = [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = DAG)
    pos = layout(dag, :circle)
    @test length(pos) == 4
    @test all(p -> isapprox(hypot(p[1], p[2]), 1.0; atol = 1e-10), pos)
end

@testitem "layout: :circle handles 0 and 1 nodes" tags = [:unit] begin
    empty_g = cgraph(class = DAG)
    @test layout(empty_g, :circle) == NTuple{2,Float64}[]

    single = cgraph(node(:A); class = DAG)
    @test layout(single, :circle) == [(0.0, 0.0)]
end

@testitem "layout: unknown method errors with a helpful message" tags = [:unit] begin
    dag = cgraph(directed(:A, :B); class = DAG)
    @test_throws ErrorException layout(dag, :bogus)
end
