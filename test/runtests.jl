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

@testset "node merging without Kron reduction" begin
    # Square 1-2-3-4 with a parallel edge 2-3; merge {1, 2} and {3, 4}.
    sources = [1, 2, 3, 4, 2]
    destinations = [2, 3, 4, 1, 3]
    membership = [:a, :a, :b, :b]
    data = merge_data(sources, destinations, membership)
    @test data isa MergeData
    @test internal_edges(data) == [1, 3]
    @test external_edges(data) == [2, 4, 5]
    # Every external edge stays, including the parallel one: no quotient collapse.
    @test reduced_edges(data) == [(1, 2), (2, 1), (1, 2)]
    @test ne(quotient_graph(path_graph(4), membership)) == 1
    @test data.representatives == [1, 3]
    @test occursin("3 edges", sprint(show, data))

    # The same network from pairs and from an incidence matrix (one column per edge).
    @test reduced_edges(merge_data(collect(zip(sources, destinations)), membership)) ==
          reduced_edges(data)
    incidence = zeros(Int, 4, 5)
    for (edge, (a, b)) in enumerate(zip(sources, destinations))
        incidence[a, edge] = -1
        incidence[b, edge] = 1
    end
    from_incidence = merge_data(incidence, membership; representation=:incidence)
    @test length(external_edges(from_incidence)) == 3

    # A simple graph and an adjacency matrix have no parallel edges; weights are kept.
    adjacency = [0 2 0 5; 2 0 3 0; 0 3 0 4; 5 0 4 0]
    weighted = merge_data(adjacency, membership)
    @test sort(weighted.edge_weights) == [2.0, 3.0, 4.0, 5.0]
    @test length(external_edges(weighted)) == 2
    @test length(external_edges(merge_data(cycle_graph(4), membership))) == 2

    coordinates = ([0.0, 1.0, 1.0, 0.0], [0.0, 0.0, 1.0, 1.0])
    for reduced_coordinates in (nothing, :representatives, ([0.0, 1.0], [0.5, 0.5]))
        @test layeredplot(data; coordinates=coordinates,
                          reduced_coordinates=reduced_coordinates) isa Makie.Figure
    end
    @test layeredplot(weighted; edge_width_by=:weight, internal_edge_color=:gray,
                      palette=[:red, :blue]) isa Makie.Figure
    animation = animate_contraction(data; coordinates=coordinates)
    @test animation isa ContractionAnimation
    for t in (0.5, 1.0)
        animation.time[] = t
    end
    @test animation.figure isa Makie.Figure

    # Parallel edges combine into one equivalent edge per super-node pair.
    equivalent = equivalent_edges(data)
    @test length(equivalent) == 1
    @test equivalent[1].ends == (1, 2)
    @test equivalent[1].edges == [2, 4, 5]
    @test equivalent[1].weight == 3.0
    @test occursin("1 after combining", sprint(show, data))
    weighted_lines = merge_data(sources, destinations, membership; edge_weights=[1, 2, 3, 4, 5])
    @test equivalent_edges(weighted_lines)[1].weight == 2 + 4 + 5
    @test equivalent_edges(weighted_lines; combine=:reciprocal)[1].weight ≈ 1 / (1/2 + 1/4 + 1/5)
    @test equivalent_edges(weighted_lines; combine=:count)[1].weight == 3
    @test equivalent_edges(weighted_lines; combine=maximum)[1].weight == 5
    @test_throws ArgumentError equivalent_edges(data; combine=:median)

    for parallel_edges in (:merge, :keep)
        @test layeredplot(weighted_lines; coordinates=coordinates, parallel_edges=parallel_edges,
                          edge_width_by=:weight) isa Makie.Figure
    end
    for options in ((parallel_timing=:with_nodes,), (parallel_timing=:after_nodes,),
                    (parallel_edges=:keep,), (color_share=0.0, parallel_timing=:after_nodes),
                    (edge_width_by=:weight, parallel_weight=:reciprocal))
        merging = animate_contraction(weighted_lines; coordinates=coordinates, options...)
        for t in (0.0, 0.1, 0.4, 0.7, 0.9, 1.0)
            merging.time[] = t
        end
        @test merging.figure isa Makie.Figure
    end
    # Extra keywords reach Makie's record (here: half-size frames).
    gif = joinpath(mktempdir(), "merging.gif")
    record_animation(animate_contraction(data; coordinates=coordinates), gif;
                     duration=0.2, framerate=10, final_hold=0, px_per_unit=1)
    @test isfile(gif) && filesize(gif) > 0

    @test_throws ArgumentError layeredplot(data; parallel_edges=:fan)
    @test_throws ArgumentError animate_contraction(data; parallel_timing=:before_nodes)
    @test_throws ArgumentError animate_contraction(data; parallel_timing=:after_nodes,
                                                   color_share=0.5, line_share=0.6)

    # Everything merged into one super-node: no edge survives.
    single = merge_data(path_graph(3), [1, 1, 1])
    @test isempty(external_edges(single))
    @test layeredplot(single) isa Makie.Figure
    @test animate_contraction(single).figure isa Makie.Figure

    # Representatives also work for the Kron-style data.
    @test layeredplot(contraction_data(path_graph(4), [1, 1, 2, 2]);
                      coordinates=coordinates,
                      reduced_coordinates=:representatives) isa Makie.Figure

    @test_throws DimensionMismatch merge_data([1, 2], [2], [1, 1, 2])
    @test_throws DimensionMismatch merge_data(path_graph(3), [1, 2])
    @test_throws ArgumentError merge_data([1], [1], [1, 2])
    @test_throws ArgumentError merge_data([1], [5], [1, 2])
    @test_throws ArgumentError merge_data(sources, destinations, membership; representatives=[3, 1])
    @test_throws ArgumentError merge_data(ones(3, 1), [1, 2, 3]; representation=:incidence)
    @test_throws ArgumentError layeredplot(data; internal_edge_color=:white)
    @test_throws ArgumentError layeredplot(data; reduced_coordinates=:centroids)
