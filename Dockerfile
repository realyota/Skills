FROM altinity/altinity-mcp:latest AS mcp

FROM oven/bun:debian
RUN bun install -g @openai/codex@latest
RUN bun install -g @anthropic-ai/claude-code@latest
RUN apt install -y curl clickhouse-client
COPY --from=mcp /bin/altinity-mcp /bin/altinity-mcp