abstract type GraphConstraints end

struct DAGConstraints <: GraphConstraints end
struct PDAGConstraints <: GraphConstraints end
struct UGConstraints <: GraphConstraints end
struct ADMGConstraints <: GraphConstraints end
struct AGConstraints <: GraphConstraints end
struct CPDAGConstraints <: GraphConstraints end
struct UNKNOWNConstraints <: GraphConstraints end

function directed_cycle_detected(g::CausalGraph)
    nodes = g.backend.nodes
    edges = g.edges

    children_map = Dict(node => Set{Symbol}() for node in nodes)
    indegree = Dict(node => 0 for node in nodes)

    for edge in edges
        if is_directed(edge)
            push!(children_map[edge.src], edge.dst)
            indegree[edge.dst] += 1
        end
    end

    queue = [node for node in nodes if indegree[node] == 0]

    visited = 0

    while !isempty(queue)
        node = popfirst!(queue)
        visited += 1

        for child in children_map[node]
            indegree[child] -= 1
            if indegree[child] == 0
                push!(queue, child)
            end
        end
    end

    return visited != length(nodes)
end

function validation_errors(::DAGConstraints, g::CausalGraph)
    errors = String[]

    all(is_directed, g.edges) || push!(errors, "invalid edge type for graph class DAG")

    all(e -> e.src != e.dst, g.edges) || push!(errors, "self-loops are not allowed in DAG")

    directed_cycle_detected(g) && push!(errors, "directed cycles are not allowed in DAG")

    return errors
end

function validation_errors(::PDAGConstraints, g::CausalGraph)
    errors = String[]

    all(e -> is_directed(e) || is_undirected(e), g.edges) ||
        push!(errors, "invalid edge type for graph class PDAG")

    all(e -> e.src != e.dst, g.edges) || push!(errors, "self-loops are not allowed in PDAG")

    directed_cycle_detected(g) && push!(errors, "directed cycles are not allowed in PDAG")

    return errors
end

function validation_errors(::UGConstraints, g::CausalGraph)
    errors = String[]

    all(is_undirected, g.edges) || push!(errors, "invalid edge type for graph class UG")

    all(e -> e.src != e.dst, g.edges) || push!(errors, "self-loops are not allowed in UG")

    return errors
end

function validation_errors(::ADMGConstraints, g::CausalGraph)
    errors = String[]

    all(e -> is_directed(e) || is_bidirected(e), g.edges) ||
        push!(errors, "invalid edge type for graph class ADMG")

    all(e -> e.src != e.dst, g.edges) || push!(errors, "self-loops are not allowed in ADMG")

    directed_cycle_detected(g) && push!(errors, "directed cycles are not allowed in ADMG")

    return errors
end

function validation_errors(::UNKNOWNConstraints, g::UNKNOWN)
    errors = String[]

    if g.simple && !is_simple(g)
        push!(errors, "graph marked simple=true but contains self-loops or parallel edges")
    end

    return errors
end

_satisfies_constraints(c::GraphConstraints, g::CausalGraph) =
    isempty(validation_errors(c, g))

function _satisfies_constraints(::UNKNOWNConstraints, g::UNKNOWN)
    if g.simple
        return is_simple(g)
    end

    return true
end

_fast_skip(g::CausalGraph, ::DAGConstraints) = g isa DAG
_fast_skip(g::CausalGraph, ::PDAGConstraints) = g isa AbstractPDAG || g isa DAG || g isa UG
_fast_skip(g::CausalGraph, ::CPDAGConstraints) = g isa CPDAG
_fast_skip(g::CausalGraph, ::UGConstraints) = g isa UG
_fast_skip(g::CausalGraph, ::ADMGConstraints) = g isa ADMG || g isa DAG
_fast_skip(g::CausalGraph, ::AGConstraints) = g isa AG || g isa DAG

function _class_matches_or_satisfies(g::CausalGraph, constraints::GraphConstraints)
    _fast_skip(g, constraints) && return true
    return _satisfies_constraints(constraints, g)
end

