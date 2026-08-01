# TODO

## Algs

- Generalized adjustment criterion for PAG — is_valid_adjustment, all_adjustment_sets
  (Perković, Textor, Kalisch & Maathuis 2018). PAG currently has no identification
  support at all (no adjustment, backdoor, or m_separated methods); possible_ancestors/
  possible_descendants already provide the building blocks. Extend minimal_separator to
  PAG too.

- ID algorithm (Shpitser & Pearl 2006). Requires c-component factorization first.

- c-component factorization (Tian & Pearl 2002) — decomposes the joint distribution into c-components based on bidirected-connected components.

- IDC algorithm (Shpitser & Pearl 2008) — extends ID to conditional causal effects P(Y | do(X), Z).

## Causal Graphs

- RFCI-PAG

- generate_graph(...; class = PAG) — pipe generate_graph(...; class = MAG) through mag_to_pag.
