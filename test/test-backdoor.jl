# Ported from caugi/tests/testthat/test-adjustment.R (backdoor section)

using Test
using CausalGraphInterface

# Figure 6.5 from Elements of Causal Inference (p. 115)
# C→X, X→F, X→D, A→X, A→K, K→Y, D→Y, D→G, Y→H
function _eci_graph()
    caugi(
        directed(:C, :X),
        directed(:X, :F),
        directed(:X, :D),
        directed(:A, :X),
        directed(:A, :K),
        directed(:K, :Y),
        directed(:D, :Y),
        directed(:D, :G),
        directed(:Y, :H);
        class = DAG,
    )
end

@testitem "is_valid_backdoor: canonical choices on ECI graph" tags = [:unit] begin
    g = caugi(
        directed(:C, :X),
        directed(:X, :F),
        directed(:X, :D),
        directed(:A, :X),
        directed(:A, :K),
        directed(:K, :Y),
        directed(:D, :Y),
        directed(:D, :G),
        directed(:Y, :H);
        class = DAG,
    )
    @test is_valid_backdoor(g, :X, :Y, [:A])
    @test is_valid_backdoor(g, :X, :Y, [:K])
    @test !is_valid_backdoor(g, :X, :Y, [:D])       # D is a descendant of X
    @test !is_valid_backdoor(g, :X, :Y, [:A, :D])   # D is a descendant of X
    @test !is_valid_backdoor(g, :X, :Y)             # empty set: backdoor path A→X open
end

@testitem "all_backdoor_sets: minimal sets on ECI graph" tags = [:unit] begin
    g = caugi(
        directed(:C, :X),
        directed(:X, :F),
        directed(:X, :D),
        directed(:A, :X),
        directed(:A, :K),
        directed(:K, :Y),
        directed(:D, :Y),
        directed(:D, :G),
        directed(:Y, :H);
        class = DAG,
    )
    sets = all_backdoor_sets(g, :X, :Y; minimal = true)
    @test length(sets) == 2
    @test any(s -> s == [:A], sets)
    @test any(s -> s == [:K], sets)
end

@testitem "all_backdoor_sets: non-minimal with max_size=2" tags = [:unit] begin
    g = caugi(
        directed(:C, :X),
        directed(:X, :F),
        directed(:X, :D),
        directed(:A, :X),
        directed(:A, :K),
        directed(:K, :Y),
        directed(:D, :Y),
        directed(:D, :G),
        directed(:Y, :H);
        class = DAG,
    )
    sets = all_backdoor_sets(g, :X, :Y; minimal = false, max_size = 2)
    @test length(sets) == 5
    set_strings = Set(join(sort(s), ",") for s in sets)
    @test "A" in set_strings
    @test "K" in set_strings
    @test "A,K" in set_strings
    @test "A,C" in set_strings
    @test "C,K" in set_strings
end

@testitem "all_backdoor_sets: empty set valid when v-structure blocks backdoor" tags =
    [:unit] begin
    # A→L, K→L forms a collider on L, blocking A→X backdoor path
    g = caugi(
        directed(:C, :X),
        directed(:X, :F),
        directed(:X, :D),
        directed(:A, :X),
        directed(:A, :L),
        directed(:K, :L),
        directed(:K, :Y),
        directed(:D, :Y),
        directed(:D, :G),
        directed(:Y, :H);
        class = DAG,
    )
    @test is_valid_backdoor(g, :X, :Y)

    sets = all_backdoor_sets(g, :X, :Y; minimal = false, max_size = 2)
    set_strings = Set(join(sort(s), ",") for s in sets)
    expected = Set(["", "C", "A", "K", "A,K", "A,C", "C,K", "A,L", "K,L"])
    @test set_strings == expected
end

@testitem "is_valid_backdoor: mediator graph" tags = [:unit] begin
    g = caugi(directed(:X, :M), directed(:M, :Y), directed(:Y, :S); class = DAG)
    @test is_valid_backdoor(g, :X, :Y)
    @test !is_valid_backdoor(g, :X, :Y, [:M])   # M is a descendant of X
end

@testitem "all_backdoor_sets: mediator graph returns only empty set" tags = [:unit] begin
    g = caugi(directed(:X, :M), directed(:M, :Y), directed(:Y, :S); class = DAG)
    sets = all_backdoor_sets(g, :X, :Y; minimal = true, max_size = 1)
    @test length(sets) == 1
    @test sets[1] == Symbol[]
end

@testitem "is_valid_backdoor: collider-driven candidates" tags = [:unit] begin
    g = caugi(
        directed(:A, :Z),
        directed(:B, :Z),
        directed(:A, :X),
        directed(:B, :Y);
        class = DAG,
    )
    @test !is_valid_backdoor(g, :X, :Y, [:Z])        # Z is a collider; conditioning opens path
    @test is_valid_backdoor(g, :X, :Y, [:A])
    @test is_valid_backdoor(g, :X, :Y, [:A, :Z])
    @test is_valid_backdoor(g, :X, :Y, [:B, :Z])
end

@testitem "all_backdoor_sets: collider graph non-minimal" tags = [:unit] begin
    g = caugi(
        directed(:A, :Z),
        directed(:B, :Z),
        directed(:A, :X),
        directed(:B, :Y);
        class = DAG,
    )
    sets = all_backdoor_sets(g, :X, :Y; minimal = false, max_size = 2)
    set_strings = Set(join(sort(s), ",") for s in sets)
    @test "" in set_strings
    @test "A,Z" in set_strings
    @test "B,Z" in set_strings
end

@testitem "is_valid_backdoor: chain graph — empty set valid" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_valid_backdoor(g, :A, :C)
    @test !is_valid_backdoor(g, :A, :C, [:B])  # B is a descendant of A
end
