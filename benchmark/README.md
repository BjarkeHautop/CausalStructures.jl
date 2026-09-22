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

`n` is the number of nodes in the DAG, for adjustment and backdoor. Frontdoor cost tracks the candidate-pool size rather than `n` directly, so its setup is instead a mediator chain `X --> M --> Y` plus `k` isolated nodes each freely includable in or excludable from `Z`, giving exactly `2^k` valid sets.

Numbers below were measured with Julia 1.13.0 on an AMD Ryzen 7 8845HS (single thread, Linux x86_64).

**Enumerate all valid adjustment sets**
DAGs of increasing size, same `(x,y)` pair:

| n | valid sets | CS `all_adjustment_sets` | CI `list_covariate_adjustment` | speedup |
|---|---|---|---|---|
| 15 | 8 | 5.5 us | 443.2 us | ~81x |
| 18 | 25,500 | 25.22 ms | 423.51 ms | ~17x |
| 21 | 524,288 | 255.17 ms | 14.18 s | ~56x |

**Enumerate all valid backdoor sets**
A different family of DAG/pairs, same size sweep:

| n | valid sets | CS `all_backdoor_sets` | CI `list_backdoor_adjustment` | speedup |
|---|---|---|---|---|
| 15 | 5,376 | 2.69 ms | 84.16 ms | ~31x |
| 18 | 32,768 | 7.15 ms | 750.67 ms | ~105x |
| 21 | 512,128 | 182.97 ms | 14.12 s | ~77x |

**Enumerate all valid frontdoor sets**
Single mediator chain plus increasing isolated-node count:

| k | valid sets | CS `all_frontdoor_sets` | CI `list_frontdoor_adjustment` | speedup |
|---|---|---|---|---|
| 13 | 8,192 | 4.69 ms | 136.88 ms | ~29x |
| 16 | 65,536 | 41.17 ms | 557.83 ms | ~14x |
| 19 | 524,288 | 397.19 ms | 6.72 s | ~17x |
