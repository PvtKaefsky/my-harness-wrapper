---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [quick-human-readable-review]
---

Review this diff.

```diff
--- a/billing/invoice.py
+++ b/billing/invoice.py
@@ -12,9 +12,11 @@ def total(lines, discount=None):
     subtotal = sum(line.price * line.quantity for line in lines)
-    if discount:
-        subtotal = subtotal - discount
-    return round(subtotal, 2)
+    if discount is not None:
+        if discount > subtotal:
+            raise ValueError("discount exceeds subtotal")
+        subtotal -= discount
+    return round(subtotal, 2)
```
