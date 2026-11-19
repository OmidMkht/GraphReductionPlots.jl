# Opti-KRON case100 fixture

Source: the `red_map100.mat` result from the Opti-KRON research project.
The public fixture was extracted in August 2026.

Conversion rules:

1. Each nonzero upper-triangular entry of `adj_full` becomes one undirected edge.
2. The stored cluster assignment for vertex `i` becomes its community label.
3. Community labels are retained as produced and normalized by
   `GraphReductionPlots.contraction_data` when loaded.

The CSV representation removes the MAT.jl dependency and contains only the
100-node topology and 11-community assignment needed by the visualization
example. The included PDF is a reference output from the source workflow.

`supernodes.csv` (added November 2026) lists the kept buses of the same
`red_map100` result: `reduction` marks the 11 super-nodes of the Kron
reduction (`SN_reduced`), and `radialization` marks the 5 buses that
radialization restores (`SN_radial` minus `SN_reduced`). With these super-nodes,
`kron_data(...; radialize=true)` reproduces the source run's 25 Kron edges, its
restored buses, and its 15 radial edges.
