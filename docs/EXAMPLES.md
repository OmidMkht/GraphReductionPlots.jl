# GraphReductionPlots examples and case studies

The repository includes reusable synthetic, matrix-input, and research-derived
examples.

| Example | Size | Purpose |
|---|---:|---|
| `basic.jl` | 18 vertices | Minimal API demonstration using a synthetic barbell graph |
| `matrix_inputs.jl` | 4 vertices | Weighted adjacency and directed incidence inputs |
| `transmission_case118.jl` | 118 buses | Transmission-network community contraction |
| `optikron_case100.jl` | 100 nodes | Distribution-network reduction derived from Opti-KRON data |
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
julia --project=examples examples/run_examples.jl transmission
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
