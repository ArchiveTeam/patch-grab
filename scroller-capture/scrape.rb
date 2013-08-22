#!/usr/bin/env ruby

require 'capybara'
require 'capybara/poltergeist'
require 'uri'

PHANTOMJS_PATH = File.expand_path('../vendor/phantomjs/bin/phantomjs', __FILE__)

$stderr.puts "Running PhantomJS from #{PHANTOMJS_PATH}"

Capybara.register_driver(:poltergeist) do |app|
  Capybara::Poltergeist::Driver.new(app, {
    :phantomjs => PHANTOMJS_PATH,
    :phantomjs_options => [ '--proxy=http://127.0.0.1:8000' ]
  })
end

Capybara.default_driver = :poltergeist

class Scraper
  include Capybara::DSL

  def row_count
    all('.feed-row').length
  end

  def go(url)
    $stderr.puts "Working on #{url}"
    visit url
    found = row_count

    loop do
      $stderr.puts "#{found} rows found"

      if has_css?('a.show_more')
        find('a.show_more').click

        loop do
          len = row_count

          if len > found
            found = len
            sleep 1 + rand(5)
            break
          else
            sleep 0.5
          end
        end
      else
        $stderr.puts "Expanding hidden sections for kicks"
        all('.more_text').each(&:click)

        $stderr.puts "Waiting 5 seconds to let things settle down"
        sleep 5

        $stderr.puts "No more pages found, dumping links"
        break all('a').map { |a| a[:href] }
      end
    end
  end
end

links = Scraper.new.go(ARGV[0])

File.open(ARGV[1], 'w') do |f|
  links.each { |l| f.puts(l) }
end
