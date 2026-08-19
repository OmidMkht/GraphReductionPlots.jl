# Opti-KRON case100 fixture

Source: `C:\Users\omokhtar\Opti-KRON 2026\ploting\red_map100.mat`.

Conversion rules:

1. Each nonzero upper-triangular entry of `adj_full` becomes one undirected edge.
2. For vertex `i`, the nonzero row in column `i` of `red_map` becomes its
   representative/community label.
3. Diagonal representatives are handled by the same rule.

The CSV form intentionally removes the MAT.jl dependency and contains only the
topology and clustering information required by GraphReductionPlots.jl.
