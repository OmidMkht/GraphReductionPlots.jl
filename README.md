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
  quotient graphs, such as Kron reduction;
- show node merging without Kron reduction: edges inside a community
  disappear, every other edge stays unchanged, parallel edges included;
- use custom coordinates, colors, labels, and display settings.

## Installation

The package is not registered in Julia's General registry yet, so
`Pkg.add("GraphReductionPlots")` will not work by name.

Install the package directly from GitHub and add a Makie rendering backend:

```julia
using Pkg
Pkg.add(url="https://github.com/OmidMkht/GraphReductionPlots.jl.git")
Pkg.add("CairoMakie")
```

Then load the package with:

```julia
using CairoMakie
using GraphReductionPlots
```

For local development, clone the repository and run the package tests:

```powershell
git clone https://github.com/OmidMkht/GraphReductionPlots.jl.git
Set-Location GraphReductionPlots.jl
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

The examples use their own environment. Set it up once, then use the unified
runner:

```powershell
julia --project=examples examples/setup.jl
julia --project=examples examples/run_examples.jl basic
julia --project=examples examples/run_examples.jl merge
julia --project=examples examples/run_examples.jl kronradial
julia --project=examples examples/run_examples.jl transmission
julia --project=examples examples/run_examples.jl optikron
julia --project=examples examples/run_examples.jl matrices
julia --project=examples examples/run_examples.jl all
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
must belong to its corresponding community. Reduced vertices are drawn at
community centroids by default; pass `reduced_coordinates=:representatives`
to draw each one at its representative vertex instead.

## Node merging (no Kron reduction)

Some reductions merge vertices and keep the remaining edges as they are. An
edge with both ends in one community disappears. Every other edge stays and
joins the two super-nodes. No new edge is created. This is the reduction used
in transmission-network studies that merge buses into clusters.

A quotient graph is not enough here, because it collapses several edges
between two communities into one. `merge_data` keeps every edge:

```julia
# Edge e joins sources[e] and destinations[e]. Edges 2-3 are parallel.
sources      = [1, 2, 3, 4, 2]
destinations = [2, 3, 4, 1, 3]
membership   = [:a, :a, :b, :b]

data = merge_data(sources, destinations, membership)
internal_edges(data)   # [1, 3]           edges that disappear
external_edges(data)   # [2, 4, 5]        edges that stay
reduced_edges(data)    # [(1, 2), (2, 1), (1, 2)]  three edges between a and b

fig = layeredplot(data)
animation = animate_contraction(data)
record_animation(animation, "merging.gif")
```

`merge_data` also accepts a `Graphs.jl` graph, a vector of `(source,
destination)` pairs, or a matrix (`representation=:adjacency` or
`:incidence`). Simple graphs and adjacency matrices cannot hold parallel
edges; use edge vectors, pairs, or an incidence matrix to keep them.

### Equivalent edges

After merging, several edges can join the same two super-nodes. They can be
replaced by one equivalent edge:

```julia
equivalent_edges(data)
# [(ends = (1, 2), edges = [2, 4, 5], weight = 3.0)]
```

`combine` sets how the weights of parallel edges combine: `:sum` (default,
for admittance, susceptance, or rating), `:reciprocal` (`1 / sum(1 ./ w)`, for
reactance or impedance), `:max`, `:mean`, `:count`, or a function.

### Plots and animations

In the layered plot, the edges that disappear are drawn in their community's
color on the top layer. The bottom layer shows the equivalent edges: an edge
that replaces parallel edges is darker and thicker (`equivalent_edge_color`);
a single edge stays gray. Use `parallel_edges=:keep` to draw every edge
instead, with parallel edges fanned out as arcs.

The animation has three steps:

1. the network starts uncolored, then the clusters take their colors
   (`color_share` of the time; `color_share=0` skips this step);
2. the vertices move to their super-node; internal edges shrink and fade,
   external edges stay and follow their ends;
3. parallel edges join into their equivalent edge.

`parallel_timing` sets when step 3 happens:

```julia
# Option 1 (default): parallel edges join while the nodes merge.
animate_contraction(data; parallel_timing=:with_nodes)

# Option 2: nodes merge first, then the parallel edges join
# (during the last `line_share` of the animation).
animate_contraction(data; parallel_timing=:after_nodes, line_share=0.3)
```

Other options specific to node merging: `internal_edge_color` (`:community`
or one color), `internal_edge_width`, `uncolored_color`, `parallel_weight`
(the `combine` rule), `parallel_spread`, and `arc_samples`.
`edge_width_by=:weight` uses one width scale for original and equivalent
edges, so their widths can be compared.

## Kron reduction with radialization

`kron_data` describes a Kron-based reduction: each community keeps one
vertex (its representative) and every other vertex is eliminated. All original
edges are replaced by Kron edges: two kept vertices are joined when a path links
them through eliminated vertices only. On a radial network this can create
cycles. With `radialize=true`, a minimal set of eliminated vertices is brought
back so the reduced network is radial again (as in Structure-preserving
Opti-KRON); or pass them yourself with `restored`.

```julia
data = kron_data(sources, destinations, membership;
                 representatives=kept_vertices, radialize=true)
data.reduced_edges   # Kron network between the super-nodes
data.restored        # vertices brought back by radialization
data.radial_edges    # radial network on super-nodes, then restored vertices

animation = animate_contraction(data; title="")   # "" hides the title
record_animation(animation, "kron.mp4"; duration=28, final_hold=2)
```

The animation starts uncolored, colors the clusters, moves the vertices into
their super-node while the original edges fade and the Kron edges appear, and
then radializes: the restored vertices move back out, Kron edges that are not
radial fade out, and the radial edges fade in. Super-nodes sit on their
representative vertex. `radial_share` sets the time of the last step.

## API

- `quotient_graph(graph, membership)` builds a simple unweighted quotient.
- `contraction_data(...)` validates and normalizes a contraction.
- `merge_data(...)` describes node merging without Kron reduction;
  `internal_edges`, `external_edges`, `reduced_edges`, and
  `equivalent_edges` inspect it.
- `kron_data(...)` describes a Kron-based reduction, with optional
  radialization.
- `layeredplot(...)` returns a Makie `Figure`.
- `animate_contraction(...)` returns a reusable `ContractionAnimation`.
- `record_animation(animation, filename; ...)` writes MP4, GIF, or another
  format supported by the active Makie backend.

See [`docs/EXAMPLES.md`](docs/EXAMPLES.md) for setup instructions and the complete example catalog.

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
centroids, or `:representatives` for the representative vertices.

## License

MIT. See [LICENSE](LICENSE).
