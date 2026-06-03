# Ported from caugi/tests/testthat/test-metrics.R
# shd and hd are not yet implemented.
# All tests are marked @test_broken.

using Test
using CausalGraphInterface

# ── SHD (Structural Hamming Distance) ─────────────────────────────────────────

@testitem "SHD: identical graphs have SHD of 0 (broken)" tags = [:unit] begin
    g1 = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test_broken shd(g1, g2) == 0
end

@testitem "SHD: graphs with different nodes error (broken)" tags = [:unit] begin
    g1 = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = caugi(directed(:A, :B), directed(:B, :D); class = DAG)
    @test_broken shd(g1, g2) isa Integer
end

@testitem "SHD: one edge difference (broken)" tags = [:unit] begin
    g1 = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG)
    @test_broken shd(g1, g2) == 1
end

@testitem "SHD: symmetrical undirected edges give SHD 0 (broken)" tags = [:unit] begin
    g1 = caugi(undirected(:A, :B); class = UG)
    g2 = caugi(undirected(:B, :A); class = UG)
    @test_broken shd(g1, g2) == 0
end

@testitem "SHD: different edge order gives SHD 0 (broken)" tags = [:unit] begin
    g1 = caugi(directed(:A, :B), directed(:B, :C), directed(:D, :C); class = DAG)
    g2 = caugi(directed(:D, :C), directed(:B, :C), directed(:A, :B); class = DAG)
    @test_broken shd(g1, g2) == 0
end

@testitem "SHD: detects actual differences despite different edge order (broken)" tags =
    [:unit] begin
    g1 = caugi(directed(:A, :B), directed(:B, :C); class = PDAG)
    g2 = caugi(directed(:B, :C), undirected(:A, :B); class = PDAG)
    @test_broken shd(g1, g2) == 1
end

# ── HD (Hamming Distance) ──────────────────────────────────────────────────────

@testitem "HD: identical graphs have HD of 0 (broken)" tags = [:unit] begin
    g1 = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test_broken hd(g1, g2) == 0
end

@testitem "HD: graphs with different nodes error (broken)" tags = [:unit] begin
    g1 = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = caugi(directed(:A, :B), directed(:B, :D); class = DAG)
    @test_broken hd(g1, g2) isa Integer
end

@testitem "HD: symmetrical undirected edges give HD 0 (broken)" tags = [:unit] begin
    g1 = caugi(undirected(:A, :B); class = UG)
    g2 = caugi(undirected(:B, :A); class = UG)
    @test_broken hd(g1, g2) == 0
end

@testitem "HD: one edge difference gives same result regardless of type (broken)" tags =
    [:unit] begin
    g_ref = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    g2 = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG)
    g3 = caugi(directed(:A, :B), bidirected(:B, :C); class = ADMG)
    @test_broken hd(g_ref, g2) == hd(g_ref, g3)
end
