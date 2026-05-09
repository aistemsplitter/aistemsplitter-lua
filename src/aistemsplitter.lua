local json = require("dkjson")

local DEFAULT_BASE_URL = "https://api.aistemsplitter.org/v1"

local Client = {}
Client.__index = Client

local M = {
  DEFAULT_BASE_URL = DEFAULT_BASE_URL,
}

local function trim_right_slash(value)
  return (value:gsub("/+$", ""))
end

local function encode_path(value)
  return tostring(value):gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end)
end

local function merge_headers(left, right)
  local result = {}
  for key, value in pairs(left or {}) do
    result[key] = value
  end
  for key, value in pairs(right or {}) do
    result[key] = value
  end
  return result
end

local function decode_response(response)
  local payload, _, decode_error = json.decode(response.body or "{}")
  if not payload then
    return nil, {
      status = response.status or 0,
      code = "INVALID_JSON",
      message = decode_error or "Invalid JSON response",
    }
  end

  if response.status >= 200 and response.status < 300 and payload.success == true then
    return payload.data, nil
  end

  if payload.success == false and payload.error then
    return nil, {
      status = response.status,
      code = payload.error.code or "API_ERROR",
      message = payload.error.message or "AIStemSplitter API request failed",
      details = payload,
    }
  end

  return nil, {
    status = response.status,
    code = "HTTP_ERROR",
    message = "AIStemSplitter API request failed with status " .. tostring(response.status),
    details = payload,
  }
end

local function default_transport(method, url, headers, body)
  local ltn12 = require("ltn12")
  local transport = url:match("^https://") and require("ssl.https") or require("socket.http")
  local chunks = {}
  local request = {
    url = url,
    method = method,
    headers = headers,
    sink = ltn12.sink.table(chunks),
  }
  if body then
    request.source = ltn12.source.string(body)
    request.headers["content-length"] = tostring(#body)
  end

  local _, status, response_headers = transport.request(request)
  return {
    status = status or 0,
    headers = response_headers or {},
    body = table.concat(chunks),
  }
end

local function default_sleep(milliseconds)
  local socket = require("socket")
  socket.sleep(milliseconds / 1000)
end

function M.new(config)
  config = config or {}
  if not config.api_key or config.api_key == "" then
    error("AIStemSplitter API key is required", 2)
  end

  return setmetatable({
    api_key = config.api_key,
    base_url = trim_right_slash(config.base_url or DEFAULT_BASE_URL),
    transport = config.transport or default_transport,
    sleep = config.sleep or default_sleep,
  }, Client)
end

function Client:request(method, path, body, extra_headers)
  local headers = merge_headers({
    Accept = "application/json",
    Authorization = "Bearer " .. self.api_key,
  }, extra_headers)
  local encoded_body = nil
  if body ~= nil then
    headers["Content-Type"] = "application/json"
    encoded_body = json.encode(body)
  end

  local response = self.transport(method, self.base_url .. path, headers, encoded_body)
  return decode_response(response)
end

function Client:get_credits()
  return self:request("GET", "/credits")
end

function Client:create_upload(request)
  return self:request("POST", "/audio/uploads", {
    filename = request.filename,
    contentType = request.content_type,
    contentLength = request.content_length,
  })
end

function Client:upload_audio(request)
  local upload, err = self:create_upload({
    filename = request.filename,
    content_type = request.content_type,
    content_length = request.content_length or #request.data,
  })
  if err then
    return nil, err
  end

  local headers = merge_headers(upload.uploadHeaders, {
    ["Content-Type"] = request.content_type,
  })
  local response = self.transport("POST", upload.uploadUrl, headers, request.data)
  local payload, _, decode_error = json.decode(response.body or "{}")
  if not payload then
    return nil, {
      status = response.status or 0,
      code = "INVALID_JSON",
      message = decode_error or "Invalid JSON response",
    }
  end
  if response.status < 200 or response.status >= 300 or payload.success ~= true then
    return nil, {
      status = response.status,
      code = payload.error or "UPLOAD_ERROR",
      message = payload.message or payload.error or "Upload failed",
      details = payload,
    }
  end

  local input = {
    type = "uploaded_file",
    uploadId = upload.uploadId,
    fileUrl = payload.data.url,
    storageKey = payload.data.key,
  }

  return {
    uploadId = upload.uploadId,
    fileUrl = payload.data.url,
    storageKey = payload.data.key,
    expiresAt = upload.expiresAt,
    input = input,
  }, nil
end

function Client:create_split(request, options)
  options = options or {}
  local headers = {}
  if options.idempotency_key then
    headers["Idempotency-Key"] = options.idempotency_key
  end
  return self:request("POST", "/audio/splits", request, headers)
end

function Client:get_split(split_id)
  return self:request("GET", "/audio/splits/" .. encode_path(split_id))
end

function Client:wait_for_split(split_id, options)
  options = options or {}
  local timeout_ms = options.timeout_ms or 300000
  local interval_ms = options.interval_ms or 2000
  local deadline = os.clock() + timeout_ms / 1000

  while true do
    local split, err = self:get_split(split_id)
    if err then
      return nil, err
    end
    if split.status == "succeeded" or split.status == "failed" then
      return split, nil
    end
    if os.clock() >= deadline then
      return nil, {
        status = 0,
        code = "TIMEOUT",
        message = "Timed out waiting for split " .. tostring(split_id),
      }
    end
    self.sleep(math.min(interval_ms, math.max(0, math.floor((deadline - os.clock()) * 1000))))
  end
end

return M
