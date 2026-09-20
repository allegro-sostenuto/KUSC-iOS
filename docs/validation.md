# Validation record

Prepared 19 September 2026 in a Linux workspace. Status applies to this source delivery, not to a signed installation.

| Check | Result | Evidence / scope |
|---|---|---|
| Official audio endpoint discovery | Passed | Official listening page, stream-service PLS, verified HTTP responses |
| HLS transport structure | Passed | 96 kbps HE-AAC master, timestamped unencrypted AAC media segments |
| Real segment format and clock | Passed | 215 complete ADTS frames; duration 9.984580498866 s against EXTINF 9.98458 s; ffprobe HE-AAC stereo 44.1 kHz |
| Official metadata endpoints and schema | Passed | Current, combined and programme JSON returned HTTP 200; captured schema fixtures |
| Swift source syntax | Passed | 32 Swift files parsed with tree-sitter-swift; zero syntax errors; this is not Swift type checking |
| Project structure | Passed | Six targets, four shared app schemes, 218 project objects with no unresolved object references; all referenced files present |
| Plists, entitlements, privacy manifest | Passed structurally | Parsed as property lists; provisioning authorization not tested |
| Scheme/workspace XML and JSON | Passed structurally | Parsed successfully |
| Icon resources | Passed | Required PNG dimensions, opaque white background; visual inspection of red treble clef |
| Python and shell helpers | Passed structurally | Python byte-compilation, Bash syntax check |
| XCTest suite | Written; not executed | 43 methods covering policies, stream parsing and captured station schema |
| Swift Package compilation | Not run | Swift compiler absent |
| Xcode builds / Apple SDK type checking | Not run | Xcode and Apple SDK absent |
| Signing, installation, simulator launch | Not run | macOS signing environment absent |
| iPhone SE / iPhone 17 acceptance tests | Not run | No connected devices |
| CarPlay, AirPlay, interruptions, Dynamic Island | Not run | Requires Apple system integration / hardware tests |
| Long-duration audio, segment continuity, energy | Not run | Requires running app on target devices |

`../scripts/validate_source.py` repeats the portable structural checks. Optional parser/icon-check packages are development tools only; no Python packages are included in or needed by the iOS app. `../scripts/build_and_test.sh` is the Mac compilation/test entry point. Run the physical-device matrix in `manual_test_plan.md` after signed builds pass.

No static check proves that Apple accepts a capability, that a restricted entitlement is provisioned, that queued audio is seamless, or that silent standby survives iOS suspension. Those results remain explicitly unverified.

## Windows workflow revision

The follow-up audit checked the uploaded free-build/AltStore handoff against current official GitHub, Apple, and AltStore documentation. Added public-repository-only CI for both ordinary targets; it uses `macos-26`, Xcode 26.6 from the documented image, and SHA-pinned official checkout/upload actions. Existing entitlement-free schemes avoid duplicating a PersonalSideload configuration. Full CarPlay is excluded from CI while its optional source remains available.

Local checks: workflow YAML and triggers/matrix were parsed; shell and Python syntax were checked; the portable IPA validator was exercised with synthetic valid SE/17 packages and rejected simulator-platform, wrong identifier/OS, unexpected extension, credential/profile, executable-permission, and malformed archive cases. Synthetic fixtures test the packaging guard; they are not generated KUSC apps and do not prove an Xcode build succeeds.

The workflow has not been dispatched against a selected GitHub repository. No actual KUSC IPA, successful Xcode/test result, AltStore import, physical launch, or automatic-renewal observation is claimed. The first live CI/device run remains the acceptance gate. See [Windows viability review](windows_workflow_review.md) and the revised [installation guide](../installation_guides.md).

The IPA guard distinguishes project executables from prebuilt runtime libraries. It accepts compatible universal arm64 Apple runtimes while rejecting simulator/Catalyst slices; Apple vendor signature checks run on macOS. Synthetic universal-library cases passed locally. Actual codesign validation of a generated KUSC artifact remains unrun.
