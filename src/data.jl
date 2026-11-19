"""
    ContractionData

Algorithm-independent description of a graph reduction. `original` is the
input graph, `reduced` is the output graph, and `membership[v]` is the dense
community index of vertex `v`.
"""
struct ContractionData{G<:AbstractGraph,H<:AbstractGraph,L}
    original::G
    reduced::H
    membership::Vector{Int}
    labels::Vector{L}
    representatives::Vector{Int}
    edge_weights::Vector{Float64}
    reduced_edge_weights::Vector{Float64}
end

function Base.getproperty(data::ContractionData, name::Symbol)
    name === :graph && return getfield(data, :original)
    name === :contracted && return getfield(data, :reduced)
    name === :contracted_edge_weights && return getfield(data, :reduced_edge_weights)
    return getfield(data, name)
end

function Base.propertynames(data::ContractionData, private::Bool=false)
    names = (:original, :reduced, :membership, :labels, :representatives,
             :edge_weights, :reduced_edge_weights)
    return private ? names : (names..., :graph, :contracted, :contracted_edge_weights)
end

"""A validated sequence of graph reductions."""
struct ReductionSequence
    stages::Vector{ContractionData}
end

Base.length(sequence::ReductionSequence) = length(sequence.stages)
Base.getindex(sequence::ReductionSequence, index::Integer) = sequence.stages[index]

"""
    graph_from_adjacency(adjacency; directed=false) -> AbstractGraph

Convert a square adjacency matrix into a simple graph. Nonzero entries
represent edges; matrix values are not retained as edge weights.
"""
function graph_from_adjacency(adjacency::AbstractMatrix; directed=false)
    size(adjacency, 1) == size(adjacency, 2) || throw(DimensionMismatch(
        "adjacency matrix must be square"))
    n = size(adjacency, 1)
    graph = directed ? SimpleDiGraph(n) : SimpleGraph(n)
    if !directed
        adjacency == adjacency' || throw(ArgumentError(
            "an undirected adjacency matrix must be symmetric"))
    end
    for source in 1:n
        destinations = directed ? (1:n) : (source:n)
        for destination in destinations
            source == destination && continue
            iszero(adjacency[source, destination]) || add_edge!(graph, source, destination)
        end
    end
    return graph
end

"""
    graph_from_incidence(incidence; directed=false) -> AbstractGraph

Convert a vertex-by-edge incidence matrix into a simple graph. Each column
must contain exactly two nonzero entries. For directed incidence matrices,
the entries must have opposite signs, with negative at the source and
positive at the destination.
"""
function graph_from_incidence(incidence::AbstractMatrix; directed=false)
    n, m = size(incidence)
    graph = directed ? SimpleDiGraph(n) : SimpleGraph(n)
    for edge_index in 1:m
        incident = findall(!iszero, view(incidence, :, edge_index))
        length(incident) == 2 || throw(ArgumentError(
            "incidence column $edge_index must contain exactly two nonzero entries"))
        if directed
            values = incidence[incident, edge_index]
            sum(values .< 0) == 1 && sum(values .> 0) == 1 || throw(ArgumentError(
                "directed incidence column $edge_index must have one negative and one positive entry"))
            source = incident[findfirst(<(0), values)]
            destination = incident[findfirst(>(0), values)]
            add_edge!(graph, source, destination)
        else
            add_edge!(graph, incident[1], incident[2])
        end
    end
    return graph
end

"""
    quotient_graph(graph, membership) -> SimpleGraph

Build the unweighted quotient graph: each distinct membership value becomes a
vertex and two communities are adjacent when any original edge crosses them.
Membership values may be strings, symbols, or non-contiguous integers.
"""
function quotient_graph(graph::AbstractGraph, membership::AbstractVector)
    length(membership) == nv(graph) || throw(DimensionMismatch(
        "membership has $(length(membership)) entries for a $(nv(graph))-vertex graph"))
    labels = unique(membership)
    index = Dict(label => i for (i, label) in enumerate(labels))
    dense = [index[label] for label in membership]
    quotient = SimpleGraph(length(labels))
    for edge in edges(graph)
        a, b = dense[src(edge)], dense[dst(edge)]
        a == b || add_edge!(quotient, a, b)
    end
    return quotient
end

_edge_weights(graph::AbstractGraph, weights) = _edge_weights(ne(graph), weights)

