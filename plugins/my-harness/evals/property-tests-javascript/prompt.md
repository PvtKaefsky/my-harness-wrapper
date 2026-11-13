---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [python-property-model-tests]
---

Write Jest tests for this function.

```javascript
function slugify(title) {
  return title
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

module.exports = { slugify };
```
