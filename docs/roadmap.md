# Development roadmap

This document tracks implementation against the current checkout. A milestone is complete only after `make check` passes and the diff is reviewed.

| Area | Current status | Completion criteria |
| --- | --- | --- |
| CLI and native packs | Implemented | Expand malformed state and module argument tests |
| Palette and templates | Implemented | Add real CWAL version compatibility test on a disposable host |
| Application pipeline | Implemented with limits | Verify live reload semantics on a disposable desktop; preserve ACLs in rollback |
| Wallpaper workflow | Implemented with limits | Support more than the first monitor and alternative backends |
| Import analysis | Bounded, commit-pinned retrieval, local scanning, and per-file theme candidates implemented | Verify live GitHub API behavior on a disposable host |
| Import conversion | Exact candidate selection, preview, license evidence, provenance, and exclusive staged publication implemented | Add more source formats only with reliable parsers and fixtures |
| Checks and CI | Implemented | Run in CI and inspect artifact logs |
| Packaging | Implemented | Verify installation on another disposable Linux host |
| Documentation | Implemented | Review against a live integration pass |

Qt is deferred until a concrete supported frontend is identified. A live GitHub request and live desktop operation have not been tested in this checkout. Archive body bytes and declared checkout sizes are bounded; HTTP headers and TLS traffic are not separately metered. Directory file descriptors narrow destination races, but a process with write access can still race after the final parent identity check. The current check suite is deterministic and uses temporary fixtures. Local Git revisions identify HEAD but do not freeze a changing working tree.
