# Comparison against CausalInference.jl

Some benchmarks against [CausalInference.jl](https://github.com/mschauer/CausalInference.jl),
which also implements some causal identifications algorithms (DAGs only); the generalized adjustment criterion
(GAC), the backdoor criterion, and the frontdoor criterion.

The rest of the many algorithms in this package have no equivalent in CausalInference.jl.

Run with:

```sh
julia --project=benchmark benchmark/benchmark.jl
```

## Performance (`benchmark.jl`)

Only the expensive, combinatorial `all_*_sets` enumeration operations are benchmarked here. Below we use the shorthands CS for CausalStructures (this package), and CI for CausalInference.

Numbers below were measured with Julia 1.13.0 on an AMD Ryzen 7 8845HS (single thread, Linux x86_64).

**Enumerate all valid adjustment sets**
Done on a 21-node DAG `(x,y)` pair with 524,288 valid sets:

| | CS `all_adjustment_sets` | CI `list_covariate_adjustment` |
|---|---|---|
| n=21 | 0.27 s / 1,573,118 allocs | 14.99 s / 226,638,109 allocs |

CausalStructures is ~55x faster and allocates ~144x less.

**Enumerate all valid backdoor sets**
A different 21-node DAG/pair with 512,128 valid sets:

| | CS `all_backdoor_sets` | CI `list_backdoor_adjustment` |
|---|---|---|
| n=21 | 0.29 s / 1,536,462 allocs | 15.23 s / 292,156,997 allocs |

CausalStructures is ~52x faster and allocates ~190x less.

**Enumerate all valid frontdoor sets**. Unlike adjustment/backdoor, frontdoor cost
tracks the size of the candidate pool rather than `n` directly, and
satisfying the frontdoor criterion is a much rarer structural condition, so instead the setup is a single mediator `X --> M --> Y` plus 19 isolated
nodes with no edges to `X`, `Y`, or `M`, each freely includable in or
excludable from `Z`, giving exactly 2^19 = 524,288 valid sets:

| | CS `all_frontdoor_sets` | CI `list_frontdoor_adjustment` |
|---|---|---|
| k=19 | 0.51 s / 2,451,703 allocs | 7.34 s / 164,627,496 allocs |

CausalStructures is ~14x faster here and allocates ~67x less.