function validation_errors(::AGConstraints, g::CausalGraph)
    errors = String[]

    all(e -> is_directed(e) || is_undirected(e) || is_bidirected(e), g.edges) ||
        push!(errors, "invalid edge type for graph class AG")

    all(e -> e.src != e.dst, g.edges) || push!(errors, "self-loops are not allowed in AG")

    directed_cycle_detected(g) && push!(errors, "directed cycles are not allowed in AG")

    isempty(errors) || return errors

    # Need AGBackend for structural constraint checks
    B = g.backend isa AGBackend ? g.backend : build_backend(AG, nodes(g), g.edges)
    n = length(B.nodes)

    # Undirected constraint: if a node has an undirected edge it must have no arrowheads
    for i = 1:n
        if !isempty(_undirected_slice(B, i)) &&
           (!isempty(_parents_slice(B, i)) || !isempty(_spouses_slice(B, i)))
            push!(
                errors,
                "AG undirected constraint violated at node $(B.nodes[i]): " *
                "has both undirected edge and arrowhead",
            )
        end
    end

    # Anterior constraint: if arrowhead at v from u, v must not be an anterior of u.
    if isempty(errors)
        for v = 1:n
            for u in _parents_slice(B, v)
                if _anterior_bitmask(B, [u])[v]
                    push!(
                        errors,
                        "AG anterior constraint violated: $(B.nodes[v]) is anterior of " *
                        "$(B.nodes[u]) but $(B.nodes[u]) --> $(B.nodes[v]) exists",
                    )
                end
            end
            for u in _spouses_slice(B, v)
                u > v || continue  # check each bidirected pair once
                ant_u = _anterior_bitmask(B, [u])
                ant_v = _anterior_bitmask(B, [v])
                if ant_u[v]
                    push!(
                        errors,
                        "AG anterior constraint violated: $(B.nodes[v]) is anterior of " *
                        "$(B.nodes[u]) in bidirected edge",
                    )
                end
                if ant_v[u]
                    push!(
                        errors,
                        "AG anterior constraint violated: $(B.nodes[u]) is anterior of " *
                        "$(B.nodes[v]) in bidirected edge",
                    )
                end
            end
        end
    end

    return errors
end

# ── CPDAGConstraints helpers ──────────────────────────────────────────────────

# Chain components: connected components of the undirected subgraph.
function _cpdag_chain_components(B::PDAGBackend, n::Int)
    comp = zeros(Int, n)  # 0 = unvisited; assigned 1..c
    cid = 0
    stack = Int[]
    for s = 1:n
        comp[s] != 0 && continue
        cid += 1
        comp[s] = cid
        push!(stack, s)
        while !isempty(stack)
            u = pop!(stack)
            for w in _undirected_slice(B, u)
                if comp[w] == 0
                    comp[w] = cid
                    push!(stack, w)
                end
            end
        end
    end
    return comp, cid
end

# True if any directed edge stays within one chain component.
function _cpdag_has_intra_arrows(B::PDAGBackend, n::Int, comp::Vector{Int})
    for u = 1:n
        cu = comp[u]
        for v in _children_slice(B, u)
            comp[v] == cu && return true
        end
    end
    return false
end

# Kahn topological sort on the DAG of chain components.
function _cpdag_component_dag_acyclic(B::PDAGBackend, n::Int, comp::Vector{Int}, c::Int)
    succ = [Int[] for _ = 1:c]
    indeg = zeros(Int, c)
    seen = Set{Tuple{Int,Int}}()
    for u = 1:n
        cu = comp[u]
        for v in _children_slice(B, u)
            cv = comp[v]
            if cu != cv
                key = (cu, cv)
                if key ∉ seen
                    push!(seen, key)
                    push!(succ[cu], cv)
                    indeg[cv] += 1
                end
            end
        end
    end
    queue = [k for k = 1:c if indeg[k] == 0]
    cnt = 0
    while !isempty(queue)
        x = pop!(queue)
        cnt += 1
        for y in succ[x]
            indeg[y] -= 1
            indeg[y] == 0 && push!(queue, y)
        end
    end
    return cnt == c
end

# True if two sorted index slices share an element (two-pointer merge).
function _cpdag_intersects(a, b)
    i = j = 1
    while i <= length(a) && j <= length(b)
        if a[i] == b[j]
            return true
        elseif a[i] < b[j]
            i += 1
        else
            j += 1
        end
    end
    return false
end

# True if j is in the sorted slice.
function _cpdag_in_sorted(j::Int, arr)
    !isempty(searchsorted(arr, j))
