---
name: minecraft-modpack-translator
description: Use when translating Minecraft modpack server-pack quest/config text from a ZIP or folder, creating overwrite folders for server deployment, or updating an older translation folder against a newer modpack.
compatibility: opencode
metadata:
  scope: reusable
  game: minecraft
  workflow: translation-overwrite-folder
---

# Minecraft Modpack Translator

## What I Do

- Translate Minecraft modpack quest/config text from a server-pack ZIP or folder.
- Create an overwrite folder that mirrors only the files that should override the generated server files.
- Update an existing translation overwrite folder against a newer modpack version.
- Coordinate translation subagents and an independent validator subagent.

## When To Use

Use this skill when the user wants Minecraft modpack quest/config text translated, especially FTB Quests `.snbt`, Patchouli books, KubeJS/lang text, or similar user-facing config files from a server pack ZIP or folder.

Use this skill when the user says things like:

- Translate FTB quest files.
- Translate a Minecraft modpack/server pack.
- Create an overwrite folder for translated quests.
- Update an old translation ZIP/folder for a new modpack version.
- Keep tags, commands, IDs, and resource names unchanged while translating visible text.

## Role Split

The main agent is the orchestrator. It should gather inputs, split work, dispatch subagents, review results, and perform final verification. It should not do the real translation work itself unless the task is tiny and the user explicitly asks for direct editing.

## Bootstrap

Ask the user for the target language first if it is not already explicit.

Ask for the server pack source:

- ZIP path or folder path for the new modpack/server pack.
- Desired overwrite/output folder path.
- Optional old translation ZIP/folder when updating an existing translation.
- Optional deployment target convention, such as an overwrite folder copied into a Docker bind mount.
- Whether to translate only quests or also books, menus, lang files, and other config text.

Do not guess language or output location when unclear. Ask one short question.

## Inputs And Outputs

The user provides a server pack as either:

- A ZIP archive.
- An already extracted folder.

Create or update an overwrite folder, not a full rewritten modpack. The overwrite folder should mirror the paths that need to replace files on the server. For FTB Quests this usually means paths like:

```text
config/ftbquests/quests/
```

When used with `itzg/minecraft-server`, one common deployment pattern is to copy the overwrite folder into a host config directory, mount it at `/config`, and set:

```text
COPY_CONFIG_DEST=/data/config
SYNC_SKIP_NEWER_IN_DESTINATION=false
```

The exact deployment wiring is environment-specific. Inspect the user's existing Docker, Compose, Kubernetes, or server-launcher setup before suggesting paths.

## Translation Scope

Translate user-facing text only:

- Quest `title`, `subtitle`, and `description` text.
- Task and reward display titles.
- Chapter/group names.
- Patchouli book names, categories, entries, and page text.
- Menu/help/tutorial text stored in config files.
- Language JSON values when the file is intended for display text.

Default to translating natural-language terms that players are meant to read. Do not leave English in the translated output just because a word is a Minecraft/modpack concept. Translate dimensions, locations, mobs, factions, structures, bosses, materials, mechanics, and lore terms when they have an official, community-standard, or clear target-language rendering. Examples of translatable readable terms include dimension names like `Overworld`, `Nether`, `End`, `The Otherside`, `Underdark`, `Everbright`, and `Everdawn`; mob or group names like `Primal Titans`; and gameplay/lore phrases embedded in prose.

Preserve technical content exactly:

- IDs, UUID-like strings, quest IDs, dependency IDs, group IDs.
- Filenames, resource paths, texture paths, image directives, and namespaces.
- Item IDs, entity IDs, stat IDs, registry names, tags, and NBT selectors.
- Commands, selectors, permissions, URLs, and config keys.
- Minecraft formatting codes like `&e`, `&r`, `&9`, escaped quotes, and placeholders.
- Tags such as `#botania:runes`; translate surrounding readable words only, for example `Any #botania:runes` to `任意 #botania:runes`.

If a string mixes readable prose and special tokens, translate the prose and any translatable readable terms, but leave the technical tokens intact. A remaining English word in translated display text should be intentional, not the default.

## Editing Rules

Use the environment's native patch/edit tooling for translation edits. Do not write ad-hoc scripts to rewrite translation text in bulk.

Allowed automation:

- Read-only discovery and verification scans.
- Archive extraction if needed.
- File listing and diff inspection.

Not allowed:

