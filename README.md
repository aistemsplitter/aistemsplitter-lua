# AIStemSplitter

[![Website](https://img.shields.io/badge/website-aistemsplitter.org-blue)](https://aistemsplitter.org)
[![Docs](https://img.shields.io/badge/docs-API-green)](https://aistemsplitter.org/developers/api)
[![OpenAPI](https://img.shields.io/badge/openapi-yaml-orange)](https://api.aistemsplitter.org/openapi.yaml)

Official Lua SDK for [AIStemSplitter](https://aistemsplitter.org), an AI-powered stem splitter that separates vocals, drums, bass, and other instruments from uploaded audio files or direct audio URLs.

## Links

- Homepage: https://aistemsplitter.org
- API docs: https://aistemsplitter.org/developers/api
- OpenAPI: https://api.aistemsplitter.org/openapi.yaml

## Features

- Vocal isolation and remover workflows
- Drum, bass, and instrumental stems
- Async API with webhook callbacks
- Pay-as-you-go credits

## Get an API Key

Sign up at [aistemsplitter.org](https://aistemsplitter.org) and use `AISTEMSPLITTER_API_KEY` in local examples.

## Install

```sh
luarocks install aistemsplitter
```

## Quickstart

```lua
local aistemsplitter = require("aistemsplitter")

local client = aistemsplitter.new({
  api_key = os.getenv("AISTEMSPLITTER_API_KEY"),
})

local credits, err = client:get_credits()
if err then error(err.message) end
print(credits.balance, credits.unit)

local split = assert(client:create_split({
  input = {
    type = "direct_url",
    url = "https://example.com/song.mp3",
  },
  stemModel = "6s",
}, { idempotency_key = "retry-001" }))

local result = assert(client:wait_for_split(split.id, {
  timeout_ms = 10 * 60 * 1000,
  interval_ms = 2000,
}))

print(result.status)
```

## Upload Then Split

```lua
local file = assert(io.open("song.mp3", "rb"))
local bytes = file:read("*a")
file:close()

local upload = assert(client:upload_audio({
  filename = "song.mp3",
  content_type = "audio/mpeg",
  data = bytes,
}))

local split = assert(client:create_split({
  input = upload.input,
  stemModel = "4s",
}))
```

## Smoke Example

```sh
AISTEMSPLITTER_API_KEY=ast_live_xxx lua examples/smoke.lua
```

Without `AISTEMSPLITTER_API_KEY`, the smoke example exits cleanly with setup instructions.

## Development

```sh
lua tests/client_test.lua
luarocks lint aistemsplitter-dev-1.rockspec
luarocks make aistemsplitter-dev-1.rockspec
```

Publishing to LuaRocks is blocked until the `aistemsplitter` LuaRocks account/package ownership and the `github.com/aistemsplitter/aistemsplitter-lua` repository are available.
