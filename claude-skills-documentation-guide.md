# Claude Skills: Complete Documentation & Best Practices Guide

## Overview

**Skills** are modular, filesystem-based capabilities that extend Claude's functionality by packaging instructions, metadata, scripts, and resources into reusable directories. Think of them as "onboarding guides" for specific domains—they transform Claude from a general-purpose agent into a specialized one equipped with procedural knowledge.

### Key Benefits
- **Specialize Claude**: Tailor capabilities for domain-specific tasks
- **Reduce Repetition**: Create once, use automatically
- **Compose Capabilities**: Combine multiple Skills for complex workflows
- **Progressive Disclosure**: Only load context when needed (token-efficient)

---

## Skill Structure

Every Skill is a directory containing at minimum a `SKILL.md` file:

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter metadata (required)
│   │   ├── name: (required) 
│   │   └── description: (required)
│   └── Markdown instructions (required)
└── Optional Resources
    ├── scripts/       # Executable code (Python/Bash)
    ├── references/    # Documentation loaded into context as needed
    └── assets/        # Files used in output (templates, icons, etc.)
```

### SKILL.md Requirements

#### YAML Frontmatter (Required)

```yaml
---
name: your-skill-name
description: Brief description of what this Skill does and when to use it
---
```

**Field Requirements:**

| Field | Rules |
|-------|-------|
| `name` | Max 64 chars, lowercase letters/numbers/hyphens only, no XML tags, no reserved words ("anthropic", "claude") |
| `description` | Max 1024 chars, non-empty, no XML tags, should include BOTH what it does AND when to trigger |

#### Body (Required)
Markdown instructions and guidance. Keep under 500 lines for optimal performance.

---

## Progressive Disclosure Architecture

Skills use a three-level loading system to manage context efficiently:

| Level | When Loaded | Token Cost | Content |
|-------|-------------|------------|---------|
| **1: Metadata** | Always (at startup) | ~100 tokens | `name` and `description` from frontmatter |
| **2: SKILL.md Body** | When Skill triggers | Under 5k tokens | Instructions, workflows, references |
| **3+: Resources** | As needed | Effectively unlimited | Scripts executed without loading; reference files read selectively |

**Key insight**: Files don't consume context until accessed. Claude navigates your Skill like reading a manual—accessing only what each task requires.

---

## Core Authoring Principles

### 1. Concise is Key

The context window is a shared resource. Only add what Claude doesn't already know.

**Bad (verbose):**
```markdown
PDF (Portable Document Format) files are a common file format that contains
text, images, and other content. To extract text from a PDF, you'll need to
use a library. There are many libraries available...
```

**Good (concise):**
```markdown
## Extract PDF text
Use pdfplumber for text extraction:
```python
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```

### 2. Set Appropriate Degrees of Freedom

Match specificity to task fragility:

| Freedom Level | When to Use | Example |
|---------------|-------------|---------|
| **High** (text instructions) | Multiple valid approaches, context-dependent | Code review guidelines |
| **Medium** (pseudocode/parameterized scripts) | Preferred pattern exists, some variation OK | Report generation templates |
| **Low** (specific scripts, few params) | Fragile operations, consistency critical | Database migrations |

**Analogy**: Narrow bridge = specific guardrails; Open field = general direction.

### 3. Write Effective Descriptions

The description is the **primary triggering mechanism**. Claude uses it to decide when to activate the Skill from potentially 100+ available Skills.

**Always write in third person** (descriptions are injected into system prompt):
- ✓ Good: "Processes Excel files and generates reports"
- ✗ Avoid: "I can help you process Excel files"
- ✗ Avoid: "You can use this to process Excel files"

**Include both what it does AND triggers:**
```yaml
description: Extract text and tables from PDF files, fill forms, merge documents. 
             Use when working with PDF files or when the user mentions PDFs, forms, 
             or document extraction.
```

### 4. Use Progressive Disclosure Patterns

**Pattern 1: High-level guide with references**
```markdown
# PDF Processing

## Quick start
[code example]

## Advanced features
**Form filling**: See [FORMS.md](FORMS.md) for complete guide
**API reference**: See [REFERENCE.md](REFERENCE.md) for all methods
```

