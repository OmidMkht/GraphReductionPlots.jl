# Contributing

Issues and pull requests are welcome. Please keep the core independent of any
particular clustering algorithm and avoid committing generated media or private
datasets.

Run the test suite before opening a pull request:

```julia
using Pkg
Pkg.test()
```

For visual changes, also run `examples/basic.jl` with CairoMakie and inspect
both the layered image and at least one exported animation.
