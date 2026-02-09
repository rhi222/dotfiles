---
paths: 
	-  "~/Obsidian/07_Slide/**/*.md"
---

Create a presentation in Markdown according to the following rules.

# Rules for describing presentations using Markdown

Unless otherwise specified, please follow the rules below.

## Basic Structure

- Use a line containing only three or more consecutive hyphens (`---`, `----`, etc.) from the beginning to the end of the line to indicate page breaks between slides.
- Other horizontal rule elements (like `- - -`, `***`, `___`) remain in the content as visual separators and can be used to separate multiple body placeholders.
- Within each slide, the minimum heading level will be treated as the title, and the next level as the subtitle. Higher level headings will be treated as body content. It is recommended to use only one title heading per slide.

## YAML Frontmatter

You can include YAML frontmatter at the beginning of the file:

```yaml
---
title: "Presentation Title"
presentationID: "presentation_id"
breaks: true
author: "Author Name"
date: "2024-01-01"
tags: ["tag1", "tag2"]
custom:
  nested: "value"
  number: 42
---
```

## Supported Markdown Syntax

The following syntax can be used in the slide content:

### Text Formatting

- **Bold** (`**bold**`)
- _Italic_ (`*italic*` or `__italic__`)
- `Inline code` (<code>\`code\`</code>)
- Combined formatting (e.g., **_bold and italic_**)

### Lists

- Bullet lists (`-` or `*`)
- Numbered lists (`1.` or `1)`)
- Nested lists (with proper indentation)
- Alphabetical lists (a. b. c.)

### Links and Images

- Links (`[Link text](https://example.com)`)
- Angle bracket autolinks (`<https://example.com>`)
- Images (`![alt text](image.jpg)`)
- Supports PNG, JPEG, GIF formats
- Supports both local files and URLs (HTTP/HTTPS)

### Block Elements

- Block quotes (`> quoted text`)
- Nested block quotes
- Code blocks with language specification:
  ```language
  code content
  ```
- Mermaid diagrams (in code blocks with `mermaid` language)

### Tables

- GitHub Flavored Markdown (GFM) tables
- Supports table headers with automatic bold formatting
- Cell content can include inline formatting (bold, italic, code)
- Example:
  ```markdown
  | Header 1 | Header 2 | Header 3 |
  | -------- | -------- | -------- |
  | Cell 1   | **Bold** | `code`   |
  | Cell 2   | _Italic_ | Normal   |
  ```
- Header rows are automatically styled with bold text and gray background
- Tables created by users in Google Slides are preserved

### HTML Elements

You can use the following HTML inline elements:

- `<strong>`, `<em>`, `<b>`, `<i>`, `<mark>`, `<small>`
- `<code>`, `<kbd>`, `<cite>`, `<q>`, `<ruby>`, `<rt>`
- `<span>`, `<u>`, `<s>`, `<sub>`, `<sup>`, `<var>`
- `<samp>`, `<data>`, `<dfn>`, `<time>`, `<abbr>`, `<rp>`
- `<br>` (for line breaks)
- Use `class` attribute for custom styling

### Line Break Handling

- Default (`breaks: false`): Soft line breaks become spaces
- With `breaks: true`: Soft line breaks become actual line breaks
- Use `<br>` tags for explicit line breaks

## Page Configuration

Use HTML comments for page settings and speaker notes:

- Page settings: `<!-- {"layout": "title-and-body"} -->`
- Available settings: `"freeze": true`, `"ignore": true`, `"skip": true`
- Speaker notes: `<!-- This is a speaker note -->` (use separate comments for notes)

## Important Notes

- If a comment (`<!-- -->`) contains JSON, it's a page setting - do not overwrite it
- If `"freeze": true` is present in page settings, do not modify that page content at all
- Write speaker notes in separate comments, not in JSON configuration comments
- Code blocks can be converted to images using the `--code-block-to-image-command` option