**Pattern 2: Domain-specific organization**
```
bigquery-skill/
├── SKILL.md (overview and navigation)
└── reference/
    ├── finance.md (revenue, billing metrics)
    ├── sales.md (opportunities, pipeline)
    └── product.md (API usage, features)
```

**Pattern 3: Conditional details**
```markdown
## Editing documents
For simple edits, modify XML directly.
**For tracked changes**: See [REDLINING.md](REDLINING.md)
```

**Important**: Keep references ONE level deep from SKILL.md. Deeply nested references cause partial reads.

---

## Workflows and Feedback Loops

### Use Checklists for Complex Tasks

```markdown
## PDF form filling workflow

Copy this checklist and track your progress:

```
Task Progress:
- [ ] Step 1: Analyze the form (run analyze_form.py)
- [ ] Step 2: Create field mapping (edit fields.json)
- [ ] Step 3: Validate mapping (run validate_fields.py)
- [ ] Step 4: Fill the form (run fill_form.py)
- [ ] Step 5: Verify output (run verify_output.py)
```
```

### Implement Feedback Loops

**Common pattern**: Run validator → fix errors → repeat

```markdown
## Document editing process

1. Make edits to `word/document.xml`
2. **Validate immediately**: `python ooxml/scripts/validate.py unpacked_dir/`
3. If validation fails:
   - Review error message
   - Fix issues in XML
   - Run validation again
4. **Only proceed when validation passes**
```

---

## Bundled Resources

### Scripts (`scripts/`)
Executable code for deterministic, repeatable tasks.

- **When to include**: Same code being rewritten repeatedly; deterministic reliability needed
- **Benefits**: Token efficient (executed without loading), deterministic, consistent
- **Note**: Make clear whether Claude should EXECUTE or READ as reference

```markdown
## Utility scripts

**analyze_form.py**: Extract all form fields from PDF
```bash
python scripts/analyze_form.py input.pdf > fields.json
```
```

### References (`references/`)
Documentation loaded selectively into context.

- **When to include**: Documentation Claude should reference while working
- **Examples**: Database schemas, API docs, company policies
- **Best practice**: For files >10k words, include grep search patterns in SKILL.md

### Assets (`assets/`)
Files used in output (NOT loaded into context).

- **When to include**: Templates, images, icons, fonts, boilerplate
- **Examples**: `logo.png`, `slides.pptx` template, `frontend-template/`

---

## Common Patterns

### Template Pattern
```markdown
## Report structure

ALWAYS use this exact template structure:

```markdown
# [Analysis Title]

## Executive summary
[One-paragraph overview]

## Key findings
- Finding 1 with data
- Finding 2 with data

## Recommendations
1. Actionable recommendation
```
```

### Examples Pattern
```markdown
## Commit message format

**Example 1:**
Input: Added user authentication with JWT tokens
Output:
```
feat(auth): implement JWT-based authentication
Add login endpoint and token validation middleware
```
```

### Conditional Workflow Pattern
```markdown
## Document modification workflow

1. Determine modification type:
   **Creating new content?** → Follow "Creation workflow"
   **Editing existing content?** → Follow "Editing workflow"

2. Creation workflow:
   - Use docx-js library
   - Build from scratch
   - Export to .docx
```

---

## Anti-Patterns to Avoid

### ✗ Windows-Style Paths
- Bad: `scripts\helper.py`
- Good: `scripts/helper.py`

### ✗ Too Many Options
- Bad: "Use pypdf, or pdfplumber, or PyMuPDF, or..."
- Good: "Use pdfplumber. For scanned PDFs requiring OCR, use pdf2image instead."

### ✗ Time-Sensitive Information
- Bad: "If before August 2025, use old API"
- Good: Use "old patterns" section with collapsible details

### ✗ Deeply Nested References
- Bad: SKILL.md → advanced.md → details.md
- Good: All references link directly from SKILL.md

### ✗ Extraneous Documentation
Do NOT create: README.md, INSTALLATION_GUIDE.md, CHANGELOG.md, etc.
Skills contain only what an AI agent needs to do the job.

---

## Evaluation and Iteration

### Build Evaluations First

Create evaluations BEFORE writing extensive documentation.

