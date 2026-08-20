using CairoMakie
using GraphReductionPlots
using Graphs

CairoMakie.activate!()

graph = SimpleGraph(18)
for left in 1:7
	for right in (left + 1):8
		add_edge!(graph, left, right)
	end
end
for left in 11:17
	for right in (left + 1):18
		add_edge!(graph, left, right)
	end
end
add_edge!(graph, 8, 9)
add_edge!(graph, 9, 10)
add_edge!(graph, 10, 11)
membership = [fill(:left, 8); fill(:bridge, 2); fill(:right, 8)]

figure = layeredplot(graph, membership)
save(joinpath(@__DIR__, "layered_contraction.png"), figure)

animation = animate_contraction(graph, membership; title="Community contraction")
record_animation(animation, joinpath(@__DIR__, "community_contraction.mp4"))
record_animation(animation, joinpath(@__DIR__, "community_contraction.gif"); duration=4, framerate=20)
