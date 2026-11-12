---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [edit-russian-technical-text]
---

Make this paragraph clearer:

The service carries out the processing of incoming requests by means of a queue, and in the event that a situation of queue overflow occurs, requests are dropped without the client being notified. Resending of a request by the client should be performed no earlier than 5 seconds, but no later than 60 seconds, since after that period of time the session identifier becomes invalid. It should be taken into account that the order in which requests are processed is not guaranteed in the case where several instances of the handler are present.