end

# True if nodes i and j are adjacent (in any bucket).
function _cpdag_adjacent(B::PDAGBackend, i::Int, j::Int)
    _cpdag_in_sorted(j, _parents_slice(B, i)) && return true
    _cpdag_in_sorted(j, _undirected_slice(B, i)) && return true
    _cpdag_in_sorted(j, _children_slice(B, i)) && return true
    return false
end

# True if there is a directed path from src to dst following children.
function _cpdag_has_dir_path(B::PDAGBackend, src::Int, dst::Int, n::Int)
    visited = falses(n)
    stack = [src]
    while !isempty(stack)
        u = pop!(stack)
        visited[u] && continue
        visited[u] = true
        for v in _children_slice(B, u)
            v == dst && return true
            !visited[v] && push!(stack, v)
        end
    end
    return false
end

# MCS maximum cardinality search + PEO clique test (chordalilty per component).
function _cpdag_components_chordal(B::PDAGBackend, n::Int, comp::Vector{Int}, c::Int)
    nodes_in = [Int[] for _ = 1:c]
    for v = 1:n
        push!(nodes_in[comp[v]], v)
    end

    label = zeros(Int, n)
    numbered = falses(n)
    in_c = falses(n)
    pos = zeros(Int, n)

    for nodes in nodes_in
        length(nodes) <= 2 && continue

        for v in nodes
            in_c[v] = true
            numbered[v] = false
            label[v] = 0
        end

        # MCS: build ordering
        order = Int[]
        sizehint!(order, length(nodes))
        for _ = 1:length(nodes)
            pick = 0
            best = -1
            for v in nodes
                if !numbered[v] && label[v] > best
                    pick = v
                    best = label[v]
                end
            end
            if pick == 0
                for v in nodes
                    ;
                    in_c[v] = false;
                end
                return false
            end
            push!(order, pick)
            numbered[pick] = true
            for w in _undirected_slice(B, pick)
                in_c[w] && !numbered[w] && (label[w] += 1)
            end
        end

        # pos[v] = rank in reverse order (last MCS pick → rank 1)
        for (i, v) in enumerate(Iterators.reverse(order))
            pos[v] = i
        end

        # PEO clique test: for each v in elimination order,
        # its undirected neighbors with higher rank must form a clique.
        for (i, v) in enumerate(Iterators.reverse(order))
            higher = [w for w in _undirected_slice(B, v) if in_c[w] && pos[w] > i]
            if length(higher) > 1
                sort!(higher, by = w -> pos[w])
                pvt = higher[end]
                for w in @view higher[1:(end-1)]
                    if !_cpdag_in_sorted(pvt, _undirected_slice(B, w))
                        for x in nodes
                            ;
                            in_c[x] = false;
                        end
                        return false
                    end
                end
            end
        end

        for v in nodes
            ;
            in_c[v] = false;
        end
    end
    return true
end

# True if no Meek orientation rule (R1–R4) would fire.
# Mirrors the safeguards in meek_closure so this is consistent with it.
function _cpdag_meek_closed(B::PDAGBackend, n::Int)
    # R1: u→v, v—w, u ⊄ w  ⇒  v→w  (unless cycle or new collider)
    for v = 1:n
        pa = _parents_slice(B, v)
        isempty(pa) && continue
        for w in _undirected_slice(B, v)
            for u in pa
                _cpdag_adjacent(B, u, w) && continue
                _cpdag_has_dir_path(B, w, v, n) && continue  # would create cycle
                creates_collider =
                    any(p -> p != v && !_cpdag_adjacent(B, v, p), _parents_slice(B, w))
                creates_collider && continue
                return false
            end
        end
    end

    # R2: u—v, ∃ w: u→w→v  ⇒  u→v
    for v = 1:n
        pa_v = _parents_slice(B, v)
        for u in _undirected_slice(B, v)
            _cpdag_intersects(_children_slice(B, u), pa_v) && return false
        end
    end

    # R3: u—v, ∃ w,x: w→v, x→v, w ⊄ x, u—w, u—x  ⇒  u→v
    for v = 1:n
        pv = _parents_slice(B, v)
        length(pv) < 2 && continue
        for u in _undirected_slice(B, v)
            und_u = _undirected_slice(B, u)
            for i in eachindex(pv), j = (i+1):lastindex(pv)
                w, x = pv[i], pv[j]
                if !_cpdag_adjacent(B, w, x) &&
                   _cpdag_in_sorted(w, und_u) &&
                   _cpdag_in_sorted(x, und_u)
                    return false
                end
            end
        end
    end

    # R4: u—v and directed path u⇒v or v⇒u
    for v = 1:n
        for u in _undirected_slice(B, v)
            (_cpdag_has_dir_path(B, u, v, n) || _cpdag_has_dir_path(B, v, u, n)) &&
                return false
        end
    end

    return true
