# Security

Locus is a development browser. Use the newest release; older releases do not
receive separate fixes. Report vulnerabilities through this repository's GitHub
Security → Report a vulnerability flow. Avoid posting credentials, private profile
data or exploit details in public issues.

Development update manifests are informational: they can announce a release and
open GitHub, but cannot authorize executable installation. Signed installations
require a signed manifest and a matching Developer ID team and bundle identifier,
as well as archive checksums. Unsigned metadata is never a fallback for a signed
installation. Signing and notarization are not yet enabled for public releases.

Keep regression runs in isolated `SEARCH_PROBE` profiles. Installed Locus and
upstream Search have separate profile directories, bundle identifiers and keychain
labels. No silent migration or deletion of older profiles is performed.
