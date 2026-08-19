# GraphReductionPlots.jl

Create layered figures and MP4/GIF animations of graph clustering,
contraction, coarsening, and community detection results.

The package is deliberately algorithm-independent. Bring any `Graphs.jl`
graph and one community label per vertex; labels may be integers, strings,
symbols, or the output of your preferred clustering method.

## Features

- infer a quotient graph from arbitrary community assignments;
- render original and contracted networks as a layered 3D figure;
- animate vertices collapsing into community centroids;
- export MP4 and GIF through Makie;
- accept a custom contracted graph for reductions that are not simple
  quotient graphs;
- use custom coordinates, colors, labels, and display settings.

## Installation

The package is not registered in Julia's General registry yet, so
`Pkg.add("GraphReductionPlots")` will not work by name.

To use this checkout directly from the repository root:

```powershell
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=. examples/custom_template.jl
```

To make the local checkout available in your default Julia environment, run:

```powershell
julia -e 'using Pkg; Pkg.develop(path=raw"C:\Users\omokhtar\graph_clustering_plots"); Pkg.add("CairoMakie")'
```

Then it can be used from any Julia session with:

```julia
using CairoMakie
using GraphReductionPlots
```

Once the repository is published at its final GitHub URL, install it with:

```julia
using Pkg
Pkg.add(url="https://github.com/OmidMkht/GraphReductionPlots.jl.git")
Pkg.add("CairoMakie") # one plotting backend
```

When developing from a local clone:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
Pkg.test()
```

## Quick start

```julia
using CairoMakie
using GraphReductionPlots
using Graphs

CairoMakie.activate!()

graph = path_graph(12)
communities = repeat(1:3, inner=4)

# Static layered visualization
fig = layeredplot(graph, communities)
save("contraction.pdf", fig)

# One animation can be exported more than once
animation = animate_contraction(graph, communities)
record_animation(animation, "contraction.mp4")
record_animation(animation, "contraction.gif"; duration=4, framerate=20)
```

Layer connectors are enabled automatically for small, lightly reduced graphs
and suppressed when they would clutter a dense or heavily reduced network.
Override this with `show_connectors=true` or `show_connectors=false`.

Adjacency and incidence matrices can be passed directly. Matrix values are
treated as topology indicators; nonzero entries represent edges:

```julia
adjacency = [0 1 0; 1 0 1; 0 1 0]
membership = [:left, :middle, :right]
fig = layeredplot(adjacency, membership)

incidence = [-1 0; 1 -1; 0 1] # vertices by edges
animation = animate_contraction(incidence, [:left, :middle, :right];
                                data_kwargs=(representation=:incidence,
                                             directed=true))
```

Use `graph_from_adjacency` or `graph_from_incidence` when the normalized graph
is needed separately. Incidence columns must contain exactly two nonzero
entries. Directed incidence uses a negative source entry and positive
destination entry.

## Multiple reductions

Build a sequence when a network is reduced more than once:

```julia
sequence = reduction_sequence(
  graph,
  [
    [:a, :a, :b, :b, :c, :c],
    [1, 1, 2],
  ],
)

figure = layeredplot(sequence; show_connectors=:auto, max_edges=4000)
animation = animate_contraction(sequence)
record_animation(animation, "reduction_sequence.gif"; duration=8)
```

The first coordinate set is propagated through each reduction by taking
community centroids. Supply `coordinates=(x, y)` to control the initial
layout. Layer spacing and camera angles default to `:auto`; use numeric
`layer_gap`, `azimuth`, or `elevation` values to override them.

For large networks, `max_edges` and `max_connectors` limit rendering work while
preserving the full graph data. Visual scale can be adjusted with
`node_size`, `cluster_node_size`, `edge_width`, and `connector_width`.

## Optional weights and layouts

Weighted adjacency values are preserved when supplied:

```julia
data = contraction_data(
  adjacency,
  membership;
  weight_aggregation=:sum,
)