- Generating translations with a custom script and writing them back programmatically.
- Blind regex replacement across all files unless the user explicitly approves a simple repeated phrase and the replacement is safe.
- Reformatting SNBT/JSON/TOML files unnecessarily.

Keep syntax stable. Preserve indentation, line endings where practical, comments, field order, and non-translated tokens.

## Subagent Workflow

Use subagents for the real translation work when the current assistant environment supports subagents and there is more than one small file. If subagents are unavailable, do the same workflow sequentially and keep the main agent's role as coordination/checking as much as possible.

1. Main agent inventories candidate files and groups them into batches by chapter/file type.
2. Main agent gives each subagent exact file paths and strict preservation rules.
3. Each translation subagent edits only its assigned files using native patch/edit tooling.
4. Each subagent reports files changed, strings intentionally left untranslated, and verification performed.
5. Main agent reviews the reports and runs cross-file verification.
6. Main agent dispatches a separate validator subagent after all translators claim completion.
7. Validator subagent checks whether translation is really complete and reports missed user-facing English text, broken syntax, stale files, or unsafe translated technical tokens.
8. If validator finds issues, main agent assigns fixes to translation subagents or asks a focused follow-up.
9. Only after validator passes should main agent call the translation finished.

The validator must be independent from the translation subagents. Do not accept “finished” based only on translator self-reporting.

## Update Existing Translation

When the user provides an old translation folder or ZIP, treat the task as an update instead of a fresh translation.

Workflow:

1. Extract or read the old translation and new server pack.
2. Compare the old translated overwrite tree against the new modpack source tree.
3. Keep translations for files that still exist and whose structure is compatible.
4. Diff changed files against the new modpack source so new strings are not missed.
5. Translate new or changed user-facing strings.
6. Remove overwrite files that no longer exist in the new modpack unless the user explicitly wants legacy custom files retained.
7. Add overwrite files for new quest/config files that contain translatable user-facing text.
8. Run the validator subagent over the final overwrite folder and the new source pack.

The important update invariant: the overwrite folder should match the new modpack's current file set for translated files. Do not carry removed old files forward silently, and do not miss new files.

## Search And Names

Some modpack terms have established Chinese names. If unsure, search current docs, wiki pages, existing localization files, or community translations. Prefer consistency with:

- The mod's existing `zh_cn` lang files.
- The modpack's own wiki or docs.
- Existing old translation folder supplied by the user.
- Common Minecraft Simplified Chinese terminology.

Do not treat proper nouns as automatically untranslatable. Translate proper nouns when they are visible story, place, creature, boss, faction, quest, or dimension names and a good target-language name exists or can be rendered naturally. Keep a proper noun untranslated only when translating it would make gameplay harder to match with item names, JEI, commands, registry IDs, or wiki references. Use Chinese descriptions around preserved names when helpful.

## Verification Checklist

Before reporting completion:

- Check that every intended source file has a corresponding overwrite file or a reason it was skipped.
- Scan display fields for remaining source-language prose and readable terms that should have been translated.
- Confirm technical tokens were preserved, especially commands, IDs, tags, resource paths, and formatting codes.
- Validate syntax with available tools where possible.
- Compare old-vs-new translation trees for update tasks.
- Run a final independent validator subagent.
- Fix validator findings or clearly report any intentionally untranslated terms.

## Completion Summary

Report concisely:

- Source pack path and overwrite folder path.
- Target language.
- File categories translated.
- Files intentionally skipped.
- Terms intentionally left untranslated.
- Validation result, including the independent validator subagent result.
- Deployment note, if the overwrite folder should be copied or mounted somewhere.

## Example Orchestration Prompt

Use a prompt like this for translation subagents:

```text
Translate user-facing text in these files to Simplified Chinese: <paths>.
Use native patch/edit tooling only. Preserve SNBT/JSON syntax exactly.
Translate player-facing prose and readable game/lore terms by default,
including dimensions, mobs, bosses, places, factions, mechanics, and quest
names. Do not translate IDs, commands, registry names, resource paths, tags,
URLs, formatting codes, placeholders, selectors, or config keys. If a string
mixes readable text and a technical token, translate the readable text and
preserve only the technical token.
Report changed files, intentionally untranslated terms, and checks performed.
```

Use a prompt like this for the validator subagent:

```text
Independently validate the translated overwrite folder against the source
server pack. Do not edit files. Find remaining user-facing source-language
text, translated technical tokens that should have been preserved, missing new
files, stale removed files, and syntax risks. Return findings with file paths
and line references. If clean, state that explicitly and list residual risks.
```
