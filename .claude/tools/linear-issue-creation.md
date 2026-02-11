# Linear Issue Creation Guide

This document provides deterministic instructions for creating a Linear issue with all component parts.

## Prerequisites

1. Verify authentication status:
```bash
linear auth status
```

2. If not authenticated, authenticate first:
```bash
linear auth login
```

## Issue Creation Process

### Step 1: Create the Base Issue

Use the `linear issue create` command with the following syntax:

```bash
linear issue create "<TITLE>" [OPTIONS]
```

**Required Parameters:**
- `<TITLE>`: The issue title (positional argument, must be quoted if contains spaces)
- `--team <TEAM_KEY>`: Team key (e.g., "ENG", "OPS", "SAL") - required if no default team is configured

**Optional Parameters:**
- `--description "<TEXT>"` or `-d "<TEXT>"`: Issue description
- `--assignee <EMAIL>`: Assignee email address (e.g., "user@example.com")
- `--priority <NUMBER>` or `-p <NUMBER>`: Priority level:
  - `0` = None
  - `1` = Low
  - `2` = Normal
  - `3` = High
  - `4` = Urgent
- `--labels "<LABEL1>,<LABEL2>"` or `-L "<LABEL1>,<LABEL2>"`: Comma-separated label names
- `--state <NUMBER>` or `-s <NUMBER>`: Initial state:
  - `0` = Canceled
  - `1` = Backlog
  - `2` = Todo
  - `3` = In Progress
  - `4` = In Review
  - `5` = Done
  - `6` = Duplicate
- `--project "<PROJECT_NAME>"`: Project name or ID
- `--milestone "<MILESTONE_NAME>"` or `-m "<MILESTONE_NAME>"`: Milestone name or ID

**Example:**
```bash
linear issue create "Fix login bug" \
  --team ENG \
  --description "Users cannot log in with OAuth" \
  --assignee john@example.com \
  --priority 3 \
  --labels "bug,critical" \
  --project "Q1 Backend Work"
```

**Output:**
The command returns the issue identifier (e.g., "ENG-1234") which is needed for subsequent updates.

### Step 2: Set Cycle (if needed)

The Linear CLI does not support setting cycles directly. Use the GraphQL API instead.

**Process:**
1. Get the access token and find the current active cycle:
```bash
TOKEN=$(python3 -c "from linear_cli.api.auth.storage import CredentialStorage; storage = CredentialStorage('default'); creds = storage.retrieve_credentials(); print(creds.get('access_token', ''))")

curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $TOKEN" \
  -d '{
    "query": "query { cycles(filter: { team: { key: { eq: \"<TEAM_KEY>\" } }, isActive: { eq: true } }, first: 1) { nodes { id number name } } }"
  }'
```

2. Extract the cycle ID from the response and update the issue:
```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $TOKEN" \
  -d '{
    "query": "mutation($issueId: String!, $cycleId: String!) { issueUpdate(id: $issueId, input: { cycleId: $cycleId }) { success issue { identifier cycle { number name } } } }",
    "variables": {
      "issueId": "<ISSUE_ID>",
      "cycleId": "<CYCLE_ID>"
    }
  }'
```

### Step 3: Set Point Estimate (if needed)

The Linear CLI does not support setting point estimates directly. Use the GraphQL API:

```bash
TOKEN=$(python3 -c "from linear_cli.api.auth.storage import CredentialStorage; storage = CredentialStorage('default'); creds = storage.retrieve_credentials(); print(creds.get('access_token', ''))")

curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $TOKEN" \
  -d '{
    "query": "mutation($issueId: String!, $estimate: Int!) { issueUpdate(id: $issueId, input: { estimate: $estimate }) { success issue { identifier estimate } } }",
    "variables": {
      "issueId": "<ISSUE_ID>",
      "estimate": <POINT_VALUE>
    }
  }'
```

### Step 4: Update Other Properties (if needed)

Use `linear issue update` for properties supported by the CLI:

