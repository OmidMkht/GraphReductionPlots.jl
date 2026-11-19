# GraphReductionPlots examples and case studies

The repository includes reusable synthetic, matrix-input, and research-derived
examples.

| Example | Size | Purpose |
|---|---:|---|
| `basic.jl` | 18 vertices | Minimal API demonstration using a synthetic barbell graph |
| `matrix_inputs.jl` | 4 vertices | Weighted adjacency and directed incidence inputs |
| `merge_basic.jl` | 15 vertices | Node merging without Kron reduction: internal edges disappear, parallel edges join into equivalent edges (both animation timings) |
| `transmission_case118.jl` | 118 buses | Transmission-network bus merging (no Kron reduction): 186 lines, 71 kept, 54 equivalent lines |
| `transmission_case118_greedy.jl` | 118 buses | Strong bus merging (10 super-nodes, 15 equivalent lines); 30-second MP4 and GIF for both ways of joining parallel lines |
| `optikron_case100.jl` | 100 nodes | Distribution-network reduction derived from Opti-KRON data |
| `optikron_case100_radial.jl` | 100 nodes | Kron reduction (11 super-nodes, 25 Kron lines) and radialization (5 buses restored, 15 radial lines); 30-second MP4 and GIF without a header |
| `custom_template.jl` | user-defined | Starting point for a new dataset |

## Set up the example environment

From the repository root, run:

```powershell
julia --project=examples examples/setup.jl
```

This develops the local GraphReductionPlots package into the example
environment and installs CairoMakie and Graphs. The generated
`examples/Manifest.toml` is intentionally ignored.

## Run examples

Use the unified runner:

```powershell
julia --project=examples examples/run_examples.jl basic
julia --project=examples examples/run_examples.jl matrices
julia --project=examples examples/run_examples.jl merge
julia --project=examples examples/run_examples.jl transmission
julia --project=examples examples/run_examples.jl reduced118
julia --project=examples examples/run_examples.jl kronradial
julia --project=examples examples/run_examples.jl optikron
julia --project=examples examples/run_examples.jl all
```

For a user-owned network, copy
[`examples/custom_template.jl`](../examples/custom_template.jl) and replace
its input section.

The examples write layered PNG files and, where applicable, MP4 and GIF
animations. Generated outputs are ignored by Git.

## Data convention

Each research fixture separates topology from clustering:

- an edge file contains integer source and destination vertex IDs;
- a membership file maps every vertex to a community label;
- labels may be non-contiguous because `contraction_data` normalizes them.

This keeps the public examples independent of MATPOWER, MATLAB, MAT.jl,
optimization solvers, and the research code that originally produced the
reductions.
