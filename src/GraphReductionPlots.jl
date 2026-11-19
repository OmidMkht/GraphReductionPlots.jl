module GraphReductionPlots

using Colors
using Graphs
using Makie
using NetworkLayout

export ContractionData, ReductionSequence, contraction_data, quotient_graph
export reduction_sequence
export graph_from_adjacency, graph_from_incidence
export layeredplot, ContractionAnimation, ReductionSequenceAnimation
export animate_contraction, record_animation
export MergeData, merge_data, internal_edges, external_edges, reduced_edges, equivalent_edges
export KronData, kron_data

include("data.jl")
include("plotting.jl")
include("animation.jl")
include("merge.jl")
include("kron.jl")

end