**Evaluation-driven development:**
1. Identify gaps: Run Claude on tasks without Skill, document failures
2. Create evaluations: Build 3 scenarios testing these gaps
3. Establish baseline: Measure performance without Skill
4. Write minimal instructions: Just enough to pass evaluations
5. Iterate: Execute, compare, refine

### Iterate with Claude

**Creating a new Skill:**
1. Complete a task with Claude A using normal prompting
2. Notice what context you repeatedly provide
3. Ask Claude A to capture patterns into a Skill
4. Test with Claude B (fresh instance with Skill loaded)
5. Return to Claude A with observations for improvements

**Observing Claude's Usage:**
- Unexpected exploration paths → Structure isn't intuitive
- Missed connections → Links need to be more explicit
- Overreliance on sections → Content should move to SKILL.md
- Ignored content → Might be unnecessary

---

## Advanced: Skills with Executable Code

### Solve, Don't Punt

Handle errors explicitly rather than failing to Claude:

**Good:**
```python
def process_file(path):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        print(f"File {path} not found, creating default")
        with open(path, 'w') as f:
            f.write('')
        return ''
```

### Self-Documenting Constants

**Good:**
```python
# HTTP requests typically complete within 30 seconds
REQUEST_TIMEOUT = 30  # accounts for slow connections

# Three retries balances reliability vs speed
MAX_RETRIES = 3
```

**Bad:**
```python
TIMEOUT = 47  # Why 47?
```

### Create Verifiable Intermediate Outputs

For complex tasks: plan → validate plan → execute → verify

Example workflow:
1. Analyze → Create `changes.json`
2. Validate `changes.json` with script
3. If validation fails, iterate on plan
4. Only then execute changes
5. Verify final output

### MCP Tool References

Always use fully qualified names: `ServerName:tool_name`
```markdown
Use the BigQuery:bigquery_schema tool to retrieve schemas.
```

---

## Checklist for Effective Skills

### Core Quality
- [ ] Description is specific and includes key terms
- [ ] Description includes both WHAT it does and WHEN to use it
- [ ] SKILL.md body under 500 lines
- [ ] Additional details in separate files (if needed)
- [ ] No time-sensitive information
- [ ] Consistent terminology throughout
- [ ] Examples are concrete, not abstract
- [ ] File references one level deep
- [ ] Progressive disclosure used appropriately
- [ ] Workflows have clear steps

### Code and Scripts
- [ ] Scripts solve problems rather than punt to Claude
- [ ] Error handling is explicit and helpful
- [ ] No magic constants (all values justified)
- [ ] Required packages listed and verified available
- [ ] Scripts have clear documentation
- [ ] No Windows-style paths
- [ ] Validation/verification steps for critical operations
- [ ] Feedback loops for quality-critical tasks

### Testing
- [ ] At least 3 evaluations created
- [ ] Tested with target model(s)
- [ ] Tested with real usage scenarios
- [ ] Team feedback incorporated (if applicable)

---

## Platform-Specific Notes

### Claude.ai

**Skills Sharing:**
- **Individual users**: Custom skills uploaded personally are private to that account
- **Team & Enterprise plans**: Organization Owners can provision skills organization-wide via Admin settings > Capabilities. These appear for all users with a team indicator and can be toggled on/off individually
- **Peer-to-peer sharing**: Not currently available—users cannot directly share skills with specific colleagues

**Network Access (Code Execution):**

Network access is controlled by organization admins (Team/Enterprise) or individual settings (Pro/Max):

| Setting | Description |
|---------|-------------|
| **Network egress OFF** | Pre-installed packages only, no internet. Maximum security. |
| **Package managers only** (Team default) | Access to npm, PyPI, GitHub, etc. Balances security with functionality. |
| **Package managers + specific domains** | Package managers plus custom domain allowlist configured by admin. |

- **Enterprise plans**: Code execution disabled by default; Owners enable in Admin settings
- **Team plans**: Enabled by default with package manager access
- **Pro/Max plans**: Users enable in Settings > Capabilities and can toggle "Allow limited network access"

### Claude API
- Custom Skills: Workspace-wide sharing (all workspace members can access)
- **No network access**: Skills cannot make external API calls
- **No runtime package installation**: Only pre-installed packages available
- Pre-configured dependencies only (check code execution tool docs)

### Claude Code
- Skills are filesystem-based:
  - Project: `.claude/skills/` (shared via git)
  - User: `~/.claude/skills/` (personal across projects)
  - Plugins: Bundled with installed Claude Code plugins
