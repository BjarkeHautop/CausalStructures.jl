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

@testitem "_foreach_subset visits subsets in size-then-lexicographic order" tags =
    [:unit, :enumerate_subsets] begin
    for n = 0:6, min_size = 0:n, max_size = min_size:(n+1)
        # Brute force: every subset of 1:n via bitmasks, sorted by size, then
        # lexicographically.
        all_subsets = [[i for i = 1:n if (m >> (i - 1)) & 1 == 1] for m = 0:(2^n-1)]
        expected = sort(
            filter(s -> min_size <= length(s) <= max_size, all_subsets);
            by = s -> (length(s), s),
        )
        universe = collect(10:10:(10n))
        expected = [universe[s] for s in expected]

        visited = Vector{Int}[]
        CausalStructures._foreach_subset(
            c -> push!(visited, copy(c)),
            universe,
            min_size,
            max_size,
        )
        @test visited == expected

        # Starting from every rank (as a thread's chunk does) visits the
        # matching tail.
        total = length(expected)
        @test all(0:(total-1)) do lo
            ranged = Vector{Int}[]
            CausalStructures._foreach_subset(
                c -> push!(ranged, copy(c)),
                universe,
                min_size,
                lo,
                total - 1,
            )
            ranged == expected[(lo+1):end]
        end
    end
end
