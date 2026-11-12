---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [python-property-model-tests]
---

Can you write tests for these two functions?

```python
def encode(fields):
    return ";".join(f"{key}={value.replace('\\', '\\\\').replace(';', '\;')}" for key, value in fields.items())


def decode(text):
    fields = {}
    key, value, escaped, in_value = "", "", False, False
    for char in text:
        if escaped:
            value += char
            escaped = False
        elif in_value and char == "\\":
            escaped = True
        elif in_value and char == ";":
            fields[key] = value
            key, value, in_value = "", "", False
        elif not in_value and char == "=":
            in_value = True
        elif in_value:
            value += char
        else:
            key += char
    if key or in_value:
        fields[key] = value
    return fields
```
