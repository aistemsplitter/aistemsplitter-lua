package.path = "./src/?.lua;" .. package.path

local aistemsplitter = require("aistemsplitter")

local api_key = os.getenv("AISTEMSPLITTER_API_KEY")

if not api_key or api_key == "" then
  print("Set AISTEMSPLITTER_API_KEY to run the smoke example.")
  os.exit(0)
end

local client = aistemsplitter.new({ api_key = api_key })
local credits, err = client:get_credits()
if err then
  error(err.message)
end

print("AIStemSplitter credits: " .. tostring(credits.balance) .. " " .. credits.unit)
