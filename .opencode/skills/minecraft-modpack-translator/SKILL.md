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

## Scope

Use this skill for Minecraft modpack translation work: quest text, in-game books, scripted language text, user-facing config text, translated overwrite folders, and updates from an older translated overwrite folder or translation pack.

Use this skill for deployment-related work only when translation artifacts affect overwrite-folder deployment.

## Guided Intake

Ask for missing information one decision at a time. If the environment supports interactive choices, forms, or input boxes, use them instead of asking for a long free-form bundle.

When context strongly implies a likely answer, ask the user to confirm or correct that prediction instead of asking from scratch. Use choices only for closed decisions with a known small set of valid answers; use free-form input for open-ended values. Use the user's current conversation language for prompts, option labels, option descriptions, and input hints; re-evaluate that language after each user reply. Translate ordinary readable terms in prompts and options; preserve only exact technical identifiers such as literal file names, paths, commands, env vars, IDs, and protocol names.

1. First determine the target language. If the user stated it explicitly, use it. If context strongly implies a likely target language, ask a short confirmation that includes the predicted language and lets the user correct it. If the target language is unclear, ask with free-form input. Keep target-language intake open-ended rather than using a preset language list. After the target language is confirmed, use the user's latest conversation language for the next intake step, with any explicit conversation-language preference taking precedence.
2. After the target language is known, ask whether this is a first translation or an upgrade of an existing translation. If choices are available, present those two choices in the user's current conversation language.
3. If upgrading, ask for the old translation path before asking for other inputs.
4. Then collect the new source pack path, output location for the packaged result, and translation scope.

Ask one short guided question for the next missing required input whenever the target language or output location is unclear.

## Workflow

Before editing or dispatching subagents, read `references/translation-workflow.md` and follow its detailed rules for translation scope, token preservation, update handling, validation, and subagent prompts.

1. Inventory candidate user-facing files in the source pack.
2. Create or update an overwrite folder that mirrors the source pack's relative paths for files that replace generated server files.
3. Keep direct work limited to small tasks; delegate work that may consume substantial context or time to subagents when the environment supports them.
4. Track recurring terminology decisions when they affect consistency across files or future updates.
5. For multi-file work, assign translation batches and then run an independent validator.
6. Fix validator findings or clearly report intentionally untranslated terms and residual risks.

Default to delivering a ZIP archive containing the overwrite folder contents. Keep the folder as a working artifact for validation, then package it after validation passes. Ask about deployment wiring only when the user explicitly asks to apply the translation to a server or wire it into a runtime setup.

## Completion Summary

Report concisely:

- Source pack path, working overwrite folder path, and output ZIP path.
- Target language.
- Whether this was a first translation or an upgrade.
- File categories translated.
- Files intentionally skipped.
- Terms intentionally left untranslated.
- Recurring terminology decisions when they affect consistency or future updates.
- Validation result, including the independent validator result when used.
- Deployment note only if the user asked for deployment wiring.
