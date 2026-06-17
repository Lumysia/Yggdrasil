# Translation Workflow Reference

Read this file before editing translated modpack files or validating translated overwrite folders.

## Inputs And Outputs

The source pack may be a ZIP archive or an extracted folder.

Create or update a working overwrite folder, not a full rewritten modpack. Mirror the source pack's relative paths only for files that need to replace generated server files. After validation passes, package the overwrite contents into a ZIP archive for final delivery.

Choose a concise ZIP filename from the source pack name, target language, and translation type. Use the user's requested output name when they provide one; otherwise choose a clear name. Keep the archive root directly usable as an overwrite package rather than adding an extra wrapper directory.

When the source pack or bundled mods already provide official localization files for the target language, use those files as terminology references and coverage evidence. Generate overwrite output for user-facing text that remains uncovered by official target-language localization.

Coverage is part of the translation task. If an official target-language localization file is incomplete, fill the missing user-facing entries instead of reporting them as residual risk. Preserve existing official translations exactly. If the runtime merges partial localization files, generate only the missing entries. If the runtime replaces the whole file, generate a complete overwrite file by carrying existing official target-language entries forward unchanged and adding translated entries for the missing keys.

## Translation Scope

Translate user-facing text only:

- Quest `title`, `subtitle`, and `description` text.
- Task and reward display titles.
- Chapter, group, category, entry, and page text.
- Menu, help, tutorial, and in-game book text.
- Language-file values when the file is intended for display text.

Default to translating natural-language terms that players are meant to read. Translate readable dimension, location, creature, faction, structure, boss, material, mechanic, quest, and lore terms when they have an official, community-standard, or clear target-language rendering.

For language files, compare source-language keys against target-language keys when both exist. Missing target-language values for user-facing source keys are translation work, even when the target-language file already exists.

## Technical Token Preservation

Preserve technical content exactly:

- IDs, UUID-like strings, quest IDs, dependency IDs, and group IDs.
- Filenames, resource paths, texture paths, image directives, and namespaces.
- Item IDs, entity IDs, stat IDs, registry names, tags, and NBT selectors.
- Commands, selectors, permissions, URLs, and config keys.
- Formatting codes, escaped quotes, and placeholders.
- Tags and tag-like selectors.

If a string mixes readable prose and special tokens, translate the prose and translatable readable terms, but leave technical tokens intact. Any remaining source-language word in translated display text should be intentional, not the default.

## Editing Rules

Use native patch/edit tooling for translation edits. Keep bulk rewriting scripts out of the translation path.

Allowed automation:

- Read-only discovery and verification scans.
- Archive extraction if needed.
- File listing and diff inspection.

Restricted automation:

- Generating translations with a custom script and writing them back programmatically.
- Regex replacement across all files only for user-approved simple repeated phrases where the replacement is safe.
- Unnecessary reformatting of structured config files.

Keep syntax stable. Preserve indentation, line endings where practical, comments, field order, and non-translated tokens.

## Search And Names

Some modpack terms have established names in the target language. When terminology is uncertain, look for authoritative target-language sources in this order:

- Target-language localization files bundled in the source pack or related mod archives.
- Official project documentation, websites, release pages, and wikis.
- Modpack documentation or wiki pages.
- Established community translations.
- Existing old translation folder supplied by the user.
- Common Minecraft terminology in the target language.

Search within the provided source pack, extracted files, bundled archives, and user-approved paths first. Expand to web search when local sources do not provide enough evidence.

Treat proper nouns as translatable when they are visible story, place, creature, boss, faction, quest, or dimension names and a good target-language name exists or can be rendered naturally. Preserve a proper noun when translation would make gameplay harder to match with item names, in-game lookup tools, commands, registry IDs, or wiki references. Use target-language descriptions around preserved names when helpful.

Build a terminology baseline before large translation batches. Prefer target-language localization bundled in the pack or mod archives, then established community terms, then clear common Minecraft terms. Record recurring decisions for dimensions, progression materials, UI roles, trainer/gym-like concepts, quest mechanics, and common items. Do not treat "lookup-sensitive" as a blanket reason to keep English: preserve exact mod names and true item names when needed, but translate generic prose words, visible UI roles, dimensions, common Minecraft items, mechanics, and title phrases when a target-language rendering is available.

For mixed strings, separate the technical token from the readable text. Translate the readable sentence around preserved names so the result reads naturally in the target language. A translated line that leaves ordinary words such as location names, role names, common item names, instructions, or UI phrases in the source language is incomplete unless the validator report explicitly justifies each remaining term.

## Subagent Workflow

The main agent is the orchestrator. It owns intake, inventory, batching, terminology tracking, review, validation, and final reporting.

Direct work by the main agent is appropriate only for small tasks. When the work may consume substantial context or time, delegate batches to subagents when the environment supports subagents. If subagents are unavailable, run the same batched workflow sequentially and keep the orchestrator role focused on coordination and review.

