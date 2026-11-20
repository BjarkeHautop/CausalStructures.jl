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

@testitem "_unrank_subset and _next_subset! agree with sequential order" tags =
    [:unit, :enumerate_subsets] begin
    for n = 0:6, min_size = 0:n, max_size = min_size:(n+1)
        expected = Vector{Int}[]
        for k = min_size:min(max_size, n)
            CausalStructures._all_subsets_rec!(expected, Int[], collect(1:n), n, 1, k)
        end
        pos = CausalStructures._unrank_subset(n, min_size, 0)
        for (r, s) in enumerate(expected)
            @test CausalStructures._unrank_subset(n, min_size, r - 1) == s
            @test pos == s
            r < length(expected) && CausalStructures._next_subset!(pos, n)
        end
    end
end

@testitem "_search_subsets_threaded matches sequential with min_size and oversized max_size" tags =
    [:unit, :enumerate_subsets] begin
    universe = [3, 5, 8, 9, 11, 12]
    make_checker() = (cur -> isodd(sum(cur; init = 1)))
    to_symbols(cur) = [Symbol(:v, i) for i in cur]
    for (lo, hi) in ((0, 10), (2, 4), (3, 3), (7, 9))
        @test CausalStructures._search_subsets_threaded(
            universe,
            lo,
            hi,
            make_checker,
            to_symbols,
        ) == CausalStructures._search_subsets_sequential(
            universe,
            lo,
            hi,
            make_checker,
            to_symbols,
        )
    end
end
