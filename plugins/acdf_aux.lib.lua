-- * Metronome IM *
--
-- This file is part of the Metronome XMPP server and is released under the
-- ISC License, please see the LICENSE file in this source package for more
-- information about copyright and licensing.

-- This library contains shared code for Access Control Decision Function.

local type = type;
local clone, error_reply = require "util.stanza".clone, require "util.stanza".error_reply;
local bare, section, split, t_remove =
	require "util.jid".bare, require "util.jid".section, require "util.jid".split, table.remove;
local is_contact_subscribed = require "util.rostermanager".is_contact_subscribed;

local hosts = hosts;

local function apply_policy(label, session, stanza, actions, check_acl)
	local breaks_policy;
	local from, to = stanza.attr.from, stanza.attr.to;
	if type(actions) == "table" then
		if actions.type and stanza.attr.type ~= actions.type then
			breaks_policy = true;
		elseif type(actions.host) == "table" then
			local _from, _to;
			if type(check_acl) == "table" then -- assume it's a MAM ACL request,
				from = section(check_acl.attr.from or session.full_jid, "host");
			end
			if actions.include_subdomains then
				if not check_acl then
					_from = from and section(from, "host"):match("%.([^%.].*)");
				else
					_from = from and from:match("%.([^%.].*)");
				end
				_to = to and section(to, "host"):match("%.([^%.].*)");
			else
				if not check_acl then _from = section(from, "host"); else _from = from; end
				_to = section(to, "host");
			end

			if check_acl then
				if _from ~= (actions.host[1] or actions.host[2]) or _to ~= (actions.host[1] or actions.host[2]) then
					breaks_policy = true;
				end
			else
				if _from ~= (actions.host[1] or actions.host[2]) and _to ~= (actions.host[1] or actions.host[2]) then
					breaks_policy = true;
				end
			end
		end
	elseif actions == "roster" then
		local from_node, from_host = split(from);
		local to_node, to_host = split(to);
		if from_node and hosts[from_host] then
			if not is_contact_subscribed(from_node, from_host, bare(to)) then breaks_policy = true; end
		elseif to_node and hosts[to_host] then
			if not is_contact_subscribed(to_node, to_host, bare(from)) then breaks_policy = true; end
		end
	end

	if breaks_policy then
		if not check_acl then
			module:log("warn", "%s message to %s was blocked because it breaks the provided security label policy (%s)",
				from or session.full_jid, to, label);
			session.send(error_reply(stanza, "cancel", "policy-violation", "Message breaks security label "..label.." policy"));
		end
		return true;
	end
end

local policy_cache = {};
local function get_actions(host, label)
	local host_object = hosts[host];
	if host_object then
		if not policy_cache[host] then policy_cache[host] = setmetatable({}, { __mode = "v" }); end
		local cache = policy_cache[host];
		if not cache[label] then
			cache[label] = host_object.events.fire_event("sec-labels-fetch-actions", label);
		end
		return cache[label];
	end
end

local function check_policy(label, jid, stanza, request_stanza)
	local host = jid_section(jid, "host");
	local actions = get_actions(host, label);
	if actions then
		return apply_policy(label, { full_jid = jid }, stanza, actions, request_stanza or true);
	end
end

local function censor_body(stanza)
	local _clone = clone(stanza);
	local body = _clone:get_child("body");
	if body then
		t_remove(body, 1);
		body:text("[You're not authorized to see this message content]");
	end
	return _clone;
end

return { apply_policy = apply_policy, censor_body = censor_body, check_policy = check_policy, get_actions = get_actions };