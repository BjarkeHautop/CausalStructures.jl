@testitem "_search_subsets_threaded matches _search_subsets_sequential" tags =
    [:unit, :enumerate_subsets] begin
    universe = collect(1:7)
    nodes = [:A, :B, :C, :D, :E, :F, :G]

    make_checker() = (cur -> iseven(sum(cur; init = 0)))
    to_symbols(cur) = sort([nodes[i] for i in cur])

    sequential = CausalStructures._search_subsets_sequential(
        universe,
        0,
        4,
        make_checker,
        to_symbols,
    )
    threaded =
        CausalStructures._search_subsets_threaded(universe, 0, 4, make_checker, to_symbols)

    @test threaded == sequential
    @test !isempty(threaded)
end

@testitem "_search_subsets_threaded: checker rejecting everything yields no sets" tags =
    [:unit, :enumerate_subsets] begin
    universe = collect(1:5)
    nodes = [:A, :B, :C, :D, :E]

    make_checker() = Returns(false)
    to_symbols(cur) = sort([nodes[i] for i in cur])

    threaded =
        CausalStructures._search_subsets_threaded(universe, 0, 3, make_checker, to_symbols)

    @test isempty(threaded)
end

@testitem "_search_subsets_threaded: min_size restricts subset sizes" tags =
    [:unit, :enumerate_subsets] begin
    universe = collect(1:4)
    nodes = [:A, :B, :C, :D]

    make_checker() = Returns(true)
    to_symbols(cur) = sort([nodes[i] for i in cur])

    threaded =
        CausalStructures._search_subsets_threaded(universe, 2, 3, make_checker, to_symbols)

    @test all(s -> length(s) in (2, 3), threaded)
    @test length(threaded) == binomial(4, 2) + binomial(4, 3)
end
