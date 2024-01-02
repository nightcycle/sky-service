#!/usr/bin/env bash
content_dir_path=$1
luau-lsp analyze --sourcemap="sourcemap.json" --ignore="Packages/**" --ignore="src/Server/NPC/Animate.server.lua" --ignore="**/Packages/**" --ignore="*.spec.luau" --ignore="out/**" --flag:LuauTypeInferIterationLimit=0 --flag:LuauCheckRecursionLimit=0 --flag:LuauTypeInferRecursionLimit=0 --flag:LuauTarjanChildLimit=0 --flag:LuauTypeInferTypePackLoopLimit=0 --flag:LuauVisitRecursionLimit=0 --definitions=types/globalTypes.d.lua --flag:LuauParseDeclareClassIndexer=true $content_dir_path
