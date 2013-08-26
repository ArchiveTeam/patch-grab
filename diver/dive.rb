require 'nokogiri'
require 'mechanize'
require 'redis'
require 'celluloid'

class Diver
  include Celluloid
  include Celluloid::Logger

  def initialize
    @agent = Mechanize.new { |agent| agent.user_agent_alias = 'Linux Firefox' }
    @r_working = Redis.new(:port => 6379)
    @r_incoming = Redis.new(:port => 6380)
  end

  def dive(url, parent_sets = [], level = 0)
    key = "#{url}-state"

    begin
      base_uri = URI.parse(url)
      host = base_uri.host
    rescue URI::InvalidURIError
      error "(#{level}) #{url} is not a valid URI"
    end

    begin
      @agent.get(url) do |page|
        hrefs = page.links.map { |l| l.href }

        results = hrefs.each_with_object([]) do |href, res|
          begin
            uri = URI.parse(href)
            if !uri.absolute?
              uri = URI.join(base_uri, href)
            end

            if uri.host == host
              res << uri.to_s
            end
          rescue URI::InvalidURIError
            shortened_href = href.to_s.length > 32 ? "#{href[0..31]}..." : href

            if shortened_href.to_s.length == 0
              # meh, don't care
            else
              warn "(#{level}) #{shortened_href} is not a valid URI; skipping"
            end
          end
        end

        # Strip out anchors -- we don't need them
        results.map! { |r| r.sub(/\#.*$/, '') }
        
        # Normalize trailing slashes
        results.map! { |r| r.sub(/\/$/, '') }

        # Make unique for this set
        results.uniq!

        # Remove ones that we've already seen
        @r_working.sadd(key, results)
        @r_working.sdiffstore(key, key, 'done')

        # Remove ones that we've already added to incoming
        @r_working.sdiffstore(key, key, 'new_incoming')

        # Remove ones that are in the parent sets
        if !parent_sets.empty?
          parents_key = "#{key}-parents"
          @r_working.sunionstore(parents_key, parent_sets)
          @r_working.sdiffstore(key, key, parents_key)
          @r_working.del(parents_key)
        end

        # Is there anything new?
        sz = @r_working.scard(key)

        the_next_key = "#{key}-next"

        if sz > 0
          info "(#{level}) Found #{sz} new URLs on #{url}"
          # Okay, add them to the incoming set, and dive down each one
          @r_incoming.sadd('incoming', @r_working.smembers(key))
          @r_working.sadd('new_incoming', @r_working.smembers(key))
          @r_working.sadd(the_next_key, @r_working.smembers(key))
        else
          info "(#{level}) Nothing new for #{url}"
        end

        next_sz = @r_working.scard(the_next_key)

        if next_sz > 0
          info "(#{level}) Tracing #{next_sz} children URLs"

          @r_working.smembers(the_next_key).each do |url|
            dive(url, parent_sets + [key], level + 1)
            @r_working.srem(the_next_key, url)
          end
        end
      end
    rescue Mechanize::ResponseCodeError => e
      if e.response_code.to_i == 420
        error "(#{level}) Rate limiting detected; waiting one hour and trying again"
        sleep 3600
        retry
      elsif e.response_code.to_i == 404
        warn "(#{level}) #{url} returned 404; skipping"
      else
        warn "(#{level}) #{url} returned unhandled response code #{r.response_code}; skipping"
      end
    end

    # Clean up when we're done
    @r_working.del key
  end
end

Diver.new.dive('http://loganville.patch.com/directory/arts-&-entertainment')
