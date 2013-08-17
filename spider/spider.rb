require 'celluloid'
require 'nokogiri'
require 'redis'
require 'uri'
require 'securerandom'
require 'net/http'

# URI.parse can't handle bookmarks or improperly escaped URLs, and
# patch.com sites contain both.  We use a slightly less sophisticated
# but more tolerant algorithm here.
#
# Is it absolute? If so, use it as is.
def absolutize(host, proto, url)
  if url =~ /^http/
    url
  else
    # Otherwise, expand the URL.
    "#{proto}://#{host}#{url}"
  end
end

seed = ARGV[0]
R = Redis.new

if !seed
  puts "Usage:    #$0 SEED_URL"
  puts "Example:  #$0 http://agourahills.patch.com"
  exit 1
end

class GrabberResult < Struct.new(:url, :links)
end

class Grabber
  include Celluloid
  include Celluloid::Logger

  def get(url)
    limit = 5
    tries = 3

    resp = loop do
      info "GET #{url}"

      begin
        tries -= 1
        resp = Net::HTTP.get_response(URI(url))

        uri = URI.parse(URI.escape(url))
        host = uri.host
        proto = uri.scheme

        case resp
        when Net::HTTPSuccess then
          break resp
        when Net::HTTPClientError then
          if resp.code == '420' then
            fatal "GET #{url} responsed with rate-limit error"
            fatal resp.body.inspect
            fail "Rate-limited; restart later"
          elsif resp.code == '404'
            warn "GET #{url} returned 404; returning empty set"
            break
          else
            error "GET #{url} returned #{resp.code}; returning empty set"
            break
          end
        when Net::HTTPRedirection then
          if limit == 0
            error "GET #{url} exceeded redirection limit; returning empty set"
            break
          else
            warn "#{url} -> #{resp['location']}"
            url = absolutize(host, proto, resp['location'])
            limit -= 1
          end
        when Net::HTTPServerError then
          error "GET #{url} returned #{resp.code}; returning empty set"
          break
        else
          warn "GET #{url} returned #{resp.code}, which is unhandled; returning empty set"
          break
        end
      rescue EOFError, Errno::ECONNRESET, Errno::ETIMEDOUT => e
        if tries > 0
          error "Got #{e.class} on GET #{url}, retrying #{tries} times"
          retry
        else
          error "Got #{e.class} on GET #{url}; returning empty set"
          break
        end
      end
    end

    if !resp
      return GrabberResult.new.tap { |gr| gr.url = url; gr.links = [] }
    end

    doc = Nokogiri.HTML(resp.body)

    links = (doc/'a').map { |e| e['href'] }.select do |href|
      href =~ %r{^(?:/|https?://)}
    end

    GrabberResult.new.tap do |gr|
      gr.url = url

      uri = URI.parse(URI.escape(url))
      host = uri.host
      proto = uri.scheme

      gr.links = links.map { |l| absolutize(host, proto, l) }

      if gr.links.length == 0
        warn "Found zero links for #{url}, which is really bizarre"
        warn doc.inspect
      else
        info "Found #{gr.links.length} links on #{url}"
      end
    end
  end
end

class Aggregator
  include Celluloid
  include Celluloid::Logger

  def initialize
    @id = SecureRandom.urlsafe_base64(8)
  end

  def get(url, host_key, todo_key)
    result = Grabbers.future.get(url).value
    patches = result.links.select { |l| l =~ %r{\Ahttps?://[^\.]+?\.patch\.com/} }

    if patches.length < 1
      info "[#@id] No *.patch.com URLs found for #{result.url}"
    else
      new = R.sadd(todo_key, patches)
      found = R.sunionstore(host_key, host_key, todo_key)

      info "[#@id] #{new} new URLs on #{result.url}, #{found} URLs total"
    end

    delay = gen_delay
    info "[#@id] Waiting #{delay} seconds"
    sleep delay
    true  # for now, anyway
  end

  def gen_delay
    rand(60) + 72
  end
end

Grabbers = Grabber.pool
Aggregators = Aggregator.pool

# Keys we use:
#
# patch.com       - the full set of links for all patch.com sites
# patch.com:todo  - links pending examination
# patch.com:eval  - links being evaluated

host_key = "patch.com".freeze
todo_key = "patch.com:todo".freeze
eval_key = "patch.com:eval".freeze 
Celluloid.logger.info "Moving #{eval_key} back to #{todo_key}"
R.sunionstore todo_key, todo_key, eval_key
R.del eval_key

Celluloid.logger.info "#{R.scard(todo_key)} URLs in #{todo_key}"

if [host_key, todo_key, eval_key].none? { |k| R.sismember(k, seed) }
  Celluloid.logger.info "Adding #{seed} to #{todo_key}"
  R.sadd(todo_key, seed)
end

loop do
  count = [R.scard(todo_key), 8].min

  Celluloid.logger.info "Beginning evaluation of #{count} URLs"
  count.times { R.smove(todo_key, eval_key, R.srandmember(todo_key)) }

  if count == 0
    if R.exists(todo_key) && R.exists(eval_key)
      Celluloid.logger.info "Crawl completed"
      break
    else
      Celluloid.logger.info "Adding #{seed} for evaluation"
      R.sadd(eval_key, seed)
    end
  end

  futures = R.smembers(eval_key).map { |k| [k, Aggregators.future.get(k, host_key, todo_key)] }
  
  futures.each do |k, f|
    if f.value
      R.srem eval_key, k
    else
      Celluloid.logger.info "Retrieval of #{k} failed; leaving it in the pending set"
    end
  end
end
