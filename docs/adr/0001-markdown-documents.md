# Documents are Markdown files, not rich text

The PRD called for a rich-text `NSTextView` editor. We chose instead to make ScribeAI a document-based app that saves plain Markdown (`.md`), because the text is sent to a local LLM on nearly every pause and plain text needs no conversion, diffs cleanly, and stays portable to other tools. We accept losing full rich-text formatting (fonts, colours, arbitrary styling); Markdown's light formatting covers what prose writers need.
