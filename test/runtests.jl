using GraphReductionPlots
using Graphs
using Test
using CairoMakie
using SparseArrays

CairoMakie.activate!()

@testset "quotient graph" begin
    graph = path_graph(6)
    membership = [:left, :left, :middle, :middle, :right, :right]
    quotient = quotient_graph(graph, membership)
    @test nv(quotient) == 3
    @test ne(quotient) == 2
    @test has_edge(quotient, 1, 2)
    @test has_edge(quotient, 2, 3)

    data = contraction_data(graph, membership)
    @test data.membership == [1, 1, 2, 2, 3, 3]
    @test data.labels == [:left, :middle, :right]
    @test data.representatives == [1, 3, 5]
end

@testset "matrix inputs" begin
    adjacency = [0 1 0 0; 1 0 1 0; 0 1 0 1; 0 0 1 0]
    graph = graph_from_adjacency(adjacency)
    @test nv(graph) == 4
    @test ne(graph) == 3

    incidence = [-1 0 0; 1 -1 0; 0 1 -1; 0 0 1]
    incidence_graph = graph_from_incidence(incidence; directed=true)
    @test ne(incidence_graph) == 3
    @test has_edge(incidence_graph, 1, 2)
    @test has_edge(incidence_graph, 3, 4)

    data = contraction_data(adjacency, [1, 1, 2, 2]; contracted=[0 1; 1 0])
    @test nv(data.original) == 4
    @test nv(data.reduced) == 2
    @test data.graph === data.original
    @test data.contracted === data.reduced

    coordinates = ([0.0, 1.0, 2.0, 3.0], [0.0, 0.0, 0.0, 0.0])
    @test layeredplot(adjacency, [1, 1, 2, 2]; coordinates=coordinates) isa Makie.Figure
    @test animate_contraction(adjacency, [1, 1, 2, 2]; coordinates=coordinates).figure isa Makie.Figure

    @test_throws DimensionMismatch graph_from_adjacency(ones(2, 3))
    @test_throws ArgumentError graph_from_incidence(ones(3, 1))
    @test_throws ArgumentError graph_from_adjacency([0 1; 0 0])

    directed = graph_from_adjacency([0 1 0; 0 0 1; 0 0 0]; directed=true)
    @test has_edge(directed, 1, 2)
    @test !has_edge(directed, 2, 1)

    sparse_graph = graph_from_adjacency(sparse(adjacency))
    @test nv(sparse_graph) == 4
    @test ne(sparse_graph) == 3
end

@testset "optional weights and layouts" begin
    adjacency = [0 2 0 0; 2 0 3 0; 0 3 0 4; 0 0 4 0]
    data = contraction_data(adjacency, [1, 1, 2, 2])
    @test data.edge_weights == [2.0, 3.0, 4.0]
    @test data.contracted_edge_weights == [3.0]
    @test layeredplot(data; edge_width_by=:weight, weight_scale=:log,
                      reduced_coordinates=([0.0, 1.0], [0.0, 0.0])) isa Makie.Figure
    @test animate_contraction(data; edge_width_by=:weight, weight_scale=:sqrt,
                              layout=:spring).figure isa Makie.Figure
end

@testset "figure builders" begin
    graph = cycle_graph(6)
    membership = [1, 1, 2, 2, 3, 3]
    coordinates = (cos.(range(0, 2pi; length=7)[1:6]),
                   sin.(range(0, 2pi; length=7)[1:6]))
    figure = layeredplot(graph, membership; coordinates=coordinates)
    animation = animate_contraction(graph, membership; coordinates=coordinates)
    @test figure isa Makie.Figure
    @test animation.figure isa Makie.Figure
    @test animation.time[] == 0.0
end

@testset "layered plot safety" begin
    graph = path_graph(4)
    membership = [1, 1, 2, 2]
    @test layeredplot(graph, membership; layer_gap=:auto, azimuth=:auto, elevation=:auto) isa Makie.Figure
    @test_throws ArgumentError layeredplot(graph, membership; palette=[:white, :red])
    @test_throws ArgumentError layeredplot(graph, membership; edge_color=:white)
    @test_throws ArgumentError layeredplot(graph, membership; plane_color=:white)
end

@testset "automatic connectors" begin
    graph = path_graph(6)
    membership = [1, 1, 2, 2, 3, 3]
    data = contraction_data(graph, membership)
    @test GraphReductionPlots._automatic_connectors(data)

    dense_graph = complete_graph(20)
    dense_membership = repeat(1:2, inner=10)
    dense_data = contraction_data(dense_graph, dense_membership)
    @test !GraphReductionPlots._automatic_connectors(dense_data)
    @test layeredplot(dense_data; show_connectors=false) isa Makie.Figure
    @test layeredplot(dense_data; show_connectors=true) isa Makie.Figure
end

@testset "reduction sequences" begin
    graph = path_graph(8)
    memberships = [[1, 1, 1, 1, 2, 2, 2, 2], [1, 1]]
    sequence = reduction_sequence(graph, memberships)
    @test length(sequence) == 2
    @test nv(sequence[1].original) == 8
    @test nv(sequence[1].reduced) == 2
    @test nv(sequence[2].original) == 2
    @test nv(sequence[2].reduced) == 1
    coordinates = (collect(1.0:8.0), zeros(8))
    figure = layeredplot(sequence, coordinates; show_connectors=false,
                         max_edges=100, max_connectors=100)
    @test figure isa Makie.Figure
    animation = animate_contraction(sequence, coordinates; max_edges=100)
    @test animation isa ReductionSequenceAnimation
    @test animation.time[] == 0.0
end

@testset "validation" begin
    @test_throws DimensionMismatch contraction_data(path_graph(3), [1, 2])
    @test_throws DimensionMismatch contraction_data(path_graph(3), [1, 2, 3]; contracted=path_graph(2))
    @test_throws ArgumentError contraction_data(path_graph(3), [1, 1, 2]; representatives=[2, 1])
end

@testset "visual export" begin
    graph = path_graph(5)
    figure = layeredplot(graph, [1, 1, 2, 2, 2]; show_connectors=false)
    output = joinpath(mktempdir(), "layered.png")
    save(output, figure)
    @test isfile(output)
    @test filesize(output) > 0
end
