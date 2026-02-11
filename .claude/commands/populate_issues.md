# populate_issues Command

## Purpose

Creates multiple Linear issues from a provided list, following the deterministic instructions in `.claude/tools/linear-issue-creation.md`.

## Usage

```
/populate_issues
```

When invoked, Claude will:
1. Request the list of issues to create (if not provided)
2. Create each issue following the standard Linear issue creation process
3. Report the created issue IDs and any errors

## Input Format

Provide issues as a list in one of the following formats:

### Format 1: Structured JSON

```json
[
  {
    "title": "Issue title",
    "team": "ENG",
    "description": "Optional description",
    "assignee": "user@example.com",
    "priority": 3,
    "labels": ["bug", "urgent"],
    "project": "platform",
    "state": 1,
    "cycle": "current",
    "estimate": 5
  }
]
```

### Format 2: Simple List

```
- Fix login bug [team:ENG, priority:high, estimate:3]
- Add user dashboard [team:ENG, assignee:john@example.com, estimate:5]
- Update API documentation [team:ENG, project:platform, priority:low]
```

### Format 3: Markdown Table

```markdown
| Title | Team | Assignee | Priority | Estimate | Project | Labels |
|-------|------|----------|----------|----------|---------|--------|
| Fix login bug | ENG | john@example.com | high | 3 | platform | bug,critical |
| Add dashboard | ENG | jane@example.com | normal | 5 | platform | feature |
```

## Field Specifications

### Required Fields
- **title**: Issue title (string)
- **team**: Team key (e.g., "ENG", "OPS", "SAL")

### Optional Fields
- **description**: Detailed description (string)
- **assignee**: Email address of assignee (string)
- **priority**: Priority level
  - Numeric: `0` (None), `1` (Low), `2` (Normal), `3` (High), `4` (Urgent)
  - String: `"none"`, `"low"`, `"normal"`, `"high"`, `"urgent"`
- **labels**: Array of label names or comma-separated string
- **project**: Project name (string)
- **milestone**: Milestone name (string)
- **state**: Initial state
  - Numeric: `0` (Canceled), `1` (Backlog), `2` (Todo), `3` (In Progress), `4` (In Review), `5` (Done), `6` (Duplicate)
  - String: `"canceled"`, `"backlog"`, `"todo"`, `"in progress"`, `"in review"`, `"done"`, `"duplicate"`
- **cycle**: Cycle specification
  - `"current"` or `"active"` = Assign to current active cycle
  - Cycle number (integer) = Assign to specific cycle number
  - Cycle ID (UUID string) = Assign to specific cycle ID
- **estimate**: Point estimate (integer)

## Execution Process

For each issue in the list, Claude will:

1. **Validate Input**
   - Ensure required fields (title, team) are present
   - Convert string values (priority, state) to numeric equivalents
   - Validate email format for assignee

2. **Create Base Issue**
   - Execute `linear issue create` with all CLI-supported parameters
   - Extract the created issue ID (e.g., "ENG-1234")

3. **Set Cycle (if specified)**
   - If cycle is "current" or "active", query for the active cycle
   - If cycle is a number, query for that cycle number
   - Use GraphQL API to assign issue to cycle

4. **Set Estimate (if specified)**
   - Use GraphQL API to set point estimate

5. **Verify Creation**
   - Verify the issue was created successfully
   - Report issue URL and ID

6. **Continue or Stop**
   - Continue to next issue
   - If any issue fails, report error but continue with remaining issues

## Output

Claude will provide a summary table:

```
Created Issues:
┌────────────┬──────────────────────────────┬─────────────────────────────────┐
│ Issue ID   │ Title                        │ URL                             │
├────────────┼──────────────────────────────┼─────────────────────────────────┤
│ ENG-1234   │ Fix login bug                │ https://linear.app/...          │
│ ENG-1235   │ Add user dashboard           │ https://linear.app/...          │
└────────────┴──────────────────────────────┴─────────────────────────────────┘

Errors:
- Issue "Update docs" failed: No team specified
```

## Examples

### Example 1: Create Sprint Tasks

```
User: /populate_issues

Claude: Please provide the list of issues to create.

User:
[
  {
    "title": "Setup authentication service",
    "team": "ENG",
    "assignee": "dev@example.com",
    "priority": 3,
    "estimate": 8,
    "cycle": "current",
    "project": "platform",
    "labels": ["backend", "auth"]
  },
  {
    "title": "Design login UI",
    "team": "ENG",
    "assignee": "designer@example.com",
    "priority": 2,
    "estimate": 5,
    "cycle": "current",
    "project": "platform",
    "labels": ["frontend", "design"]
  }
]

Claude: [Creates both issues and reports results]
```

### Example 2: Create Bug List

```
User: /populate_issues

Create these bugs:
- Fix memory leak in API [team:ENG, priority:urgent, estimate:3]
- Resolve login timeout [team:ENG, priority:high, estimate:2]
- Update error messages [team:ENG, priority:low, estimate:1]

Claude: [Parses list and creates 3 issues]
```

## Priority Mapping

| String Value | Numeric Value | Linear Label |
|--------------|---------------|--------------|
| none         | 0             | None         |
| low          | 1             | Low          |
| normal       | 2             | Normal       |
| high         | 3             | High         |
| urgent       | 4             | Urgent       |

## State Mapping

| String Value  | Numeric Value | Linear State  |
|---------------|---------------|---------------|
| canceled      | 0             | Canceled      |
| backlog       | 1             | Backlog       |
| todo          | 2             | Todo          |
| in progress   | 3             | In Progress   |
| in review     | 4             | In Review     |
| done          | 5             | Done          |
| duplicate     | 6             | Duplicate     |

## Error Handling

The command will:
- Continue processing remaining issues if one fails
- Report all errors at the end
- Validate authentication before starting
- Check team existence before creating issues
- Provide clear error messages for invalid input

## Notes

- Authentication must be completed before using this command (`linear auth login`)
- All issues are created sequentially (not in parallel) to avoid rate limiting
- Cycle must exist and be active to assign issues to it
- Assignee must be a valid email address (no `@me` shorthand)
- Labels will be created if they don't exist
- Projects must exist before assignment
