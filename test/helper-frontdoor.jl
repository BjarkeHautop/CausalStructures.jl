# ── Jeong, Tian & Bareinboim (2022) Fig. 1 ───────────────────────────────────
#
# Fig. 1a: G: X --> Z --> Y, bidirected X <-> Y (latent confounder U -> X, U -> Y).
#   {Z} is the canonical front-door set.
#
# Fig. 1b: G': X --> A --> {B, C, D} --> Y
#   Bidirected X <-> Y (latent U1 -> X, U1 -> Y)
#   Bidirected X <-> D (latent U2 -> X, U2 -> D)
#
#   The four valid FD sets relative to (X, Y) are: {A}, {A,B}, {A,C}, {A,B,C}.
#   D is excluded from every valid set because the BD path X <-- U2 --> D is open.
#
# Reference: Jeong, Tian & Bareinboim (2022). Finding and Listing Front-Door
#   Adjustment Sets. NeurIPS 2022.

# Fig. 1b as a DAG with explicit latents.
function _jeong2022_fig1b()
    caugi(
        directed(:U1, :X),
        directed(:U1, :Y),
        directed(:U2, :X),
        directed(:U2, :D),
        directed(:X, :A),
        directed(:A, :B),
        directed(:A, :C),
        directed(:A, :D),
        directed(:B, :Y),
        directed(:C, :Y),
        directed(:D, :Y);
        class = DAG,
    )
end

# Fig. 6a: G with two parallel mediating paths and one latent confounder.
# 9 valid FD adjustment sets (3^2): each path i can be intercepted by Ai, Bi, or {Ai,Bi}.
function _jeong2022_fig6a()
    caugi(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:X, :A1),
        directed(:A1, :B1),
        directed(:B1, :Y),
        directed(:X, :A2),
        directed(:A2, :B2),
        directed(:B2, :Y);
        class = DAG,
    )
end

# Fig. 6b: G' = G with a third parallel mediating path added.
# 27 valid FD adjustment sets (3^3).
function _jeong2022_fig6b()
    caugi(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:X, :A1),
        directed(:A1, :B1),
        directed(:B1, :Y),
        directed(:X, :A2),
        directed(:A2, :B2),
        directed(:B2, :Y),
        directed(:X, :A3),
        directed(:A3, :B3),
        directed(:B3, :Y);
        class = DAG,
    )
end
