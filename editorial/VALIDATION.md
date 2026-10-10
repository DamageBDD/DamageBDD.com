# Article pack validation — 10 October 2026

## Passed on the supplied website baseline

The pack was checked against the modernized DamageBDD.com source archive supplied in this conversation, not an assumed live production tree.

| Check | Result |
|---|---|
| Article manifest and SHA-256 content identities | 14 new pages passed |
| Required editorial/evidence metadata | 154 field checks passed |
| Relative Org links in the new pages | 62 references resolved against pack plus baseline |
| Shared header includes | 14 resolved |
| Evidence URL syntax and manifest consistency | 35 references passed; not HTTP reachability checks |
| Historical repository evidence paths | Each matches a link recorded in an existing supplied implementation guide |
| Collection coverage | All 13 long-form articles linked by the new collection |
| Feature coverage ledger | 43 areas map to real article slugs with evidence pointers and boundaries |
| Source hygiene | No internal sandbox paths, unresolved template markers, duplicate titles or invented verified-release fields in new articles |
| Optional validator Python syntax | Parsed successfully |
| README shell examples | Parsed with sh -n; not executed |
| Validator negative cases | 8 intentionally damaged fixtures correctly rejected |

## Patch tests

The full patch was generated against the exact baseline article index. It was applied in an isolated Git repository and the resulting files were compared byte-for-byte with the pack. The additions-only patch was separately applied to the baseline; it left the index unchanged and every new file matched the pack. The article-index insertion is therefore still required after the additions-only option.

`git diff --cached --check` and `git apply --check` succeeded for the tested patch bases. These checks do not establish applicability to an index the user has edited since that baseline.

## Not performed

Emacs and Erlang were not available in this environment. No native Org export, ERT suite, application compilation or runtime feature test was run. No live provider, wallet, Nostr relay, signing vault, IPFS retention, model or native workstation integration was tested. External source links were not exhaustively checked for availability; selected public pages were fetched and some were cached.

The complete current GitHub tree, history and HEAD were not obtained. This is an evidence-bounded editorial review, not a verified latest-release changelog. No production website deployment or rsync operation was performed.

## Recheck locally

From the website repository after applying or merging this pack:

```sh
python3 editorial/validate_article_pack.py
```

The checker is read-only and uses Python's standard library. After editing an article, review and update its manifest identity rather than suppressing a mismatch. Run the existing Emacs tests and staging build documented in [README.md](README.md), then inspect the generated collection, Markdown and search inventory before deploying.
