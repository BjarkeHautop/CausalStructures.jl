module TrimCheck

using CausalStructures

# Exercises the public API

# --- src/core: construction, edges, background knowledge, edit -------------

function _check_construction()
    DAG("A --> B --> C, B --> D")
    UG("A --- B --- C")
    PDAG("A --> B, B --- C")
    CPDAG("A --> X <-- C, X --> Y")
    MPDAG("A --> B --> C")
    ADMG("A --> X, X --> Y, U <-> Y, U <-> X")
    AG("A --> B, B --> C")
    MAG("A <-> X, A --> Y, X --> Y")
    PAG("A o-o B, B o-o C")
    UNKNOWN("A --> B, A <-> B")

    directed(:A, :B)
    undirected(:A, :B)
    bidirected(:A, :B)
    partially_directed(:A, :B)
    partially_undirected(:A, :B)
    partial(:A, :B)
    required_directed(:A, :B)
    forbidden_directed(:A, :B)
    node(:A)

    BackgroundKnowledge("A --> B, C !--> D")
    return nothing
end

function _check_edit()
    dag = DAG("A --> B")
    dag = add_edges(dag, directed(:B, :C), directed(:C, :D))
    dag = add_nodes(dag, :E)
    dag = remove_edges(dag, directed(:C, :D))
    dag = remove_nodes(dag, :E)
    has_edge(dag, :A, :B)
    nodes(dag)
    edges(dag)

    reclass(dag, PDAG)
    reclass(dag, ADMG)

    cpdag = CPDAG("A --> X <-- C, X --> Y")
    reclass(cpdag, PDAG)

    mag = MAG("A --> B <-- C")
    reclass(mag, AG)
    return nothing
end

# --- src/io/utils.jl: class predicates --------------------------------------

function _check_predicates()
    is_dag(PDAG("A --> B --> C"))
    is_pdag(PDAG("A --> B"))
    is_cpdag(DAG("A --> B"))
    is_mpdag(DAG("A --> B --> C"))
    is_ug(PDAG("A --- B"))
    is_admg(UNKNOWN("A <-> B"))
    is_ag(UNKNOWN("A <-> B"))
    is_mag(AG("A --> B --> C"))
    is_pag(mag_to_pag(MAG("A --> B <-- C")))
    is_simple(DAG("A --> B"))
    is_acyclic(DAG("A --> B --> C"))
    return nothing
end

# --- src/query/traversal.jl -------------------------------------------------

# ancestors/descendants: Union{DAG,AbstractPDAG,ADMG,AbstractAG}
function _check_ancestral(cg)
    nd = last(nodes(cg))
    ancestors(cg, nd)
    descendants(cg, nd)
    return nothing
end

# markov_blanket: separate methods for DAG, AbstractPDAG, ADMG, AbstractAG
function _check_markov_blanket(cg)
    markov_blanket(cg, last(nodes(cg)))
    return nothing
end

# anteriors/posteriors: Union{AbstractPDAG,AbstractAG}
function _check_anteriors_posteriors(cg)
    nd = last(nodes(cg))
    anteriors(cg, nd)
    posteriors(cg, nd)
    return nothing
end

# possible_ancestors/possible_descendants: AbstractPDAG, PAG
function _check_possible_anc_desc(cg)
    nd = last(nodes(cg))
    possible_ancestors(cg, nd)
    possible_descendants(cg, nd)
    return nothing
end

