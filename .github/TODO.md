# TODO

## Algs

- Hedge witness on non-identifiability (Shpitser & Pearl 2008, Fig. 4 line 5);
  `id` just returns `nothing`. Separate `hedge(cg, x, y)`, not a wider `id`
  return type. `(G, G ∩ S)` at the failure point still needs trimming to
  C-forests.

- Generalized Backdoor Criterion (GBC) (Maathuis and Colombo, 2015)

- `possible_parent_sets(cpdag, x)`; the graph half of IDA (Maathuis et al.,
  2009). Not `all_adjustment_sets`: one set per DAG in the class, duplicates
  kept. Check local vs global multiplicities against the paper.

## Causal Graphs

- RFCI-PAG