layeredplot(data; edge_width_by=:weight, weight_scale=:sqrt)
animate_contraction(data; edge_width_by=:weight, weight_scale=:log)
```

Supported aggregation modes for inferred reduced edges are `:sum`, `:mean`,
`:max`, and `:count`. Unweighted inputs continue to use unit weights.

Coordinates may be supplied independently:

```julia
layeredplot(
  data;
  coordinates=(full_x, full_y),
  reduced_coordinates=(reduced_x, reduced_y),
)
```

When coordinates are omitted, the full graph uses `layout=:stress` by default.
Other built-in choices are `:spring`, `:spectral`, and `:sfdp`; a custom
function taking the graph is also accepted.

MP4 export requires `ffmpeg`; Makie normally obtains it through Julia's
`FFMPEG_jll` dependency.

`CairoMakie` is recommended for headless PNG, PDF, GIF, and test rendering.
`GLMakie` is useful for interactive exploration and requires a working desktop
OpenGL environment:

```julia
using Pkg
Pkg.add("GLMakie")
using GLMakie
GLMakie.activate!()
```

Install `ffmpeg` separately when MP4 export is unavailable through the Julia
artifact. GIF export does not require a separate system installation.

## Using community-detection output

Any vector whose length equals the number of vertices works:

```julia
membership = community_detection_algorithm(graph)
layeredplot(graph, membership; labels=("Network", "Communities"))
```

Community IDs do not need to be contiguous. Their first-seen order determines
the vertices of the contracted graph. Inspect the normalized result when that
mapping matters:

```julia
data = contraction_data(graph, membership)
data.labels       # original labels, in contracted-vertex order
data.membership   # dense IDs in 1:nv(data.contracted)
data.original     # input graph
data.reduced      # inferred quotient graph
```

## Custom contractions

For Kron reduction, multilevel coarsening, or a method whose output topology is
not the ordinary quotient graph, supply it explicitly:

```julia
data = contraction_data(
    graph,
    membership;
    reduced=my_reduced_graph,
    representatives=my_representative_vertices,
)

fig = layeredplot(data; coordinates=(x, y))
animation = animate_contraction(data; coordinates=(x, y))
```

The custom reduced graph must have one vertex per unique community. A representative
must belong to its corresponding community; representatives determine anchors
for integrations and future plot styles, while the current visuals use
community centroids.

## API

- `quotient_graph(graph, membership)` builds a simple unweighted quotient.
- `contraction_data(...)` validates and normalizes a contraction.
- `layeredplot(...)` returns a Makie `Figure`.
- `animate_contraction(...)` returns a reusable `ContractionAnimation`.
- `record_animation(animation, filename; ...)` writes MP4, GIF, or another
  format supported by the active Makie backend.

See [`examples/basic.jl`](examples/basic.jl) for a complete runnable example.

## Use your own data

For a starting point, copy
[`examples/custom_template.jl`](examples/custom_template.jl) and edit only
its input section:

```powershell
Copy-Item examples/custom_template.jl my_network_plot.jl
julia --project=. my_network_plot.jl
```

The template shows where to provide:

- an original `Graphs.jl` graph or adjacency/incidence matrix;
- one membership label per original vertex;
- an optional reduced graph or matrix;
- optional full and reduced coordinates.

Animation settings are also exposed near the top of the template:

```julia
animation_duration = 5.0 # seconds
animation_framerate = 20
animation_final_hold = 0.5 # seconds
```

Increase `animation_duration` for a slower reduction or lower
`animation_framerate` for a smaller output file.

The runner is only a menu for the repository's fixed case studies. It is not
intended to receive arbitrary user data directly.

## Real-world examples

Small, solver-independent fixtures extracted from the original research
projects are included alongside their provenance and interpretation:

- [Examples overview](docs/EXAMPLES.md)

The fixtures contain only graph topology and vertex-to-community mappings, so
they run without MATPOWER, MATLAB, MAT.jl, or an optimization solver.

## Repository layout

```text
src/                 Package implementation
examples/            Runnable examples
test/                 Unit tests
legacy research files (ignored by Git)
```

The original research scripts and generated artifacts are not required to run
the public examples. Generated media files are ignored so they are not
accidentally published.

## Public API conventions

The package uses `original`, `reduced`, and `membership` as the conceptual
names for a reduction. `layeredplot` and `animate_contraction` accept the same
input forms and the same coordinate/layout conventions. White is reserved for
the background: node, cluster, edge, plane, and palette colors cannot be white.

Connectors default to `show_connectors=:auto`; dense or heavily reduced graphs
hide them automatically. Set `show_connectors=true` or `false` to override
that choice. Automatic full-graph layouts are `:stress`, `:spring`,
`:spectral`, and `:sfdp`; reduced coordinates default to full-graph community
centroids.

## License

MIT. See [LICENSE](LICENSE).