```bash
linear issue update <ISSUE_ID> [OPTIONS]
```

**Available Update Options:**
- `--title "<TEXT>"`: Update title
- `--description "<TEXT>"` or `-d "<TEXT>"`: Update description
- `--assignee <EMAIL>` or `-a <EMAIL>`: Change assignee
- `--state <NUMBER>` or `-s <NUMBER>`: Change state (same numbers as create)
- `--priority <NUMBER>` or `-p <NUMBER>`: Change priority (same numbers as create)
- `--labels "<LABEL1>,<LABEL2>"` or `-L "<LABEL1>,<LABEL2>"`: Replace labels
- `--project "<PROJECT_NAME>"`: Change project
- `--milestone "<MILESTONE_NAME>"` or `-m "<MILESTONE_NAME>"`: Change milestone (use "none" to remove)

## Complete Example Workflow

Create an issue with all components:

```bash
# Step 1: Create base issue
ISSUE_ID=$(linear issue create "Implement user authentication" \
  --team ENG \
  --description "Add OAuth2 authentication flow" \
  --assignee developer@example.com \
  --priority 3 \
  --project "platform" \
  --labels "feature,security" | grep -oP 'ENG-\d+' | head -1)

# Step 2: Set to current cycle
TOKEN=$(python3 -c "from linear_cli.api.auth.storage import CredentialStorage; storage = CredentialStorage('default'); creds = storage.retrieve_credentials(); print(creds.get('access_token', ''))")

CYCLE_ID=$(curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $TOKEN" \
  -d '{"query": "query { cycles(filter: { team: { key: { eq: \"ENG\" } }, isActive: { eq: true } }, first: 1) { nodes { id } } }"}' | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['cycles']['nodes'][0]['id'])")

curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $TOKEN" \
  -d "{\"query\": \"mutation { issueUpdate(id: \\\"$ISSUE_ID\\\", input: { cycleId: \\\"$CYCLE_ID\\\" }) { success } }\"}"

# Step 3: Set point estimate
curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $TOKEN" \
  -d "{\"query\": \"mutation { issueUpdate(id: \\\"$ISSUE_ID\\\", input: { estimate: 5 }) { success } }\"}"

# Step 4: Verify
linear issue show $ISSUE_ID
```

## Deterministic Algorithm for LLMs

Given issue components, follow this algorithm:

1. **Input Validation:**
   - Verify `title` is provided (required)
   - Verify `team` is provided or default team exists
   - Verify `assignee` is an email if provided

2. **Create Issue:**
   ```
   COMMAND = "linear issue create \"" + title + "\""
   IF team: COMMAND += " --team " + team
   IF description: COMMAND += " --description \"" + description + "\""
   IF assignee: COMMAND += " --assignee " + assignee
   IF priority: COMMAND += " --priority " + priority
   IF labels: COMMAND += " --labels \"" + labels.join(",") + "\""
   IF project: COMMAND += " --project \"" + project + "\""
   IF milestone: COMMAND += " --milestone \"" + milestone + "\""
   IF state: COMMAND += " --state " + state

   Execute: COMMAND
   Extract: ISSUE_ID from output
   ```

3. **Set Cycle (if cycle requested):**
   ```
   Get TOKEN from auth storage
   Query active cycle for team
   Execute mutation to set issue cycle
   ```

4. **Set Estimate (if estimate requested):**
   ```
   Get TOKEN from auth storage
   Execute mutation to set issue estimate
   ```

5. **Return Issue Details:**
   ```
   Execute: linear issue show ISSUE_ID
   ```

## Notes

- The `@me` shorthand for assignee does NOT work; always use full email addresses
- Team key is required if no default team is configured
- Cycle and estimate can only be set via GraphQL API
- Priority mapping: 0=None, 1=Low, 2=Normal, 3=High, 4=Urgent
- Issue IDs follow pattern: `<TEAM_KEY>-<NUMBER>` (e.g., "ENG-1234")
