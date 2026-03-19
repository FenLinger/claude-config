# Agent Brief Template

Use this template when constructing a research agent brief. Fill in each
field before launching the agent. Delete this instruction block when using.

---

## Agent: {{agent-name}}

**Mode:** {{foreground | background}}
**Scratch file:** `survey/_scratch/{{agent-name}}.md`

### Questions

1. {{Question 1}}
   - **Expected output:** {{e.g., "a table with columns X, Y, Z"}}
   - **Stop condition:** {{e.g., "if not found in 3 searches, note the gap and move on"}}

2. {{Question 2}}
   - **Expected output:** {{description}}
   - **Stop condition:** {{description}}

3. {{Question 3}}
   - **Expected output:** {{description}}
   - **Stop condition:** {{description}}

4. {{Question 4 (optional)}}
   - **Expected output:** {{description}}
   - **Stop condition:** {{description}}

5. {{Question 5 (optional, hard limit)}}
   - **Expected output:** {{description}}
   - **Stop condition:** {{description}}

### Pre-flight Estimate

| Metric | Value |
|--------|-------|
| Questions | {{N}} (≤5) |
| Est. searches/question | {{N}} (~2–3) |
| Est. total searches | {{N}} (≤15) |
| Classification | {{must-have / nice-to-have}} |

### Checkpoint Instruction

Include this verbatim in the agent prompt:

> After answering each question, append your findings to
> `survey/_scratch/{{agent-name}}.md` using the Write tool.
> This ensures partial results survive if you run out of context.