function _check_traversal()
    dag = DAG("A --> X, B --> X, X --> Y, A --> Y")
    neighbors(dag, :X)
    parents(dag, :Y)
    children(dag, :A)
    topological_sort(dag)
    exogenous_nodes(dag)
    _check_ancestral(dag)
    _check_markov_blanket(dag)

    pdag = PDAG("A --> B, B --- C")
    exogenous_nodes(pdag)
    _check_ancestral(pdag)
    _check_markov_blanket(pdag)
    _check_anteriors_posteriors(pdag)
    _check_possible_anc_desc(pdag)

    cpdag = CPDAG("A --> X <-- C, X --> Y")
    exogenous_nodes(cpdag)
    _check_ancestral(cpdag)
    _check_markov_blanket(cpdag)
    _check_anteriors_posteriors(cpdag)
    _check_possible_anc_desc(cpdag)

    mpdag = MPDAG("A --> B --> C")
    exogenous_nodes(mpdag)
    _check_ancestral(mpdag)
    _check_markov_blanket(mpdag)
    _check_anteriors_posteriors(mpdag)
    _check_possible_anc_desc(mpdag)

    admg = ADMG("A --> X, X --> Y, U <-> Y, U <-> X")
    neighbors(admg, :X; mode = :bidirected)
    parents(admg, :X)
    children(admg, :A)
    spouses(admg, :X)
    districts(admg)
    exogenous_nodes(admg)
    _check_ancestral(admg)
    _check_markov_blanket(admg)

    ag = AG("A --> B --> C")
    neighbors(ag, :B; mode = :undirected)
    parents(ag, :B)
    children(ag, :A)
    spouses(ag, :A)
    districts(ag)
    exogenous_nodes(ag)
    _check_ancestral(ag)
    _check_markov_blanket(ag)
    _check_anteriors_posteriors(ag)

    mag = MAG("A <-> X, A --> M --> Y, X --> Y")
    neighbors(mag, :A; mode = :bidirected)
    parents(mag, :Y)
    children(mag, :A)
    spouses(mag, :A)
    districts(mag)
    exogenous_nodes(mag)
    _check_ancestral(mag)
    _check_markov_blanket(mag)
    _check_anteriors_posteriors(mag)

    pag = PAG("A o-o B, B o-o C, C o-o D, D o-o A, A o-o C")
    neighbors(pag, :A)
    parents(pag, :A)
    children(pag, :A)
    spouses(pag, :A)
    _check_possible_anc_desc(pag)

    unk = UNKNOWN("A --> B, A <-> B")
    neighbors(unk, :A)
    parents(unk, :A)
    children(unk, :A)

    ug = UG("A --- B --- C")
    neighbors(ug, :B)
    return nothing
end

# --- src/query/separation.jl, minimal-separator.jl, possible-d-sep.jl ------

function _check_separation()
    dag = DAG("A --> B --> C")
    d_separated(dag, :A, :C, [:B])
    minimal_separator(dag, :A, :C)

    cpdag = CPDAG("A --> X <-- C, X --> Y")
    d_separated(cpdag, :A, :C, Symbol[])
    minimal_separator(cpdag, :A, :C)

    admg = ADMG("A --> X, X --> Y, U <-> Y, U <-> X")
    m_separated(admg, :A, :Y, Symbol[])
    minimal_separator(admg, :A, :Y)

    mag = MAG("A <-> X, A --> M --> Y, X --> Y")
    m_separated(mag, :A, :Y, [:M])
    minimal_separator(mag, :A, :Y)
    possible_d_sep(mag, :X, :Y)

    pag = PAG("A o-o B, B o-o C, C o-o D, D o-o A, A o-o C")
    m_separated(pag, :A, :C, Symbol[])
    minimal_separator(pag, :A, :C)
    return nothing
end

# --- src/identification/adjustment-{admg,mag,pag,pdag}.jl ------------------

function _check_adjustment()
    dag = DAG("Z --> X + Y, X --> Y")
    is_valid_adjustment(dag, :X, :Y, [:Z])
    all_adjustment_sets(dag, :X, :Y)
    adjustment_set(dag, :X, :Y)

    admg = ADMG("X --> M, M --> Y, X <-> Y")
    is_valid_adjustment(admg, :X, :Y, Symbol[])
    all_adjustment_sets(admg, :X, :Y)
    adjustment_set(admg, :X, :Y)

    cpdag = CPDAG("A --> X <-- C, X --> Y")
    is_valid_adjustment(cpdag, :X, :Y, Symbol[])
    all_adjustment_sets(cpdag, :X, :Y)
    adjustment_set(cpdag, :X, :Y)

    mag = MAG("A <-> X, A --> M --> Y, X --> Y")
    is_valid_adjustment(mag, :X, :Y, [:A])
    all_adjustment_sets(mag, :X, :Y)
    adjustment_set(mag, :X, :Y)

    pag = PAG("A o-o B, B o-o C, C o-o D, D o-o A, A o-o C")
    is_valid_adjustment(pag, :A, :C, Symbol[])
    all_adjustment_sets(pag, :A, :C)
    adjustment_set(pag, :A, :C)
    return nothing
