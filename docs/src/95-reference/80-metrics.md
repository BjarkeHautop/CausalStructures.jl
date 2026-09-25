# [Metrics](@id metrics-reference)

Functions for comparing two causal graphs: edge-based distances, separation-based distances that compare the implied conditional independence structure, and adjustment-based distances that compares implied causal effect estimands.

!!! tip "Comparing causal discovery algorithms"
    When comparing several causal-discovery algorithms against each other using a known ground truth, first convert the true graph to the equivalence class the algorithms actually target ([`dag_to_cpdag`](@ref) for CPDAG output, [`mag_to_pag`](@ref) for PAG output). If a guess is an MPDAG built from background knowledge, apply the same [`apply_background_knowledge`](@ref) to the converted true CPDAG.

    This applies to the edge-based and adjustment-based distances
    below; the separation-based distances are unaffected, since a graph and its equivalence-class imply the same separations.

## Edge-based

```@docs
hd
shd
```

## Separation-based

```@docs
separation_distance
sc_metric
markov_metric
faithfulness_metric
```

## Adjustment-based

```@docs
aid
```
