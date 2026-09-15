# Security Policy

Peek Mail opens files that often come from strangers, so security reports are taken seriously.

## Reporting a vulnerability

Please **don't open a public GitHub issue** for security problems. Email **[support@oesterl.ing](mailto:support@oesterl.ing)** with:

- a description of the issue and its impact,
- steps to reproduce, ideally with a sample `.eml` or `.msg` file (anonymized),
- the Peek Mail and macOS versions you used.

You'll get a reply within a few days. Once a fix is released, you're welcome to be credited in the release notes.

## Supported versions

Security fixes go into the latest release. Please update to the newest version from the [releases page](https://github.com/jappi00/peek-mail/releases/latest) before reporting.

## What's in scope

Anything that lets a mail file do more than display content, for example:

- running code or opening apps and local files without the user's explicit action,
- loading remote content while remote content is blocked,
- bypassing Gatekeeper checks for opened attachments,
- reading or writing files outside the app's history folder and temporary attachment folder.