end

# --- src/identification/backdoor{,-pdag,-mag,-pag}.jl ----------------------

function _check_backdoor()
    dag = DAG("A --> X --> Y, A --> Y")
    is_valid_backdoor(dag, :X, :Y, [:A])
    all_backdoor_sets(dag, :X, :Y)
    backdoor_set(dag, :X, :Y)

    admg = ADMG("X --> M, M --> Y, X <-> Y")
    is_valid_backdoor(admg, :X, :Y, Symbol[])
    all_backdoor_sets(admg, :X, :Y)

    cpdag = CPDAG("A --> X <-- C, X --> Y")
    backdoor_set(cpdag, :X, :Y)

    mag = MAG("A <-> X, A --> M --> Y, X --> Y")
    backdoor_set(mag, :X, :Y)

    pag = PAG("A o-o B, B o-o C, C o-o D, D o-o A, A o-o C")
    backdoor_set(pag, :A, :C)
    return nothing
end

# --- src/identification/frontdoor.jl ----------------------------------------

function _check_frontdoor()
    dag = DAG("U --> X --> M --> Y, U --> Y")
    is_valid_frontdoor(dag, :X, :Y, [:M])
    frontdoor_set(dag, :X, :Y)
    all_frontdoor_sets(dag, :X, :Y)

    admg = ADMG("X --> M, M --> Y, X <-> Y")
    is_valid_frontdoor(admg, :X, :Y, [:M])
    frontdoor_set(admg, :X, :Y)
    all_frontdoor_sets(admg, :X, :Y)
    return nothing
end

# --- src/identification/iv.jl -----------------------------------------------

function _check_iv()
    dag = DAG("Z1 --> X, Z2 --> X, X --> Y, U --> X + Y")
    is_valid_iv(dag, :X, :Y, [:Z1])
    all_iv_sets(dag, :X, :Y)

    admg = ADMG("Z --> X, X --> Y, U <-> X, U <-> Y")
    is_valid_iv(admg, :X, :Y, [:Z])
    all_iv_sets(admg, :X, :Y)
    return nothing
end

# --- src/identification/id.jl, estimand.jl ----------------------------------
#
# Currently broken; the recursive struct fields not allowed in
# --trim=safe mode.
function _check_id_not_trim_safe()
    dag = DAG("Z --> X + Y, X --> Y")
    id(dag, :X, :Y)
    idc(dag, :X, :Y; given = :Z)

    admg = ADMG("X --> M, M --> Y, X <-> Y")
    id(admg, :X, :Y)
    idc(admg, :X, :Y; given = Symbol[])

    bow = ADMG("X --> Y, X <-> Y")
    id(bow, :X, :Y)

    e = marginal([:Z], product([prob(:Y; given = [:X, :Z]), prob(:Z)]))
    quotient(prob([:Y, :Z]; given = [:X]), prob(:Z; given = [:X]))
    string(e)
    return nothing
end

# --- src/identification/condition-marginalize.jl ----------------------------

function _check_condition_marginalize()
    dag = DAG("U --> X + Y")
    condition_marginalize(dag; marg_vars = [:U])

    admg = ADMG("U --> X + Y, X --> Y")
    condition_marginalize(admg; marg_vars = [:U])

    ag = AG("C <-> A <-> B <-> D, A --> D, B --> C")
    condition_marginalize(ag; cond_vars = [:C])
    return nothing
end

# --- src/identification/possible-{joint-parent,adjustment}-sets.jl ---------

function _check_possible_sets()
    cpdag = CPDAG("X1 --- X2 + X3 + X4, X3 + X4 --> Y")
    possible_parent_sets(cpdag, :X1)
    possible_joint_parent_sets(cpdag, [:X1, :X2])
    possible_optimal_adjustment_sets(cpdag, :X1, :Y)
    return nothing
