using Test
using CausalGraphInterface

# ── Basic counts ────────────────────────────────────────────────────────────────

@testitem "count_mags: all-circle 2-path has 8 members" tags = [:unit] begin
    pag = cgraph(partial(:A, :B), partial(:B, :C); class = PAG)
    @test count_mags(pag) == 8
end

@testitem "count_mags: collider PAG has 4 members" tags = [:unit] begin
    pag = cgraph(partially_directed(:A, :B), partially_directed(:C, :B); class = PAG)
    @test count_mags(pag) == 4
end

@testitem "count_mags: an edgeless PAG has a single member" tags = [:unit] begin
    # No adjacencies => the empty MAG is the only graph in the class.
    pag = cgraph(node(:A), node(:B); class = PAG)
    @test count_mags(pag) == 1
    @test length(enumerate_mags(pag)) == 1
end

# ── Selection bias (--- and o-- edges) ──────────────────────────────────────────

@testitem "count_mags: undirected 4-cycle PAG has a single member" tags = [:unit] begin
    # A --- B --- C --- D --- A is a closed selection-bias PAG; only the 4-cycle
    # itself is in the class.
    mag = cgraph(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:A, :D);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test count_mags(pag) == 1
    @test all(is_mag, enumerate_mags(pag))
end

@testitem "enumerate_mags: handles a PAG with an o-- edge" tags = [:unit] begin
    include("helper-enumerate-mags.jl")
    # The pendant B --> E surfaces as E o-- B; both resolutions of the circle at E
    # (the directed edge and the undirected edge) are valid members of the class.
    mag = cgraph(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:A, :D),
        directed(:B, :E);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    mags = enumerate_mags(pag)
    @test length(mags) == count_mags(pag)
    @test all(is_mag, mags)
    @test all(m -> class_of(m) == mag_sig(pag), mags)
    @test any(m -> mag_sig(m) == mag_sig(mag), mags)   # the originating MAG is present
end

# ── count_mags and enumerate_mags agree ─────────────────────────────────────────

@testitem "enumerate_mags: count matches length, members are valid MAGs" tags = [:unit] begin
    pag = cgraph(partial(:A, :B), partial(:B, :C); class = PAG)
    mags = enumerate_mags(pag)
    @test length(mags) == count_mags(pag)
    @test all(is_mag, mags)
end

# ── Every member is in the class; the class is closed ───────────────────────────

@testitem "enumerate_mags: every member maps back to the PAG" tags = [:unit] begin
    include("helper-enumerate-mags.jl")
    mag = cgraph(directed(:A, :C), directed(:B, :C), directed(:C, :D); class = MAG)
    pag = mag_to_pag(mag)
    target = mag_sig(pag)
    for m in enumerate_mags(pag)
        @test class_of(m) == target
    end
end

@testitem "enumerate_mags: contains the originating MAG" tags = [:unit] begin
    include("helper-enumerate-mags.jl")
    mag = cgraph(
        bidirected(:D, :A),
        bidirected(:A, :B),
        directed(:A, :C),
        directed(:B, :C);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test any(m -> mag_sig(m) == mag_sig(mag), enumerate_mags(pag))
end

@testitem "enumerate_mags: contains the mag_from_pag representative" tags = [:unit] begin
    include("helper-enumerate-mags.jl")
    pag = cgraph(partial(:A, :B), partial(:B, :C); class = PAG)
    rep = mag_from_pag(pag)
    @test any(m -> mag_sig(m) == mag_sig(rep), enumerate_mags(pag))
end

# ── Members are distinct ─────────────────────────────────────────────────────────

@testitem "enumerate_mags: members are pairwise distinct" tags = [:unit] begin
    include("helper-enumerate-mags.jl")
    pag = cgraph(partial(:A, :B), partial(:B, :C); class = PAG)
    mags = enumerate_mags(pag)
    sigs = Set(mag_sig(m) for m in mags)
    @test length(sigs) == length(mags)
end
