# GraphReductionPlots examples and case studies

The repository includes three levels of examples:

| Example | Size | Purpose |
|---|---:|---|
| `basic.jl` | 18 vertices | Minimal API demonstration using a synthetic barbell graph |
| `transmission_case118.jl` | 118 buses | Real transmission-network community contraction |
| `optikron_case100.jl` | 100 nodes | Distribution-network reduction derived from Opti-KRON data |
| `matrix_inputs.jl` | 4 vertices | Weighted adjacency and directed incidence inputs |

Run an example from the repository root after installing CairoMakie:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
Pkg.add("CairoMakie")

include("examples/transmission_case118.jl")
```

The matrix example can be run with:

```julia
include("examples/matrix_inputs.jl")
```

For a user-owned network, start with
[`examples/custom_template.jl`](../examples/custom_template.jl). It is
designed to be copied and edited rather than selected through the example
runner.

Each case writes a layered PNG, MP4, and GIF beside its example script. These
generated files are ignored by Git.

## Data convention

Every fixture separates topology from clustering:

- an edge file contains integer source/destination vertex IDs;
- a membership file maps every vertex to a community label;
- labels may be non-contiguous because `contraction_data` normalizes them.

This format keeps examples independent of MATPOWER, MATLAB, MAT.jl, and the
optimization code that originally produced the reductions.
