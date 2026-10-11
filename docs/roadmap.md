# Development roadmap

This document tracks implementation against the current checkout. A milestone is complete only after `make check` passes and the diff is reviewed.

| Area | Current status | Completion criteria |
| --- | --- | --- |
| CLI and native packs | Implemented | Expand malformed state and module argument tests |
| Palette and templates | Implemented | Add real CWAL version compatibility test on a disposable host |
| Application pipeline | Implemented with limits | Verify live reload semantics on a disposable desktop; preserve ACLs in rollback |
| Wallpaper workflow | Implemented with limits | Support more than the first monitor and alternative backends |
| Import analysis | Implemented with limits | Bound clone disk usage and tighten directory race handling |
| Import conversion | Implemented | Add more source formats with fixtures |
| Checks and CI | Implemented | Run in CI and inspect artifact logs |
| Packaging | Implemented | Verify installation on another disposable Linux host |
| Documentation | Implemented | Review against a live integration pass |

Qt is deferred until a concrete supported frontend is identified. A live GitHub request and live desktop operation have not been tested in this checkout. Git clone download size and concurrent filesystem replacement remain security limits. The current check suite is deterministic and uses temporary fixtures.