end

# True if every directed edge a→b is strongly protected (VS, SP1, SP2, SP3).
function _cpdag_arrows_protected(B::PDAGBackend, n::Int)
    for a = 1:n
        for b in _children_slice(B, a)
            pa_b = _parents_slice(B, b)
            # VS: ∃ c→b, c ≠ a, c ⊄ a
            any(c -> c != a && !_cpdag_adjacent(B, c, a), pa_b) && continue
            # SP1: ∃ c→a, c ⊄ b
            any(c -> !_cpdag_adjacent(B, c, b), _parents_slice(B, a)) && continue
            # SP2: ∃ c: a→c, c→b
            _cpdag_intersects(_children_slice(B, a), pa_b) && continue
            # SP3: ∃ c,d→b, c ⊄ d, a—c, a—d
            und_a = _undirected_slice(B, a)
            sp3 = false
            for i in eachindex(pa_b), j = (i+1):lastindex(pa_b)
                c1, c2 = pa_b[i], pa_b[j]
                if !_cpdag_adjacent(B, c1, c2) &&
                   _cpdag_in_sorted(c1, und_a) &&
                   _cpdag_in_sorted(c2, und_a)
                    sp3 = true
                    break
                end
            end
            sp3 && continue
            return false
        end
    end
    return true
end

function validation_errors(::CPDAGConstraints, g::CausalGraph)
    errors = validation_errors(PDAGConstraints(), g)
    isempty(errors) || return errors

    B = g.backend isa PDAGBackend ? g.backend : build_backend(PDAG, nodes(g), g.edges)
    n = length(B.nodes)
    n <= 1 && return errors

    comp, c = _cpdag_chain_components(B, n)

    _cpdag_has_intra_arrows(B, n, comp) &&
        push!(errors, "directed edge within a chain component")
    !_cpdag_component_dag_acyclic(B, n, comp, c) &&
        push!(errors, "directed cycle in component DAG")
    !_cpdag_components_chordal(B, n, comp, c) &&
        push!(errors, "undirected component is not chordal")
    !_cpdag_meek_closed(B, n) && push!(errors, "Meek orientation rules would still fire")
    !_cpdag_arrows_protected(B, n) &&
        push!(errors, "not all directed edges are strongly protected")

    return errors
end

graph_class_name(::DAGConstraints) = "DAG"
graph_class_name(::PDAGConstraints) = "PDAG"
graph_class_name(::CPDAGConstraints) = "CPDAG"
graph_class_name(::UGConstraints) = "UG"
graph_class_name(::ADMGConstraints) = "ADMG"
graph_class_name(::AGConstraints) = "AG"
graph_class_name(::UNKNOWNConstraints) = "UNKNOWN"

function validate(g::CausalGraph, c::GraphConstraints)
    errors = validation_errors(c, g)

    isempty(errors) ||
        error("Invalid $(graph_class_name(c)):\n  - " * join(errors, "\n  - "))

    return g
end

validate(g::CausalGraph, ::Type{DAG}) = validate(g, DAGConstraints())

validate(g::CausalGraph, ::Type{PDAG}) = validate(g, PDAGConstraints())

validate(g::CausalGraph, ::Type{CPDAG}) = validate(g, CPDAGConstraints())

validate(g::CausalGraph, ::Type{UG}) = validate(g, UGConstraints())

validate(g::CausalGraph, ::Type{ADMG}) = validate(g, ADMGConstraints())

validate(g::CausalGraph, ::Type{AG}) = validate(g, AGConstraints())

validate(g::CausalGraph, ::Type{UNKNOWN}) = validate(g, UNKNOWNConstraints())
