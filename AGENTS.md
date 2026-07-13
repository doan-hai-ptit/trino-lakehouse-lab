# Trino documentation guidelines

Apply these instructions when creating or rewriting Trino Markdown documentation in this repository, especially files under `security/`.

## Goal and sources

- Summarize documentation for practical implementation: retain what is needed to understand the mechanism, configuration, defaults, rule evaluation order, limitations, and testing.
- Use official Trino documentation as the primary source. When the user provides a URL, verify against that exact page. For information that can change, check the current documentation before writing.
- Include the official source link in a `References` section. Do not copy long passages verbatim from the source.
- Write clearly in the language requested by the user. Preserve property names, values, SQL, regular expressions, file names, and technical terms when needed.

## General-purpose scope

- Write documentation that works across projects and deployment styles. Do not include repository-specific service names, Docker Compose details, hostnames, ports, mount paths, workers, or files unless the user explicitly requests an environment-specific guide.
- Use general Trino configuration paths such as `etc/config.properties`, `etc/access-control.properties`, `etc/group-provider.properties`, and `etc/rules.json` when the document needs to name a file.
- Do not change runtime configuration, Docker Compose, secrets, or real policies when the user only asks to write or summarize documentation.

## Configuration block rules

Every `properties`, `json`, or `text` block that describes configuration must have a sentence immediately before it that states the action and target file:

- Create `etc/<file>` and place the following content in it.
- Add the following property to `etc/config.properties` on the coordinator.
- Add the following section to the configured ACL JSON rule file (for example, `etc/rules.json`).

Do not add comments such as `# File: ...` inside a configuration block solely to identify its location. Put that information in the paragraph immediately before the block.

Keep configuration lines, JSON, SQL, regular expressions, and sample values from the Trino source unchanged. Change them only to correct a verified error or to replace an explicit placeholder; explain any such change in the surrounding text.

When two approaches are mutually exclusive (for example, pattern mapping versus file mapping, or a file provider versus LDAP), state that the reader must choose one and identify the file to create or edit for each approach.

## Document structure

Prefer the structure used in `security/FILE_SYSTEM_ACCESS_CONTROL.md`:

1. Briefly explain the mechanism and scope.
2. Describe critical behavior and rules before examples.
3. Put a file-placement instruction immediately before every configuration block.
4. Explain how to apply it, evaluation order, defaults, and common pitfalls.
5. Add testing guidance and a checklist when appropriate.
6. End with a `References` section containing official Trino links.

Do not add a host/container path overview or Compose procedure at the beginning of general-purpose documentation. State the file location only where the reader needs it for a configuration block.

## Checks before completion

- Ensure every code block has matching opening and closing triple backticks.
- Parse JSON blocks to confirm valid syntax.
- Check that local Markdown links resolve.
- Run `git diff --check`.
- Review the document for details that only apply to one lab or project, unless the user requested them.