1. Inventory candidate files and group them by chapter or file type.
2. Identify reference localization and recurring terminology before dispatching translators.
3. Give each translator exact file paths, the terminology baseline, strict preservation rules, and instructions to read each assigned file before editing.
4. Require each translator to edit only assigned files using native patch/edit tooling.
5. Require each translator to read back representative start, middle, and end samples after editing, not only run searches.
6. Require each translator to report changed files, intentionally untranslated terms, terminology decisions, read-back samples checked, and checks performed.
7. Treat empty, missing, or vague translator reports as incomplete. Re-read those assigned files or redispatch them before validation.
8. Review translator reports and run cross-file verification.
9. Track recurring terminology decisions that need consistency across files.
10. Dispatch a separate validator after translators claim completion.
11. Fix validator findings before calling the translation finished.

The validator must be independent from the translation subagents. Completion requires validator results in addition to translator self-reporting.

Use scans as triage, not as proof of quality. Scans can find unchanged files, English-looking prose, and suspicious terms, but they cannot judge whether a translated line reads naturally or whether an English term is justified. For multi-file work, combine scans with representative file reads. Prioritize reading files with empty translator reports, unchanged hashes, low target-language coverage, high source-language prose hits, or repeated mixed-language patterns.

Before final validation, compare translated files against their source counterparts. Any file that is byte-identical to the source, has no target-language text where translation was expected, or contains source-language prose in display fields must be treated as unfinished unless it is intentionally skipped and documented.

## Update Existing Translation

When the user provides an old translation folder or ZIP, treat the task as an update instead of a fresh translation.

1. Extract or read the old translation and new server pack.
2. Compare the old translated overwrite tree against the new source tree.
3. Keep translations for files that still exist and whose structure is compatible.
4. Diff changed files against the new source so new strings are not missed.
5. Translate new or changed user-facing strings.
6. Remove overwrite files that no longer exist in the new source, retaining legacy custom files only when the user explicitly wants them retained.
7. Add overwrite files for new config files that contain translatable user-facing text.
8. Run validation over the final overwrite folder and new source pack.

The overwrite folder should match the new modpack's current file set for translated files. Remove stale files deliberately and include new translatable files.

## Verification Checklist

Before reporting completion:

- Check that every intended source file has a corresponding overwrite file or a reason it was skipped.
- Check official target-language localization coverage; fill obvious missing user-facing entries.
- Compare source and translated file counts and flag byte-identical translated files for manual review.
- Review translator reports; re-open any file from a batch with an empty or non-specific report.
- Scan display fields for remaining source-language prose and readable terms that should have been translated.
- Read representative samples from every translated file for multi-file work. For large files, sample start, middle, and end plus any scan-hit locations.
- Check recurring readable terms for consistent translations across files.
- Check that preserved source-language terms are limited to documented mod names, lookup-sensitive item names, acronyms, technical units, IDs, paths, commands, selectors, formatting codes, and other true technical tokens.
- Confirm technical tokens were preserved, especially commands, IDs, tags, resource paths, and formatting codes.
- Validate syntax with available tools where possible.
- Compare old-vs-new translation trees for update tasks.
- Run a final independent validator for multi-file work.
- Fix validator findings or clearly report intentionally untranslated terms.
- Package the validated overwrite contents into a ZIP archive and report the ZIP path.

## Subagent Prompts

Translation subagent prompt:

```text
Translate user-facing text in these files to <target language>: <paths>.
Use native patch/edit tooling only. Preserve structured config syntax exactly.
Translate player-facing prose and readable game/lore terms by default. Preserve
IDs, commands, registry names, resource paths, tags, URLs, formatting
codes, placeholders, selectors, and config keys. If a string mixes readable text
and a technical token, translate the readable text and preserve only the
technical token. Use the provided terminology baseline and bundled localization
references for official/common names. Do not leave generic UI, role, location,
common item, or instruction words in the source language just because they are
near a preserved mod or item name. Read every assigned file before editing, then
read back representative start/middle/end samples after editing. Keep recurring
readable terms consistent across files. Report changed files, intentionally
untranslated terms with reasons, terminology decisions, read-back samples, and
checks performed.
```

Validator prompt:

```text
Independently validate the translated overwrite folder against the source
server pack. Validate in read-only mode. Use scans only as triage; read
representative samples from every translated file, and read scan-hit locations.
Find uncovered user-facing source keys, byte-identical or untranslated files,
remaining user-facing source-language text, unnecessary mixed-language display
strings, inconsistent recurring terminology, translated technical tokens that
should have been preserved, missing new files, stale removed files, and syntax
risks. Distinguish justified preserved mod/item names from ordinary words that
should be translated. Return findings with file paths and line references. If
clean, state that explicitly and list residual risks.
```
