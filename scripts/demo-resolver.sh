#!/usr/bin/env bash
# Fake workspace resolver for scripts/demo.sh: prints the key -> workspace
# mapping the demo wrote, using the resolver interface in docs/cache-contract.md.
cat "${CCO_CACHE_DIR:?}/demo-tree" 2>/dev/null
