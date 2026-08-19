using CairoMakie
using GraphReductionPlots

CairoMakie.activate!()

adjacency = [0 2 0 0; 2 0 3 0; 0 3 0 4; 0 0 4 0]
membership = [:left, :left, :right, :right]
data = contraction_data(adjacency, membership)

figure = layeredplot(data; edge_width_by=:weight, weight_scale=:sqrt,
                     show_connectors=false,
                     labels=("Weighted adjacency", "Reduced graph"))
save(joinpath(@__DIR__, "matrix_adjacency_layered.png"), figure)

incidence = [-1 0 0; 1 -1 0; 0 1 -1; 0 0 1]
incidence_membership = [:left, :left, :right, :right]
incidence_figure = layeredplot(
    incidence,
    incidence_membership;
    data_kwargs=(representation=:incidence, directed=true),
    show_connectors=false,
    labels=("Directed incidence", "Reduced graph"),
)
save(joinpath(@__DIR__, "matrix_incidence_layered.png"), incidence_figure)
