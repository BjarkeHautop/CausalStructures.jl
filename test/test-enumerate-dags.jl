# Tests for enumerate_dags and count_dags
# Tests adapted in part from caugi/src/rust/src/graph/pdag/enumerate.rs

using Test
using CausalGraphInterface

@testitem "enumerate_dags: chain A--B--C has 3 DAGs, none is A->B<-C" tags = [:unit] begin
    pdag = cgraph(undirected(:A, :B), undirected(:B, :C); class = PDAG)
    dags = enumerate_dags(pdag)
    @test length(dags) == 3
    @test all(d -> d isa DAG, dags)
    for d in dags
        @test !((:A in parents(d, :B)) && (:C in parents(d, :B)))
    end
end

@testitem "count_dags: chain A--B--C returns 3" tags = [:unit] begin
    pdag = cgraph(undirected(:A, :B), undirected(:B, :C); class = PDAG)
    @test count_dags(pdag) == 3
end

@testitem "enumerate_dags: v-structure A->B<-C returns singleton" tags = [:unit] begin
    pdag = cgraph(directed(:A, :B), directed(:C, :B); class = PDAG)
    dags = enumerate_dags(pdag)
    @test length(dags) == 1
    @test :A in parents(dags[1], :B)
    @test :C in parents(dags[1], :B)
end

@testitem "count_dags: v-structure A->B<-C returns 1" tags = [:unit] begin
    pdag = cgraph(directed(:A, :B), directed(:C, :B); class = PDAG)
    @test count_dags(pdag) == 1
end

@testitem "enumerate_dags: undirected triangle has 6 DAGs (all distinct)" tags = [:unit] begin
    include("helpers.jl")
    pdag = cgraph(undirected(:A, :B), undirected(:A, :C), undirected(:B, :C); class = PDAG)
    dags = enumerate_dags(pdag)
    @test length(dags) == 6
    sigs = Set(Set(directed_pairs(d)) for d in dags)
    @test length(sigs) == 6
end

@testitem "count_dags: undirected triangle returns 6" tags = [:unit] begin
    pdag = cgraph(undirected(:A, :B), undirected(:A, :C), undirected(:B, :C); class = PDAG)
    @test count_dags(pdag) == 6
end

@testitem "enumerate_dags: v-structure plus undirected branch forced by Meek R1" tags =
    [:unit] begin
    # A->C<-B, C--D: R1 orients C->D, so MEC has exactly 1 DAG
    pdag = cgraph(directed(:A, :C), directed(:B, :C), undirected(:C, :D); class = PDAG)
    dags = enumerate_dags(pdag)
    @test length(dags) == 1
    @test :A in parents(dags[1], :C)
    @test :B in parents(dags[1], :C)
    @test :C in parents(dags[1], :D)
end

@testitem "count_dags: v-structure plus undirected branch returns 1" tags = [:unit] begin
    pdag = cgraph(directed(:A, :C), directed(:B, :C), undirected(:C, :D); class = PDAG)
    @test count_dags(pdag) == 1
end

@testitem "enumerate_dags: two independent chains multiply" tags = [:unit] begin
    # A--B (2 DAGs) and C--D--E (3 DAGs): 2 * 3 = 6
    pdag = cgraph(undirected(:A, :B), undirected(:C, :D), undirected(:D, :E); class = PDAG)
    dags = enumerate_dags(pdag)
    @test length(dags) == 6
end

@testitem "count_dags: two independent chains returns 6" tags = [:unit] begin
    pdag = cgraph(undirected(:A, :B), undirected(:C, :D), undirected(:D, :E); class = PDAG)
    @test count_dags(pdag) == 6
end

@testitem "enumerate_dags: empty graph returns 1 DAG (the empty DAG)" tags = [:unit] begin
    pdag = cgraph(node(:A), node(:B); class = PDAG)
    dags = enumerate_dags(pdag)
    @test length(dags) == 1
    @test dags[1] isa DAG
end

@testitem "enumerate_dags count matches count_dags" tags = [:unit] begin
    pdag = cgraph(undirected(:A, :B), undirected(:B, :C), undirected(:C, :D); class = PDAG)
    @test length(enumerate_dags(pdag)) == count_dags(pdag)
end

@testitem "enumerate_dags: accepts CPDAG input" tags = [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    cp = dag_to_cpdag(dag)
    @test cp isa CPDAG
    dags = enumerate_dags(cp)
    @test all(d -> d isa DAG, dags)
end
