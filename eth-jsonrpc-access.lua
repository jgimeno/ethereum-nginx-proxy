local cjson = require('cjson')
local http = require "resty.http"
local ffi = require("ffi")
local account = ffi.load("/opt/nginx/account.so")

ffi.cdef([[
typedef struct { const char *p; ptrdiff_t n; } _GoString_;
typedef signed char GoInt8;
typedef unsigned char GoUint8;
typedef short GoInt16;
typedef unsigned short GoUint16;
typedef int GoInt32;
typedef unsigned int GoUint32;
typedef long long GoInt64;
typedef unsigned long long GoUint64;
typedef GoInt64 GoInt;
typedef GoUint64 GoUint;
typedef float GoFloat32;
typedef double GoFloat64;
typedef float _Complex GoComplex64;
typedef double _Complex GoComplex128;
typedef char _check_for_64_bit_pointer_matching_GoInt[sizeof(void*)==64/8 ? 1:-1];
typedef _GoString_ GoString;
typedef void *GoMap;
typedef void *GoChan;
typedef struct { void *t; void *v; } GoInterface;
typedef struct { void *data; GoInt len; GoInt cap; } GoSlice;
extern GoString DeriveSender(GoSlice p0);
]])

local function empty(s)
  return s == nil or s == ''
end

local function split(s)
  local res = {}
  local i = 1
  for v in string.gmatch(s, "([^,]+)") do
    res[i] = v
    i = i + 1
  end
  return res
end

local function contains(arr, val)
  for i, v in ipairs (arr) do
    if v == val then
      return true
    end
  end
  return false
end

-- parse conf
local blacklist, whitelist = nil
if not empty(ngx.var.jsonrpc_blacklist) then
  blacklist = split(ngx.var.jsonrpc_blacklist)
end
if not empty(ngx.var.jsonrpc_whitelist) then
  whitelist = split(ngx.var.jsonrpc_whitelist)
end

-- check conf
if blacklist ~= nil and whitelist ~= nil then
  ngx.log(ngx.ERR, 'invalid conf: jsonrpc_blacklist and jsonrpc_whitelist are both set')
  ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  return
end

-- get request content
ngx.req.read_body()

-- try to parse the body as JSON
local success, body = pcall(cjson.decode, ngx.var.request_body);
if not success then
  ngx.log(ngx.ERR, 'invalid JSON request')
  ngx.exit(ngx.HTTP_BAD_REQUEST)
  return
end

local method = body['method']
local version = body['jsonrpc']

-- check we have a method and a version
if empty(method) or empty(version) then
  ngx.log(ngx.ERR, 'no method and/or jsonrpc attribute')
  ngx.exit(ngx.HTTP_BAD_REQUEST)
  return
end

-- check the version is supported
if version ~= "2.0" then
  ngx.log(ngx.ERR, 'jsonrpc version not supported: ' .. version)
  ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  return
end

-- if whitelist is configured, check that the method is whitelisted
if whitelist ~= nil then
  if not contains(whitelist, method) then
    ngx.status  = ngx.HTTP_FORBIDDEN
    local jsonStr = '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"The method" .. method .. "does not exist/is not available"}}'
    ngx.header.content_type = "application/json; charset=utf-8"
    ngx.say(cjson.encode(jsonStr))
    return ngx.exit(ngx.HTTP_FORBIDDEN)
  end
end

-- if blacklist is configured, check that the method is not blacklisted
if blacklist ~= nil then
  if contains(blacklist, method) then
    ngx.status  = ngx.HTTP_FORBIDDEN
    local jsonStr = '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"The method" .. method .. "does not exist/is not available"}}'
    ngx.header.content_type = "application/json; charset=utf-8"
    ngx.say(cjson.encode(jsonStr))
    return ngx.exit(ngx.HTTP_FORBIDDEN)
  end
end

-- check whitelist address
if method == "eth_sendRawTransaction" then
    -- get address from request
    local data = body['params']
    if data[1] ~= nil then
        -- Get data from code
        txFromAddr = account.DeriveSender(data[1])
        ngx.log(ngx.ERR, "decoding data")
    end

    if txFromAddr ~= nil then
        local httpc = http.new()
        local res, err = httpc:request_uri("https://videocoin-alpha-dot-videocoin-183500.appspot.com/whitelist/", {
            method = "GET",
            keepalive_timeout = 60,
            keepalive_pool = 10,
            ssl_verify = false
        })

        if not res then
            ngx.log(ngx.ERR, "failed to request: ", err)
            ngx.exit(ngx.HTTP_BAD_REQUEST)
            return
        end

        local success, body = pcall(cjson.decode, res.body);
        if not success then
          ngx.log(ngx.ERR, 'Invalid body decoding')
          ngx.exit(ngx.HTTP_BAD_REQUEST)
          return
        end

        if not contains(body["whitelist"], txFromAddr) then
          local jsonStr = '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Address is not allowed"}}'
          ngx.header.content_type = "application/json; charset=utf-8"
          ngx.say(cjson.encode(jsonStr))
          return
        end
    else
        local jsonStr = '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Address is not allowed"}}'
        ngx.header.content_type = "application/json; charset=utf-8"
        ngx.say(cjson.encode(jsonStr))
        return ngx.exit(ngx.HTTP_FORBIDDEN)
    end

    return
end

return
