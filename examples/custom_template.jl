# Run this file from the repository root with:
#   julia --project=. examples/custom_template.jl
# For a global install, see the Installation section in README.md.
using CairoMakie
using GraphReductionPlots
using Graphs

CairoMakie.activate!()

# Replace this input section with your own graph, matrix, or file loader.
# `original` may be a Graphs.jl graph or an adjacency/incidence matrix.
original = CliqueGraph(5,3)
membership = [1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3]

# Leave this as `nothing` to infer the quotient graph, or provide your own
# reduced graph/matrix with one vertex per unique membership label.
reduced = nothing

# Optional: provide one (x, y) coordinate per original vertex.
coordinates = nothing

# Optional: provide coordinates for reduced vertices. Otherwise their
# positions are computed as full-graph community centroids.
reduced_coordinates = nothing

# Animation controls. Duration is in seconds; framerate controls smoothness
# and output size. `final_hold` keeps the last frame visible briefly.
animation_duration = 5.0
animation_framerate = 20
animation_final_hold = 0.5

data = contraction_data(
    original,
    membership;
    reduced=reduced,
)

figure = layeredplot(
    data;
    coordinates=coordinates,
    reduced_coordinates=reduced_coordinates,
    show_connectors=:auto,
    labels=("Original network", "Reduced network"),
)
save(joinpath(@__DIR__, "custom_layered.png"), figure)

animation = animate_contraction(
    data;
    coordinates=coordinates,
    reduced_coordinates=reduced_coordinates,
    title="Network reduction",
)
record_animation(animation, joinpath(@__DIR__, "custom_reduction.gif");
                 duration=animation_duration,
                 framerate=animation_framerate,
                 final_hold=animation_final_hold)

println("Wrote custom_layered.png and custom_reduction.gif ($(animation_duration)s)")