end

@testset "Kron reduction with radialization" begin
    # A star: center 1 with leaves 2, 3, 4. The leaves are kept, so Kron
    # reduction joins them in a triangle; radialization restores the center.
    sources, destinations = [1, 1, 1], [2, 3, 4]
    membership = [:a, :a, :b, :c]
    plain = kron_data(sources, destinations, membership; representatives=[2, 3, 4])
    @test plain isa KronData
    @test plain.reduced_edges == [(1, 2), (1, 3), (2, 3)]
    @test isempty(plain.restored)
    @test plain.radial_edges == plain.reduced_edges

    radial = kron_data(sources, destinations, membership; representatives=[2, 3, 4], radialize=true)
    @test radial.restored == [1]
    @test radial.radial_edges == [(1, 4), (2, 4), (3, 4)]
    @test occursin("1 vertices restored", sprint(show, radial))
    @test kron_data(sources, destinations, membership; representatives=[2, 3, 4],
                    restored=[1]).radial_edges == radial.radial_edges
    @test kron_data(star_graph(4), membership; representatives=[2, 3, 4],
                    radialize=true).restored == [1]
    # A path stays radial: nothing to restore.
    @test isempty(kron_data(path_graph(5), [1, 1, 2, 2, 3]; representatives=[1, 3, 5],
                            radialize=true).restored)

    coordinates = ([0.0, 1.0, -1.0, 0.0], [0.0, 0.0, 0.0, 1.0])
    for data in (plain, radial)
        animation = animate_contraction(data; coordinates=coordinates, title="")
        @test !animation.figure.content[1].titlevisible[]
        for t in (0.0, 0.1, 0.4, 0.6, 0.8, 1.0)
            animation.time[] = t
        end
        @test animation.figure isa Makie.Figure
    end
    @test animate_contraction(radial; coordinates=coordinates,
                              reduced_coordinates=nothing).figure.content[1].titlevisible[]

    @test_throws ArgumentError kron_data(sources, destinations, membership;
                                         representatives=[2, 3, 4], radialize=true, restored=[1])
    @test_throws ArgumentError kron_data(sources, destinations, membership;
                                         representatives=[2, 3, 4], restored=[2])
    @test_throws ArgumentError animate_contraction(radial; color_share=0.6, radial_share=0.5)
end

@testset "visual export" begin
    graph = path_graph(5)
    figure = layeredplot(graph, [1, 1, 2, 2, 2]; show_connectors=false)
    output = joinpath(mktempdir(), "layered.png")
    save(output, figure)
    @test isfile(output)
    @test filesize(output) > 0
end
