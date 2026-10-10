# DamageBDD market article pack

This is a content-only patch for the modernized DamageBDD.com Org website. It contains thirteen article-length evaluation guides and one collection, adds a collection link to `org/articles/index.org`, and retains an editorial evidence ledger. It does not modify application code, publish scripts, snippets, CSS, JavaScript, `org/sitemap.org` or generated `index.inc`.

## Apply

Use the Git patch from the website repository root with the prior modernization applied. The full patch expects the article-index baseline shipped in that modernization archive; it does not depend on replacing `scripts/publish.el`.

```sh
git apply --check ~/Downloads/damagebdd-market-articles.patch &&
git apply ~/Downloads/damagebdd-market-articles.patch
```

Use the ZIP as source inspection or manual-merge material, not as a reason to overwrite unrelated work. When the existing article index has diverged, the additions-only patch can add all new files without modifying that index:

```sh
git apply --check ~/Downloads/damagebdd-market-articles-additions-only.patch &&
git apply ~/Downloads/damagebdd-market-articles-additions-only.patch
```

Use **one patch, not both**. After using additions-only, insert this link into the existing article index before its `index.inc` include:

```org
Explore [[file:solutions_evidence_first.org][Start With the Problem. Keep the Evidence.]]
for customer-problem evaluation guides with explicit implementation boundaries.
```

## Validate and publish

The following checker uses only Python's standard library and reads files; it does not publish, execute Org code or fetch URLs. It is an optional editorial check, not a new dependency of the publishing pipeline.

```sh
python3 editorial/validate_article_pack.py
```

Run the existing ERT suites on the build machine. The asset test file below is supplied by the separate asset-URL fix from the earlier change:

```sh
emacs -Q --batch \
  -l scripts/publish-tests.el \
  -l scripts/site-tests.el \
  -l scripts/publish-asset-tests.el \
  -f ert-run-tests-batch-and-exit

DAMAGEBDD_SITE_URL=https://staging.damagebdd.com \
  sh scripts/publish.sh build
```

Inspect the new collection, an article, the generated Markdown and `docs/index.json` before deploying the complete regenerated `public/` tree with the established rsync procedure. The publisher should regenerate the catalogue/discovery outputs; do not hand-edit their entries.

These commands are instructions for your build machine, **not a record that Emacs tests or export ran during content generation**. No runtime feature tests or deployment were performed.

## Commit only this pack

The following explicit paths exclude archives, unrelated edits and existing generated output. Review `git status` first; previously staged changes remain part of a commit unless you separately unstage them.

```sh
git add -- \
  org/articles/index.org \
  org/articles/ai_change_acceptance.org \
  org/articles/api_journey_assurance.org \
  org/articles/software_delivery_acceptance.org \
  org/articles/release_provenance.org \
  org/articles/private_support_copilot.org \
  org/articles/versioned_knowledge_releases.org \
  org/articles/incident_to_reviewed_patch.org \
  org/articles/nostr_signing_governance.org \
  org/articles/nostr_search_for_products.org \
  org/articles/lightning_api_economics.org \
  org/articles/verifiable_media_evidence.org \
  org/articles/local_operations_workbench.org \
  org/articles/self_hosted_verification.org \
  org/articles/solutions_evidence_first.org \
  editorial/article-manifest.json \
  editorial/feature-coverage-2026-10-10.json \
  editorial/source-register.json \
  editorial/repository-market-review-2026-10-10.md \
  editorial/README.md \
  editorial/VALIDATION.md \
  editorial/validate_article_pack.py &&
git diff --cached --check &&
git diff --cached --stat &&
git commit -F - <<'COMMIT'
docs(site): add evidence-led customer evaluation articles

Add thirteen use-case guides and a collection covering software acceptance,
release provenance, private knowledge, repair review, Nostr infrastructure,
Lightning-funded jobs and the erm operations workbench.

Connect the existing article index to the new collection while preserving
implementation references and the Org publishing/discovery pipeline.

Record source-review scope, feature coverage and market priorities without
promoting historical or unverified integrations to validated capabilities.
COMMIT
```

## Evidence model

New guides use `documentation_review_only`, do not introduce duplicate capability IDs, and do not claim a verified runtime release. Search and payment pages are explicitly evaluation blueprints. Proposed pilot metrics are not measured results. See the market review, feature ledger and source register for the source-access limitations that prevent calling this a complete latest-repository audit.
