local json = require("json")
require("socket")
local https = require("ssl.https")
io.write("Content-Type: text/plain\nPragma: no-cache\n\n")

token = ""

function print_r (t)
        local print_r_cache={}
        local function sub_print_r(t,indent)
                if (print_r_cache[tostring(t)]) then
                        print(indent.."*"..tostring(t))
                else
                        print_r_cache[tostring(t)]=true
                        if (type(t)=="table") then
                                for pos,val in pairs(t) do
                                        if (type(val)=="table") then
                                                print(indent.."["..pos.."] => "..tostring(t).." {")
                                                sub_print_r(val,indent..string.rep(" ",string.len(pos)+8))
                                                print(indent..string.rep(" ",string.len(pos)+6).."}")
                                        elseif (type(val)=="string") then
                                                print(indent.."["..pos..'] => "'..val..'"')
                                        else
                                                print(indent.."["..pos.."] => "..tostring(val))
                                        end
                                end
                        else
                                print(indent..tostring(t))
                        end
                end
        end
        if (type(t)=="table") then
                print(tostring(t).." {")
                sub_print_r(t,"  ")
                print("}")
        else
                sub_print_r(t,"  ")
        end
        print()
end


function split(s, delimiter)
        result = {}
        for match in (s..delimiter:gsub("%%", "")):gmatch("(.-)"..delimiter) do
                table.insert(result, match)
        end
        return result
end

function trim(s)
        return s:gsub("^%s*(.-)%s*$", "%1")
end

function update_cookies(str)
        local segments = split(str, ";")
        for i, v in pairs(segments) do
                if v:find(",") then
                        for i, w in pairs(split(v, ",")) do
                                if w:find("=") then
                                        local kv = split(w, "=")
                                        local ck = trim(kv[1])
                                        local cv = trim(kv[2])
                                        if ck:lower() ~= "path" and ck:lower() ~= "expires" and ck:lower() ~= "max-age" then
                                                cookies_table[ck] = cv
                                        end
                                end
                        end
                else
                        if v:find("=") then
                                local kv = split(v, "=")
                                local ck = trim(kv[1])
                                local cv = trim(kv[2])
                                if ck:lower() ~= "path" and ck:lower() ~= "expires" and ck:lower() ~= "max-age" then
                                        cookies_table[ck] = cv
                                end
                        end
                end
        end
end

function cookies_string()
        local r = {}
        for i, v in pairs(cookies_table) do
                table.insert(r, i .. "=" .. v)
        end
        return table.concat(r, ";")
end

function make_query_string(t)
        local r = {}
        for i, v in pairs(t) do
                table.insert(r, i .. "=" .. v)
        end
        return table.concat(r, "&")
end

function https_get_json(link)
        local res = {}
        local req = {
                url = link,
                protocol = "tlsv1_2",
                verify = "none",
                sink = ltn12.sink.table(res)
        }
        local ok, code, header, http = https.request(req)
        res = json.decode(table.concat(res))
        if res["user_token"] ~= nil then token = res["user_token"] end
        return res
end

function https_post_json(link, data)
        local res = {}
        data["format"] = "json"
        data["user_token"] = token
        data = make_query_string(data)
        local req = {
                method = "POST",
                url = link,
                protocol = "tlsv1_2",
                verify = "none",
                source = ltn12.source.string(data),
                sink = ltn12.sink.table(res),
                headers = {
                        ["Content-Length"] = string.len(data),
                        ["Content-Type"] = "application/x-www-form-urlencoded"
                }
        }
        local ok, code, header, http = https.request(req);
        res = json.decode(table.concat(res))
        if res["user_token"] ~= nil then token = res["user_token"] end
        return res
end

function domain_judge(target, candidate)
        if (trim(candidate:lower()) == trim(target:lower())) then return true end
        local pos = trim(target:lower()):find(trim(candidate:lower()))
        if pos ~= nil then pos = pos - 1 end
        if pos == string.len(target) - string.len(candidate) then return true end
        return false
end

local _GET = {}

for k, v in pairs(split(os.getenv("QUERY_STRING"), "&")) do
                local kv = split(v, "=")
                _GET[kv[1]] = kv[2]
end

-- Replace with your own email and password
local my_email = ""
local my_password = ""
local my_domain = _GET["domain"]
local my_record = _GET["record"]
local my_value = _GET["value"]

local login_form = {
        login_email = my_email,
        login_password = my_password
}
https_post_json("https://api.dnspod.com/Auth", login_form)
print(token)
local domain_form = {
        type = "all"
}
local domains = (https_post_json("https://api.dnspod.com/Domain.List", domain_form))["domains"]
local my_domain_id, my_record_id
for k, v in ipairs(domains) do
        if domain_judge(my_domain, v["name"]) then
                print(v["name"])
                my_domain_id = v["id"]
                if trim(my_domain:lower()) == trim(v["name"]:lower()) then
                        my_record = "@"
                else
                        my_record = my_domain
                        my_record = my_record:gsub(v["name"], "")
                        my_record = my_record:gsub("^%.*(.-)%.*$", "%1")
                end
                break
        end
end

print(my_record)
if my_domain_id == nil then os.exit(0) end
local record_form = {
        domain_id = my_domain_id
}
local records = (https_post_json("https://api.dnspod.com/Record.List", record_form))["records"]

for k, v in ipairs(records) do
        if (my_record):lower() == v["name"]:lower() then
                print(v["name"])
                my_record_id = v["id"]
                break
        end
end

if my_record_id == nil then
        local create_form = {
                domain_id = my_domain_id,
                sub_domain = my_record,
                record_type = "TXT",
                record_line = "default",
                value = ""
        }
        print_r(https_post_json("https://api.dnspod.com/Record.Create", create_form))
end

local modify_form = {
        record_id = my_record_id,
        domain_id = my_domain_id,
        sub_domain = my_record,
        -- record_type = "TXT",
        record_line = "default",
        value = my_value
}
print_r(https_post_json("https://api.dnspod.com/Record.Ddns", modify_form))