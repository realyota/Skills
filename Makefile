# Skills Build System
# Creates zip files for all skill directories (directories containing SKILL.md)

SKILLS_DIR := $(shell pwd)
BUILD_DIR := $(SKILLS_DIR)/releases
SKILL_DIRS := $(shell find altinity-expert-clickhouse/skills -maxdepth 2 -name "SKILL.md" -exec dirname {} \; | sort)
SKILL_ZIPS := $(foreach dir,$(SKILL_DIRS),$(BUILD_DIR)/$(notdir $(dir)).zip)

.PHONY: all clean list help audit audit-all audit-conditional audit-codex audit-claude audit-gemini audit-focus

all: $(BUILD_DIR) $(SKILL_ZIPS)
	@echo "Built $(words $(SKILL_ZIPS)) skill packages in $(BUILD_DIR)/"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

define ZIP_template
$(BUILD_DIR)/$(notdir $(1)).zip: $(1)/SKILL.md
	@echo "Packaging $(notdir $(1))..."
	@cd $(1) && zip -r $(BUILD_DIR)/$(notdir $(1)).zip . -x "*.DS_Store" -x "*__MACOSX*" -x "*.git*"
endef

$(foreach dir,$(SKILL_DIRS),$(eval $(call ZIP_template,$(dir))))

clean:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)

list:
	@echo "Skills found:"
	@$(foreach dir,$(SKILL_DIRS),echo "  - $(notdir $(dir)) ($(dir))";)

help:
	@echo "Skills Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make          Build all skill zip files"
	@echo "  make all      Same as 'make'"
	@echo "  make clean    Remove all built zip files"
	@echo "  make list     List all detected skills"
	@echo "  make help     Show this help"
	@echo ""
	@echo "Output: releases/<skill-name>.zip"
	@echo ""
	@echo "Audit (production) targets:"
	@echo "  make audit             Run conditional audit (codex by default)"
	@echo "  make audit-all         Run full audit (all modules)"
	@echo "  make audit-conditional Run conditional audit"
	@echo "  make audit-codex       Run conditional audit with Codex"
	@echo "  make audit-claude      Run conditional audit with Claude"
	@echo "  make audit-gemini      Run conditional audit with Gemini (stub)"
	@echo "  make audit-focus FOCUS_SKILL=altinity-expert-clickhouse-memory"

# ============================================================
# Audit automations
# ============================================================

audit: audit-conditional

audit-all:
	AUDIT_MODE=all LLM_PROVIDER=${LLM_PROVIDER:-codex} CODEX_MODEL=$(CODEX_MODEL) CLAUDE_MODEL=$(CLAUDE_MODEL) GEMINI_MODEL=$(GEMINI_MODEL) ./automations/scripts/audit.sh

audit-conditional:
	AUDIT_MODE=conditional LLM_PROVIDER=${LLM_PROVIDER:-codex} CODEX_MODEL=$(CODEX_MODEL) CLAUDE_MODEL=$(CLAUDE_MODEL) GEMINI_MODEL=$(GEMINI_MODEL) ./automations/scripts/audit.sh

audit-codex:
	LLM_PROVIDER=codex ./automations/scripts/audit.sh

audit-claude:
	LLM_PROVIDER=claude ./automations/scripts/audit.sh

audit-gemini:
	LLM_PROVIDER=gemini ./automations/scripts/audit.sh

audit-focus:
	@if [ -z "${FOCUS_SKILL}" ]; then echo "FOCUS_SKILL is required"; exit 1; fi
	LLM_PROVIDER=${LLM_PROVIDER:-codex} CODEX_MODEL=$(CODEX_MODEL) CLAUDE_MODEL=$(CLAUDE_MODEL) GEMINI_MODEL=$(GEMINI_MODEL) ./automations/scripts/focus.sh "$(FOCUS_SKILL)"
