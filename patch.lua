function os.capture(cmd)
  local f = assert(io.popen(cmd, 'r'), "unable to start "..cmd)
  local s = f:read('*a')
  f:close()
  return s
end

local url_host = "http://quilt.at.ninjawedding.org:81"
local creds = "ArchiveTeam:3boiqJvshItPBa66"

-- The httploop_result callback seems to get called on every URL we've *ever*
-- seen when working through the manifest.  To prevent work explosion, we keep
-- track of URLs we've already seen.
local seen = {}

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
	local url = urlpos.url.url

	if (seen[url]) then
		return false
	else
		return true
	end
end

wget.callbacks.httploop_result = function(url, err, http_status)
	local code = http_status.statcode

	-- HTTP 420 means that we're rate-limited.  We have to abort.
	if (code == 420) then
		io.stdout:write("Server returned status "..code.."; you've exceeded rate limits.\n")
		io.stdout:write("You may want to move to another IP.  Exiting...\n")
		io.stdout:flush()

		return wget.actions.ABORT
	end

	-- On code 2xx, extract URLs and send them to the URL storage
	-- mechanism.  We only do this for things that look like HTML files.
	if (code >= 200 and code <= 299) then
		local loc = http_status.local_file
		local out = os.capture("file "..loc)

		-- We've seen this URL; let's not see it again.
		seen[url.url] = true

		if (string.find(out, "HTML") ~= nil) then
			-- OK, this is probably an HTML document.  Get all of its links.
			io.stdout:write("Scraping "..url.url.." for links\n")
			io.stdout:flush()

			local ret = os.execute("python scrape.py "..loc.. " | curl -f -X POST -m 10 --basic -u '"..creds.."' --data-binary @- "..url_host)

			io.stdout:write("Sent links for "..url.url.." to "..url_host.."\n")
			io.stdout:flush()

			-- If we can't contact the endpoint, log the error and continue
			-- working.  Chances are some other agent will eventually see
			-- the URLs that we didn't get.
			if (ret ~= 0) then
				io.stdout:write("Warning: URL scraper failed with code "..ret.."\n")
				io.stdout:write("Continuing grab, but please report this failure to someone in #cabbagepatch on EFnet\n")
				io.stdout:flush()
			end

			-- Finally, check whether or not this was a *.patch.com URL.
			-- If it was, it's subject to rate limits, and we need to wait
			-- a bit.  Patch.com's asset servers don't seem to contribute
			-- to rate limits, so we just go through those as fast as we
			-- can.
			local theurl = url.url

			if (string.match(theurl, '%.patch.com')) then
				wait = math.random(5, 8)
				io.stdout:write("Waiting "..wait.." seconds after fetching "..theurl.."\n")
				os.execute('sleep '..wait)
			end

			-- OK, we're done.  Fall through.
		end
	end

	-- Let wget do its thing.
	return wget.actions.NOTHING
end