function _edge_weights(edge_count::Integer, weights)
    weights === nothing && return ones(Float64, edge_count)
    length(weights) == edge_count || throw(DimensionMismatch("edge_weights must match the number of edges"))
    return Float64.(weights)
end

# Community labels in first-seen order, and the dense community index of each vertex.
function _dense_membership(membership)
    labels = collect(unique(membership))
    label_index = Dict(label => i for (i, label) in enumerate(labels))
    return labels, [label_index[label] for label in membership]
end

# One representative vertex per community. The default is the first member.
function _representatives(dense, k, representatives)
    n = length(dense)
    reps = representatives === nothing ?
        [findfirst(==(community), dense) for community in 1:k] : Int.(representatives)
    length(reps) == k || throw(DimensionMismatch("one representative is required per community"))
    all(1 .<= reps .<= n) || throw(ArgumentError("representatives must be valid vertex indices"))
    all(dense[reps[i]] == i for i in 1:k) || throw(ArgumentError(
        "representative i must belong to community i (in first-seen label order)"))
    return reps
end

function _contracted_weights(graph, membership, original_weights, contracted, aggregation)
    aggregation in (:sum, :mean, :max, :count) || throw(ArgumentError(
        "weight_aggregation must be :sum, :mean, :max, or :count"))
    values = Dict{Tuple{Int,Int},Vector{Float64}}()
    for (edge_index, edge) in enumerate(edges(graph))
        source, destination = membership[src(edge)], membership[dst(edge)]
        source == destination && continue
        key = source < destination ? (source, destination) : (destination, source)
        push!(get!(values, key, Float64[]), original_weights[edge_index])
    end
    result = Float64[]
    for edge in edges(contracted)
        key = src(edge) < dst(edge) ? (src(edge), dst(edge)) : (dst(edge), src(edge))
        edge_values = get(values, key, Float64[])
        if aggregation === :count
            push!(result, Float64(length(edge_values)))
        elseif isempty(edge_values)
            push!(result, 0.0)
        elseif aggregation === :sum
            push!(result, sum(edge_values))
        elseif aggregation === :mean
            push!(result, sum(edge_values) / length(edge_values))
        else
            push!(result, maximum(edge_values))
        end
    end
    return result
end

"""
    contraction_data(original, membership; reduced=nothing, representatives=nothing)

Validate and normalize data for plotting. If `reduced` is omitted, the quotient
graph is inferred. Representatives default to the first vertex in each
community. The legacy keyword `contracted` remains accepted as an alias for
`reduced`.
"""
function contraction_data(graph::AbstractGraph, membership::AbstractVector;
                          reduced=nothing, contracted=nothing, representatives=nothing,
                          edge_weights=nothing, reduced_weights=nothing,
                          contracted_weights=nothing,
                          weight_aggregation=:sum)
    n = nv(graph)
    length(membership) == n || throw(DimensionMismatch(
        "membership has $(length(membership)) entries for a $n-vertex graph"))
    isempty(membership) && throw(ArgumentError("membership cannot be empty"))

    labels, dense = _dense_membership(membership)
    k = length(labels)
    reduced !== nothing && contracted !== nothing && throw(ArgumentError(
        "specify only one of reduced or contracted"))
    reduced_graph = reduced === nothing ? (contracted === nothing ?
        quotient_graph(graph, membership) : contracted) : reduced
    nv(reduced_graph) == k || throw(DimensionMismatch(
        "reduced graph has $(nv(reduced_graph)) vertices but membership defines $k communities"))

    reps = _representatives(dense, k, representatives)

    original_weights = _edge_weights(graph, edge_weights)
    reduced_weights !== nothing && contracted_weights !== nothing && throw(ArgumentError(
        "specify only one of reduced_weights or contracted_weights"))
    supplied_reduced_weights = reduced_weights === nothing ? contracted_weights : reduced_weights
    final_reduced_weights = reduced === nothing && contracted === nothing ?
        _contracted_weights(graph, dense, original_weights, reduced_graph, weight_aggregation) :
        _edge_weights(reduced_graph, supplied_reduced_weights)
    return ContractionData(graph, reduced_graph, dense, labels, reps,
                           original_weights, final_reduced_weights)
end

contraction_data(data::ContractionData; kwargs...) = data

