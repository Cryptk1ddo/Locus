# Page references and capture lineage

Implemented on 2026-10-01. No workspace/session schema migration is needed.

Scope: finish the page/reference lifecycle milestone without changing Tab/WebKit
ownership, global pins, close ordering or browser navigation. Existing browser
regressions must pass alongside focused object lifecycle tests.

## Close and reopen

Search's in-memory closed-tab record retains an optional Space-scoped WallBinding.
Single-tab, group and Clear undo re-resolve it against the current Space's page
objects before restoring it. A deleted object, deleted/different Space or unknown
object type drops the binding while the page reopens through Search's original
paths. Private/Bench/held sign-in pages do not acquire object bindings. No closed
tab or capture becomes a durable object automatically. Split/group restoration
keeps its original index and runtime partner logic.

## Saved and live addresses

The existing Open action selects the bound tab at its current address, preferring
the active tab and otherwise the most recently used local binding. A page
card's context menu adds **Open Saved Address**, which explicitly navigates that
tab to the saved address (or opens it when no bound tab remains). Browser unload
and navigation handling still apply. No automatic URL equality binding occurs.

**Update from Bound Tab** explicitly saves that tab's current title/address into
the same page object. It is available for a normal, nonloading bound tab, including
a sleeping tab whose pending address is already known. It does not wake, select
or navigate the tab. Credentials are stripped; unsupported schemes are rejected.
Unknown object/source/content fields and incoming capture relationships survive.
The update checks the expected object against the current snapshot, commits
atomically and leaves it unchanged on conflicts or write failure. Other windows'
objects and search results observe the successful revision. Capture observations
retain their original evidence and URL even when the source page reference updates.

## Capture again

A capture card's context menu can **Open Source Page** through its `capturedFrom`
page object. **Capture Again** is available only when that source is the active,
loaded, normal bound tab in the current Space. It starts the existing picker;
the user chooses the element again. It does not replay a brittle DOM selector,
navigate automatically, or claim the chosen element has identical identity.

The new immutable observation has `capturedFrom` and `derivedFrom` relationships.
The predecessor and source are revalidated by the serialized store before asset
staging and publication. Original capture evidence/assets stay untouched.
Explicit object deletion still removes incoming relationship links under the
existing store contract; it preserves retained capture content and assets. Escape,
navigation and other existing capture cancellation rules apply; deleting the
predecessor or source while capture is pending prevents the derived commit.

## Validation

Validated on 2026-10-01 in isolated profiles and temporary workspace folders:

- Debug app built successfully with ad-hoc signing.
- **74 Swift tests passed in separate runs:** 67 without the existing WebKit
  download suite, then its 7 tests in isolation. Five new lifecycle fixtures
  cover scoped binding resolution, reference conflicts/write failures, unknown
  field preservation, retained evidence/assets and derived-capture validation.
- **27 native lifecycle checks passed:** single-tab, Close Group and Clear undo;
  split restoration; explicit saved/live actions without additional tabs/views;
  updated search; recapture eligibility/cancellation/lineage; deletion during
  capture; wrong-Space/private exclusion; reference, binding and asset restart.
- Existing native binding (**20**), pin/Clear/session (**32**), UI capture (**20**)
  and object-search (**22**) regressions passed. Total: **121 native checks**.
- `git diff --check` passed.

An earlier full Swift run passed all 74 tests. Two full-suite reruns timed out
in different existing WebKit download fixtures (cancel and private completion);
each passed in another run, and the isolated download suite passed. This
intermittent full-suite behavior remains a release-QA concern. No download
implementation or fixture was changed to suppress it.

Reproduce after building the debug app:

```sh
swift test --skip DownloadLifecycleTests
swift test --filter DownloadLifecycleTests
python3 Tests/page_reference_lifecycle.py
python3 Tests/wall_binding.py
python3 Tests/pin_tiers.py
python3 Tests/ui_capture.py
python3 Tests/object_search.py
```

Bench probes execute the native browser actions; these checks do not replace
hands-on context-menu, trackpad or accessibility release QA. No production
browser session was used.