end

# --- src/identification/pagcauses.jl, transform/local-structure.jl ---------

function _check_pagcauses()
    pag = PAG("X o-> Y, X o-> C, X o-> A, Y o-o C, C o-o A, B o-> C, B o-> Y, B o-> A")
    pagcauses(pag, :X, :Y)

    structures = possible_local_structures(pag, :X)
    maximal_local_mag(pag, :X, first(structures))
    return nothing
end

# --- src/transform/pdag.jl, background-knowledge.jl -------------------------

function _check_pdag_transform()
    pdag = PDAG("A --- B --- C")
    dag_from_pdag(pdag)
    meek_closure(pdag)
    apply_background_knowledge(pdag, "C --> B")

    cpdag = CPDAG("A --- B --- C")
    dag_from_pdag(cpdag)
    meek_closure(cpdag)
    apply_background_knowledge(cpdag, BackgroundKnowledge(required_directed(:A, :B)))

    mpdag = MPDAG("A --- B --- C")
    dag_from_pdag(mpdag)
    meek_closure(mpdag)
    apply_background_knowledge(mpdag, "C --> B")

    dag = DAG("A --> B --> C")
    dag_to_cpdag(dag)
    dag_to_mpdag(dag, "A --> B")
    markov_equivalent(dag, DAG("A --> B --> C"))

    ag = AG("A --> B --> C")
    ag_to_mag(ag)
    return nothing
end

# --- src/transform/mag.jl ----------------------------------------------------

function _check_mag_transform()
    mag = MAG("A --> B <-- C")
    mag_to_pag(mag)

    pag = mag_to_pag(MAG("A <-> X, B --> X, A <-> B, X --> Y"))
    mag_from_pag(pag)
    return nothing
end

# --- src/transform/latent.jl -------------------------------------------------

function _check_latent()
    dag = DAG("U --> X + Y, X --> Y")
    latent_project(dag, [:U])
    exogenize(dag, [:X])
    normalize_latent_structure(dag, [:U])
    return nothing
end

# --- src/transform/skeleton-subgraph.jl --------------------------------------

function _check_skeleton_subgraph()
    dag = DAG("A --> B --> C, A --> C")
    skeleton(dag)
    moralize(DAG("A --> C <-- B"))
    subgraph(dag, [:A, :B])

    pdag = PDAG("A --> B --- C")
    skeleton(pdag)
    moralize(pdag)
    subgraph(pdag, [:A, :B])
    return nothing
end

# --- src/transform/enumerate-dags.jl, enumerate-mags.jl ---------------------

function _check_enumerate()
    pdag = PDAG("A --- B --- C")
    count_dags(pdag)
    enumerate_dags(pdag)

    cpdag = CPDAG("A --- B --- C")
    count_dags(cpdag)
    enumerate_dags(cpdag)

    pag = PAG("A o-o B o-o C")
    enumerate_mags(pag)
    return nothing
end

# --- src/io/utils.jl, uniform-dag.jl, layout.jl ------------------------------

function _check_io()
    generate_graph(6; m = 5)
    generate_graph(6; m = 5, class = CPDAG)
    generate_graph(10; p = 0.3, class = ADMG, latents = 2)
    generate_graph(10; p = 0.3, class = MAG, latents = 2)
    generate_graph(10; p = 0.3, class = PAG, latents = 2)

    dag = DAG("A --> B --> C")
    simulate_data(dag; samples = 20)

    uniform_dag(5)

    try
        layout(dag)
        layout(dag, :spring)
    catch
    end
    return nothing
end

Base.@ccallable function trim_check_run()::Cint
    _check_construction()
    _check_edit()
    _check_predicates()
    _check_traversal()
    _check_separation()
    _check_adjustment()
    _check_backdoor()
    _check_frontdoor()
    _check_iv()
    _check_condition_marginalize()
    _check_possible_sets()
    _check_pagcauses()
    _check_pdag_transform()
    _check_mag_transform()
    _check_latent()
    _check_skeleton_subgraph()
    _check_enumerate()
    _check_io()
    return Cint(0)
end

end # module