function contraction_data(matrix::AbstractMatrix, membership::AbstractVector;
                          representation=:adjacency, directed=false,
                          reduced=nothing, contracted=nothing, representatives=nothing,
                          edge_weights=nothing, reduced_weights=nothing,
                          contracted_weights=nothing,
                          weight_aggregation=:sum)
    graph_builder = representation === :adjacency ? graph_from_adjacency :
        representation === :incidence ? graph_from_incidence : nothing
    graph_builder === nothing && throw(ArgumentError(
        "representation must be :adjacency or :incidence"))
    graph = graph_builder(matrix; directed=directed)
    matrix_weights = edge_weights === nothing && representation === :adjacency ?
        [Float64(matrix[src(edge), dst(edge)]) for edge in edges(graph)] : edge_weights
    reduced_input = reduced === nothing ? contracted : reduced
    reduced_input = reduced_input isa AbstractMatrix ?
        graph_builder(reduced_input; directed=directed) : reduced_input
    reduced_weight_input = reduced_weights === nothing ? contracted_weights : reduced_weights
    reduced_matrix_source = reduced_input
    reduced_matrix_weights = reduced_weight_input === nothing && reduced_matrix_source isa AbstractMatrix &&
        representation === :adjacency ?
        [Float64(reduced_matrix_source[src(edge), dst(edge)]) for edge in edges(reduced_input)] : reduced_weight_input
    return contraction_data(graph, membership;
                            reduced=reduced_input, representatives=representatives,
                            edge_weights=matrix_weights,
                            reduced_weights=reduced_matrix_weights,
                            weight_aggregation=weight_aggregation)
end

"""
    reduction_sequence(graph, memberships; contracted=nothing)

Build a validated sequence where each membership vector contracts the graph
produced by the preceding stage. `contracted` may provide one graph or matrix
per transition; omitted graphs are inferred as quotient graphs.
"""
function reduction_sequence(graph::AbstractGraph, memberships::AbstractVector;
                            contracted=nothing, representatives=nothing,
                            edge_weights=nothing, contracted_weights=nothing,
                            weight_aggregation=:sum)
    isempty(memberships) && throw(ArgumentError("at least one membership vector is required"))
    stages = ContractionData[]
    current = graph
    for index in eachindex(memberships)
        contracted_stage = contracted === nothing ? nothing : contracted[index]
        representative_stage = representatives === nothing ? nothing : representatives[index]
        edge_weight_stage = edge_weights === nothing ? nothing : edge_weights[index]
        contracted_weight_stage = contracted_weights === nothing ? nothing : contracted_weights[index]
        stage = contraction_data(current, memberships[index];
                                 contracted=contracted_stage,
                     representatives=representative_stage,
                     edge_weights=edge_weight_stage,
                     contracted_weights=contracted_weight_stage,
                     weight_aggregation=weight_aggregation)
        push!(stages, stage)
        current = stage.reduced
    end
    return ReductionSequence(stages)
end

function reduction_sequence(matrix::AbstractMatrix, memberships::AbstractVector;
                            representation=:adjacency, directed=false,
                            contracted=nothing, representatives=nothing,
                            edge_weights=nothing, contracted_weights=nothing,
                            weight_aggregation=:sum)
    graph_builder = representation === :adjacency ? graph_from_adjacency :
        representation === :incidence ? graph_from_incidence : nothing
    graph_builder === nothing && throw(ArgumentError("representation must be :adjacency or :incidence"))
    graph = graph_builder(matrix; directed=directed)
    initial_weights = edge_weights === nothing && representation === :adjacency ?
        [Float64(matrix[src(edge), dst(edge)]) for edge in edges(graph)] : edge_weights
    contracted_graphs = contracted === nothing ? nothing : [
        stage isa AbstractMatrix ? graph_builder(stage; directed=directed) : stage
        for stage in contracted
    ]
    contracted_weight_stages = contracted_weights === nothing ? nothing : contracted_weights
    stage_weights = initial_weights === nothing ? nothing :
        Any[initial_weights; fill(nothing, max(0, length(memberships) - 1))]
    return reduction_sequence(graph, memberships;
                              contracted=contracted_graphs,
                              representatives=representatives,
                              edge_weights=stage_weights,
                              contracted_weights=contracted_weight_stages,
                              weight_aggregation=weight_aggregation)
end
