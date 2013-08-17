require 'celluloid'
require 'nokogiri'
require 'redis'
require 'shellwords'
require 'uri'
require 'securerandom'

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
    host = URI.parse(URI.escape(url)).host
    cmd = "curl -sfkL -A 'ArchiveTeam/1.5' #{Shellwords.shellescape(url)}"

    info "Running #{cmd}"
    doc = Nokogiri.HTML(`#{cmd}`)

    if !$?.success?
      if $?.exitstatus == 47
        warn "Infinite redirection detected for #{cmd}; stopping grab"
        return []
      else
        raise "Failed to get #{url} (curl status: #{$?})"
      end
    end

    links = (doc/'a').map { |e| e['href'] }.select do |href|
      href =~ %r{^(?:/|https?://)}
    end

    GrabberResult.new.tap do |gr|
      gr.url = url
      gr.links = links.map do |l|
        # URI.parse can't handle bookmarks or improperly escaped URLs, and
        # patch.com sites contain both.  We use a slightly less sophisticated
        # but more tolerant algorithm here.
        #
        # Is it absolute? If so, use it as is.
        if l =~ /^http/
          l
        else
          # Otherwise, expand the URL.
          "#{host}#{l}"
        end
      end

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
    patches = result.links.select { |l| l =~ /^http.*?\.patch\.com/ }

    if patches.length < 1
      info "[#@id] No *.patch.com URLs found for #{url}"
    else
      new = R.sadd(todo_key, patches)
      found = R.sunionstore(host_key, host_key, todo_key)

      info "[#@id] #{new} new URLs on #{url}, #{found} URLs total"
    end

    delay = gen_delay
    info "[#@id] Waiting #{delay} seconds"
    sleep delay
    true  # for now, anyway
  end

  def gen_delay
    rand(42) + 60
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