- **Full network access**: Same as any program on user's computer
- Can share via version control or plugins
- Global package installation discouraged (install locally to avoid interfering with user's computer)

---

---

## Modular Architecture: Multiple Skills vs. Single Skill with Multiple Files

One of the most important architectural decisions when building Skills is whether to create **multiple separate Skills** or **a single comprehensive Skill with multiple files**. Both approaches are valid, and the choice depends on your use case.

### Architecture Overview

| Approach | Structure | Best For |
|----------|-----------|----------|
| **Multiple Skills** | Separate SKILL.md files, each a standalone capability | Independent, reusable capabilities that may be used in isolation |
| **Single Skill with References** | One SKILL.md + multiple reference files in subdirectories | Related workflows that share context and typically work together |

---

### Option A: Multiple Separate Skills

Create separate Skills when capabilities are **independent and reusable across different contexts**.

```
skills/
├── pdf-extract/
│   └── SKILL.md
├── pdf-forms/
│   └── SKILL.md
├── pdf-merge/
│   └── SKILL.md
└── excel-analysis/
    └── SKILL.md
```

#### Pros

| Advantage | Explanation |
|-----------|-------------|
| **Independent triggering** | Each Skill activates based on its own description; user asks for forms → only pdf-forms loads |
| **Smaller context footprint** | Only relevant Skill's SKILL.md loads (~5k tokens max), not unrelated capabilities |
| **Easier maintenance** | Update one Skill without affecting others; clear ownership boundaries |
| **Composability** | Claude can combine multiple Skills naturally: "Extract text from this PDF and analyze it in Excel" triggers both |
| **Selective provisioning** | Admins can enable/disable individual Skills for different teams |
| **Parallel development** | Teams can work on different Skills independently |

#### Cons

| Disadvantage | Explanation |
|--------------|-------------|
| **No shared context** | Each Skill is isolated; can't reference common schemas or configurations directly |
| **Duplicate content** | Common patterns may be repeated across multiple Skills |
| **Discovery overhead** | More Skills = more metadata in system prompt (~100 tokens each) |
| **Coordination complexity** | Explicit chaining requires user awareness or careful description writing |

#### Chaining Multiple Skills

Claude automatically chains multiple Skills when descriptions match the request:

```
User: "Extract the tables from this PDF and create an Excel report with charts"

→ Claude activates: pdf-extract (matches "extract tables from PDF")
→ Claude activates: excel-analysis (matches "Excel report with charts")
→ Both SKILL.md files load into context
→ Claude executes workflow using both
```

**Explicit chaining in prompts:**
```markdown
## Workflow: PDF to Excel Report

1. Use the pdf-extract skill to pull tables
2. Use the excel-analysis skill to generate report

Note: Both skills will be invoked automatically when user requests PDF-to-Excel workflows.
```

**Can output of one Skill trigger another?** 

Yes, but **indirectly**. Skills don't have programmatic triggers—Claude uses semantic understanding:

1. Skill A produces output (e.g., extracted data)
2. Claude evaluates what to do next
3. If the next step matches Skill B's description, Claude loads Skill B
4. This is **LLM-mediated chaining**, not rule-based

Example flow:
```
User: "Analyze this PDF and create a presentation"

Step 1: Claude sees "PDF" → loads pdf-extract skill
Step 2: Claude extracts content → produces markdown/data
Step 3: Claude sees "presentation" in original request → loads pptx skill
Step 4: Claude creates presentation using extracted content
```

---

### Option B: Single Skill with Multiple Files

Create one comprehensive Skill with subdirectories when capabilities are **tightly related and share context**.

```
clickhouse-expert/
├── SKILL.md                    # Main orchestrator with routing table
├── BACKEND-CLI.md              # CLI execution backend
├── BACKEND-MCP.md              # MCP execution backend
├── agents/
│   ├── overview/
│   │   ├── prompt.md
│   │   └── queries.sql
│   ├── memory/
│   │   ├── prompt.md
│   │   └── queries.sql
│   ├── merges/
│   │   ├── prompt.md
│   │   └── queries.sql
│   └── ... (15 total agents)
├── references/
│   └── audit-patterns.md
└── scripts/
    └── run-agent.sh
```

#### Pros

| Advantage | Explanation |
|-----------|-------------|
| **Shared context** | All sub-components can reference common schemas, patterns, conventions |
| **Unified orchestration** | SKILL.md acts as coordinator with routing tables and workflow logic |
| **Single trigger point** | One description triggers the whole system; internal routing is explicit |
| **Atomic deployment** | Entire capability ships as one unit; version control is simpler |
| **Deep specialization** | Can build sophisticated multi-agent systems within one Skill |
| **Efficient for related tasks** | User asking about "ClickHouse memory" doesn't need separate Skills |

#### Cons

| Disadvantage | Explanation |
|--------------|-------------|
| **SKILL.md always loads fully** | The main SKILL.md body (~5k tokens) loads when triggered, even if user only needs one sub-component. However, sub-files (agents/, references/) still load selectively. |
| **Higher maintenance burden** | Changes to SKILL.md affect entire system; harder to isolate issues |
| **Less reusable** | Sub-components can't be triggered independently outside this Skill |
| **Complex to understand** | New users must learn the internal structure and routing |
| **Single trigger point** | All sub-capabilities share one description; may trigger when not all are needed |

**Important clarification**: Progressive disclosure still applies within a Single Skill! Only SKILL.md loads on trigger; reference files and agent subdirectories load only when Claude explicitly reads them. In the ClickHouse example, asking about "memory issues" loads SKILL.md + `agents/memory/*` only—not the 14 other agents.

#### Chaining Within a Single Skill

Internal chaining is **explicit and controlled** via the SKILL.md orchestrator:

```markdown
## Coordinator Loop (from SKILL.md)

1. Start an artifact for the user's question
2. Run **wave 1**: `overview` (triage)
3. Run **wave 2**: pick 2-3 targeted agents from symptom table
4. Optional **wave 3**: deep dives if needed
5. Produce consolidated RCA report

## Symptom-to-Agent Mapping

| User Symptom | Agents to Run |
|--------------|---------------|
| "OOM" / "memory" | memory, reporting |
| "slow queries" | reporting, memory |
| "too many parts" | merges, ingestion, storage |
```

**How sub-components are loaded:**
```markdown
## Agent Files

Each agent has two files in `agents/<name>/`:
- `queries.sql` - SQL queries to execute
- `prompt.md` - Analysis prompt with severity rules

To run an agent:
1. Read `agents/<name>/queries.sql`
2. Execute queries via selected backend
3. Read `agents/<name>/prompt.md`
4. Analyze results using the prompt
```

This is **SKILL.md-mediated chaining**—the main file explicitly tells Claude which sub-files to read and in what order.

---

### Decision Framework: When to Use Which

| Scenario | Recommended Approach | Reason |
|----------|---------------------|--------|
| Independent tools (PDF, Excel, PPTX) | **Multiple Skills** | Each is useful alone; users may need only one |
| Domain-specific diagnostic system | **Single Skill** | Sub-components share schemas, need coordination |
| Team-specific workflows | **Multiple Skills** | Different teams enable different Skills |
| Complex multi-step analysis | **Single Skill** | Needs explicit orchestration and shared context |
| General-purpose utilities | **Multiple Skills** | Maximum reusability and composability |
| Compliance/audit workflows | **Single Skill** | Strict sequencing, unified reporting |

### Hybrid Approach

You can combine both patterns:

```
skills/
├── data-platform/                    # Comprehensive diagnostic Skill
│   ├── SKILL.md
│   ├── agents/
│   │   ├── clickhouse/
│   │   ├── postgres/
│   │   └── redis/
│   └── references/
├── pdf-processing/                   # Standalone utility Skill
│   └── SKILL.md
└── excel-reporting/                  # Standalone utility Skill
    └── SKILL.md
```

The data-platform Skill handles complex, related diagnostics internally, while PDF and Excel Skills remain independent utilities that can be composed with it.

---

### Cross-Skill Communication Patterns

**Verified: Cross-Skill Invocation Works on Claude.ai!**

Testing confirmed that one skill CAN trigger another skill on Claude.ai by including explicit instructions to invoke the other skill by name.

| Platform | Mechanism | Can Invoke Skill by Name? | How It Works |
|----------|-----------|---------------------------|--------------|
| **Claude Code** | `Skill` tool with `command: "name"` | Yes | Explicit tool call |
| **Claude.ai** | Instructions in SKILL.md | **Yes** | Claude reads the referenced SKILL.md |
| **API** | Instructions in SKILL.md | Likely yes (same as Claude.ai) | Untested but same architecture |

**How chaining works on Claude.ai:**
1. Skill A triggers based on user request
2. Skill A's instructions say "invoke skill-b-formatter"
3. Claude reads Skill B's SKILL.md file
4. Claude executes Skill B's instructions
5. Both skills contribute to the final output

Here are patterns for cross-skill coordination:

#### Pattern 1: Output-Based Triggering (Implicit)

Claude's semantic understanding chains Skills based on context:

```
User: "Analyze this database, create a report, and make a presentation"

Claude's internal process:
1. "database" → triggers data-analysis skill
2. Skill produces analysis data
3. "report" → triggers excel-reporting skill  
4. Skill produces Excel file
5. "presentation" → triggers pptx skill
6. Skill uses analysis for slides
```

#### Pattern 2: Explicit Workflow in User Prompt

User or system prompt defines the chain:

```
User: "Use the data-analysis skill first, then pass results to excel-reporting"

Claude:
1. Loads data-analysis SKILL.md
2. Executes analysis, produces output
3. Loads excel-reporting SKILL.md
4. Uses analysis output as input
```

#### Pattern 3: Coordinator Skill (All Platforms - Verified!)

**Tested and confirmed on Claude.ai**: A skill CAN invoke another skill by name in its instructions.

```markdown
---
name: skill-a-data-extractor
description: Extract and structure data from text. Use when user asks to 
             extract data, parse information, or analyze text content.
---

# Skill A: Data Extractor

## Instructions
1. Analyze the input text
2. Extract data into DATA_BLOCK format
3. **After extraction, invoke the `skill-b-formatter` skill to format results**

## IMPORTANT: After Extraction
After producing the DATA_BLOCK output, you MUST invoke the `skill-b-formatter` 
skill to format the results into a beautiful report.
```

**What happens when user says "Extract the data from this text":**
1. Skill A triggers (matches "extract data")
2. Claude reads Skill A's SKILL.md
3. Skill A's instructions say to invoke skill-b-formatter
4. Claude reads Skill B's SKILL.md  
5. Claude executes both skills' instructions
6. User gets formatted output without ever mentioning formatting

**Key syntax**: Use phrases like:
- "invoke the `skill-name` skill"
- "use the skill-name skill to..."
- "chain to skill-name for..."

#### Pattern 4: MCP + Skills Combination

MCP provides data access; Skills provide workflow expertise:

```
MCP Server: Provides database queries, file access
Skill: Provides analysis methodology, formatting rules

User: "Analyze our Q3 sales"
→ MCP fetches data from database
→ data-analysis Skill interprets results
→ excel-reporting Skill formats output
```

---

### Best Practices for Modular Architecture

1. **Start narrow, expand later**: Build single-purpose Skills first, combine into comprehensive Skills only when patterns emerge

2. **Use the 3-conversation rule**: If you chain the same Skills 3+ times, consider creating a coordinator Skill

3. **Keep shared context in references**: For Single-Skill architecture, put common schemas/patterns in `references/` subdirectory

4. **Write descriptions for composition**: Include phrases like "Use with excel-reporting for formatted output" in descriptions

5. **Test both isolated and combined**: Verify Skills work alone AND when composed with others

6. **Document internal routing**: For Single-Skill with sub-components, include clear routing tables in SKILL.md

7. **Consider admin needs**: Multiple Skills = granular control; Single Skill = simpler provisioning

---

## Resources

- [Official Documentation](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)
- [Best Practices Guide](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [GitHub Repository](https://github.com/anthropics/skills)
- [Engineering Blog](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- [Skills Cookbook](https://platform.claude.com/cookbook/skills-notebooks-01-skills-introduction)
- [Agent Skills Standard](https://agentskills.io)
- [Skills Explained: Skills vs Prompts, Projects, MCP, Subagents](https://claude.com/blog/skills-explained)
- [Extending Claude with Skills and MCP](https://claude.com/blog/extending-claude-capabilities-with-skills-mcp-servers)
