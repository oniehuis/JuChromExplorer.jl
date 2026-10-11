# Development

## Repository setup

Clone the repository and instantiate its environment:

```sh
git clone https://github.com/oniehuis/JuChromExplorer.jl.git
cd JuChromExplorer.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

The `[sources]` entry in `Project.toml` resolves JuChrom from a tested GitHub
commit, also used by the test and documentation environments. No sibling JuChrom checkout is required. Use Julia 1.12 or later and a
working graphical display with an OpenGL context for local interactive work.

## Examples

From the repository directory:

```sh
julia --project=. examples/tic.jl
```

This loads two measurements bundled with JuChrom. To start an empty window with
the sample ChemStation importer instead:

```sh
julia --project=. examples/drag_and_drop.jl
```

The reader and preprocessing callback is in `examples/importer.jl`.
See [Importing files](man/importers.md) before adapting it to other data.

## Tests

Run the tests from the repository directory:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

The tests exercise GLMakie with hidden windows, so they still require a graphical
display and OpenGL context. GitHub Actions supplies Xvfb and software OpenGL on
Linux.

## Documentation

Prepare the separate documentation environment and build the site:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Run both commands from the repository directory. `Pkg.develop(path=pwd())` makes
the documentation use this local JuChromExplorer checkout. JuChrom itself is
resolved from GitHub through `docs/Project.toml`.

The generated site is written to `docs/build/`. Documenter checks that all exported
docstrings are included in the [API reference](api.md), which also populates the
[Register](register.md). Keep the page list in `docs/make.jl` in sync when adding
manual pages. Local builds do not deploy the site; deployment runs in GitHub Actions.

## Keeping JuChrom and JuChromExplorer compatible

Normal explorer CI and documentation use the JuChrom commit in `[sources]`.
The current tested revision is `41f86fab54e73b9db44a8475930729062bc9854f`.
CI checks that the root, test, and documentation projects all specify the same
full commit SHA and repository URL.

JuChrom also has a downstream workflow: every JuChrom pull request and push to
`main` runs the explorer's tests against that JuChrom checkout on Julia 1.12 and
1.13, overriding the explorer's normal dependency pin in a temporary environment.
Its **JuChromExplorer compatibility** check should be required before merging into
JuChrom's `main` branch. The setup instructions live in
[JuChrom's downstream guide](https://github.com/oniehuis/JuChrom.jl/blob/main/.github/DOWNSTREAM.md).

To adopt a newer JuChrom revision:

1. Choose a JuChrom commit whose downstream tests passed.
2. Replace its `rev` in `Project.toml`, `test/Project.toml`, and `docs/Project.toml`
   with the same full commit SHA. Update the installation commands in `README.md`
   and `docs/src/index.md`, and the revision stated on this page.
3. Refresh existing local manifests and verify the pins from the repository root:

   ```sh
   julia --project=. -e 'using Pkg; for env in (".", "test", "docs"); Pkg.activate(env); Pkg.resolve(); Pkg.instantiate(); end'
   julia --project=. .github/scripts/check_juchrom_pin.jl
   ```

4. Run the explorer's tests and build the documentation using the commands above.
5. Commit the pin updates together and require successful CI before tagging an
   explorer release. If the JuChrom package version changed, update the JuChrom
   `[compat]` entries to cover the versions actually supported.

The two packages have independent version numbers. A tested source revision
identifies the exact JuChrom implementation used by an explorer release;
`[compat]` specifies compatible package versions. Local manifests are ignored and
are not a substitute for the committed source pins.
