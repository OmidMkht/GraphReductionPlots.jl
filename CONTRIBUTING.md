# Contributing

Issues and pull requests are welcome. Keep the core independent of any
particular clustering algorithm, and do not commit generated media, local
manifests, private datasets, or solver logs.

## Run the package tests

From the repository root:

```powershell
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

## Check visual changes

Set up the dedicated example environment once:

```powershell
julia --project=examples examples/setup.jl
```

Then run either one example or the full suite:

```powershell
julia --project=examples examples/run_examples.jl basic
julia --project=examples examples/run_examples.jl all
```

Inspect the generated PNG, GIF, and MP4 files before opening a pull request.
Generated outputs are ignored by Git.
