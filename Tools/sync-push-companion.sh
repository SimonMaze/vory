#!/usr/bin/env bash
# server/hermes-push is the source of truth; the app bundles a copy (a unit test checks parity).
set -e; cd "$(dirname "$0")/.."
cp server/hermes-push/hermes_push.py server/hermes-push/plugin/vory-push/hermes_push.py
cp server/hermes-push/hermes_push.py server/hermes-push/install.sh Vory/Resources/hermes-push/
mkdir -p Vory/Resources/hermes-push/plugin/skills/vory-cards
cp server/hermes-push/plugin/vory-push/plugin.yaml server/hermes-push/plugin/vory-push/__init__.py Vory/Resources/hermes-push/plugin/
cp server/hermes-push/plugin/vory-push/skills/vory-cards/SKILL.md Vory/Resources/hermes-push/plugin/skills/vory-cards/SKILL.md
echo synced
