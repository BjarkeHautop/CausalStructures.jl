@testitem "possible_d_sep matches the worked backdoor_set(::MAG) example, before M_X removes the visible edge" tags =
    [:unit, :possible_d_sep] begin
    mag = cgraph(
        bidirected(:A, :X),
        directed(:A, :M),
        directed(:M, :Y),
        directed(:X, :Y);
        class = MAG,
    )
    # X --> Y is visible (witness A via A <-> X), so backdoor_set works on M_X
    # with that edge removed and gets a smaller answer than the raw D-SEP.
    @test possible_d_sep(mag, :X, :Y) == [:A, :M, :Y]
    @test backdoor_set(mag, :X, :Y) == [:A]
end

@testitem "possible_d_sep accepts a set of target nodes" tags = [:unit, :possible_d_sep] begin
    mag = cgraph(
        directed(:B, :X),
        bidirected(:A, :X),
        directed(:A, :Y1),
        directed(:A, :Y2),
        directed(:X, :Y1),
        directed(:X, :Y2);
        class = MAG,
    )
    @test possible_d_sep(mag, :X, [:Y1, :Y2]) == [:A, :B, :Y1, :Y2]
end

@testitem "possible_d_sep works on AG" tags = [:unit, :possible_d_sep] begin
    ag = cgraph(
        bidirected(:A, :X),
        directed(:A, :M),
        directed(:M, :Y),
        directed(:X, :Y);
        class = AG,
    )
    @test possible_d_sep(ag, :X, :Y) == [:A, :M, :Y]
end

@testitem "possible_d_sep excludes x itself and returns nothing when x has no collider paths" tags =
    [:unit, :possible_d_sep] begin
    mag = cgraph(directed(:X, :Y); class = MAG)
    @test :X ∉ possible_d_sep(mag, :X, :Y)
    @test possible_d_sep(mag, :X, :Y) == [:Y]
end
