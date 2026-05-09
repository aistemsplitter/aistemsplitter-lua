package.path = "./src/?.lua;" .. package.path

local aistemsplitter = require("aistemsplitter")

local function assert_equal(expected, actual, label)
  if expected ~= actual then
    error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function json_response(status, body)
  local json = require("dkjson")
  return {
    status = status,
    headers = { ["content-type"] = "application/json" },
    body = json.encode(body),
  }
end

local function test_get_credits_sends_bearer_auth()
  local requests = {}
  local client = aistemsplitter.new({
    api_key = "ast_test_123",
    transport = function(method, url, headers, body)
      table.insert(requests, { method = method, url = url, headers = headers, body = body })
      return json_response(200, {
        success = true,
        data = { balance = 6200, unit = "seconds" },
      })
    end,
  })

  local credits = assert(client:get_credits())

  assert_equal("GET", requests[1].method, "credits method")
  assert_equal("https://api.aistemsplitter.org/v1/credits", requests[1].url, "credits url")
  assert_equal("Bearer ast_test_123", requests[1].headers.Authorization, "auth header")
  assert_equal(6200, credits.balance, "credit balance")
  assert_equal("seconds", credits.unit, "credit unit")
end

local function test_create_split_sends_idempotency_key()
  local requests = {}
  local client = aistemsplitter.new({
    api_key = "ast_test_123",
    base_url = "https://api.example.test/v1/",
    transport = function(method, url, headers, body)
      table.insert(requests, { method = method, url = url, headers = headers, body = body })
      return json_response(200, {
        success = true,
        data = {
          id = "split_123",
          status = "queued",
          creditsUsed = 214,
          createdAt = "2026-05-03T10:20:30.000Z",
        },
      })
    end,
  })

  local split = assert(client:create_split({
    input = {
      type = "direct_url",
      url = "https://example.com/song.mp3",
    },
    stemModel = "6s",
  }, { idempotency_key = "retry-001" }))

  local json = require("dkjson")
  local body = assert(json.decode(requests[1].body))
  assert_equal("https://api.example.test/v1/audio/splits", requests[1].url, "split url")
  assert_equal("retry-001", requests[1].headers["Idempotency-Key"], "idempotency key")
  assert_equal("direct_url", body.input.type, "input type")
  assert_equal("https://example.com/song.mp3", body.input.url, "input url")
  assert_equal("split_123", split.id, "split id")
end

local function test_upload_audio_returns_split_input()
  local requests = {}
  local client = aistemsplitter.new({
    api_key = "ast_test_123",
    transport = function(method, url, headers, body)
      table.insert(requests, { method = method, url = url, headers = headers, body = body })
      if url:match("/audio/uploads$") then
        local json = require("dkjson")
        local payload = assert(json.decode(body))
        assert_equal("song.mp3", payload.filename, "upload filename")
        assert_equal("audio/mpeg", payload.contentType, "upload content type")
        assert_equal(5, payload.contentLength, "upload content length")
        return json_response(200, {
          success = true,
          data = {
            uploadId = "upl_123",
            uploadUrl = "https://upload.example.com",
            uploadHeaders = {
              ["X-Upload-Token"] = "token_123",
              ["X-Folder"] = "audio/api/key_123/upl_123",
            },
            expiresAt = "2026-05-03T10:25:30.000Z",
          },
        })
      end

      assert_equal("https://upload.example.com", url, "worker url")
      assert_equal("POST", method, "worker method")
      assert_equal("token_123", headers["X-Upload-Token"], "worker token")
      assert_equal("audio/mpeg", headers["Content-Type"], "worker content type")
      return json_response(200, {
        success = true,
        data = {
          url = "https://cdn.example.com/audio/api/key_123/upl_123/song.mp3",
          key = "audio/api/key_123/upl_123/song.mp3",
        },
      })
    end,
  })

  local upload = assert(client:upload_audio({
    filename = "song.mp3",
    content_type = "audio/mpeg",
    data = "12345",
  }))

  assert_equal(2, #requests, "request count")
  assert_equal("uploaded_file", upload.input.type, "uploaded input type")
  assert_equal("upl_123", upload.input.uploadId, "upload id")
  assert_equal("https://cdn.example.com/audio/api/key_123/upl_123/song.mp3", upload.input.fileUrl, "file url")
  assert_equal("audio/api/key_123/upl_123/song.mp3", upload.input.storageKey, "storage key")
end

local function test_get_split_fetches_split_by_id()
  local client = aistemsplitter.new({
    api_key = "ast_test_123",
    transport = function(method, url)
      assert_equal("GET", method, "get split method")
      assert_equal("https://api.aistemsplitter.org/v1/audio/splits/split_123", url, "get split url")
      return json_response(200, {
        success = true,
        data = {
          id = "split_123",
          status = "succeeded",
          stemModel = "6s",
          filename = "song.mp3",
          durationSeconds = 214,
          creditsUsed = 214,
          createdAt = "2026-05-03T10:20:30.000Z",
          updatedAt = "2026-05-03T10:22:01.000Z",
          stems = { vocals = "https://cdn.example.com/vocals.mp3" },
          error = nil,
        },
      })
    end,
  })

  local split = assert(client:get_split("split_123"))

  assert_equal("succeeded", split.status, "split status")
  assert_equal("https://cdn.example.com/vocals.mp3", split.stems.vocals, "vocals stem")
end

local function test_wait_for_split_polls_until_terminal_status()
  local attempts = 0
  local client = aistemsplitter.new({
    api_key = "ast_test_123",
    sleep = function() end,
    transport = function()
      attempts = attempts + 1
      return json_response(200, {
        success = true,
        data = {
          id = "split_123",
          status = attempts == 1 and "processing" or "succeeded",
          stemModel = "6s",
          filename = "song.mp3",
          durationSeconds = 214,
          creditsUsed = 214,
          createdAt = "2026-05-03T10:20:30.000Z",
          updatedAt = "2026-05-03T10:22:01.000Z",
          error = nil,
        },
      })
    end,
  })

  local split = assert(client:wait_for_split("split_123", { timeout_ms = 1000, interval_ms = 1 }))

  assert_equal(2, attempts, "poll attempts")
  assert_equal("succeeded", split.status, "terminal status")
end

local function test_api_errors_return_typed_error_table()
  local client = aistemsplitter.new({
    api_key = "bad_key",
    transport = function()
      return json_response(401, {
        success = false,
        error = {
          code = "UNAUTHORIZED",
          message = "Missing or invalid API key",
        },
      })
    end,
  })

  local result, err = client:get_credits()

  assert_equal(nil, result, "result")
  assert_equal("UNAUTHORIZED", err.code, "error code")
  assert_equal(401, err.status, "error status")
end

local tests = {
  test_get_credits_sends_bearer_auth,
  test_create_split_sends_idempotency_key,
  test_upload_audio_returns_split_input,
  test_get_split_fetches_split_by_id,
  test_wait_for_split_polls_until_terminal_status,
  test_api_errors_return_typed_error_table,
}

for _, test in ipairs(tests) do
  test()
end

print(#tests .. " tests passed")
