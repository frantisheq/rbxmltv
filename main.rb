#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'date'
require 'time'
require 'optparse'
require 'optparse/time'
require 'ostruct'
require 'pp'
require 'nokogiri-happymapper'
require 'roman-numerals'
require 'net/http'
require 'open-uri'
require 'mechanize'
require 'days_and_times'
require 'ruby-progressbar'
require 'fileutils'
require 'unidecoder'
require 'xz'

# :nodoc:
class HTTPCache
  include FileUtils

  def initialize(base_dir)
    @base_dir   = base_dir
  end

  def get(url, key)
    cached_path = @base_dir + '/' + key
    if File.exist?(cached_path)
      IO.read(cached_path)
    else
      agent = Mechanize.new
      begin
        resp = agent.get(url)
      rescue Mechanize::ResponseCodeError => e
        warn e.message
        resp = agent.get('http://www.google.com')
      end
      data = resp.body

      File.open(cached_path, 'w') do |f|
        f.puts data
      end
      data
    end
  end

  def clean
    require 'date'

    progress_bar = ProgressBar.create(format: "%a %p%% %b\u{15E7}%i %t", \
                                      progress_mark: ' ', \
                                      remainder_mark: "\u{FF65}", \
                                      title: 'Wiping old cache', \
                                      total: Dir[@base_dir + '/*-*'].count, \
                                      length: 60)

    Dir[@base_dir + '/*-*'].each do |f|
      progress_bar.increment
      file_date_name = f.gsub(/(.*)\-|.xml/, '')
      date = Time.strptime(file_date_name, '%Y%m%d')
      t = Time.parse(Time.now.strftime('%Y%m%d'))
      FileUtils.rm f if t > date
    end unless Dir[@base_dir + '/*-*'].nil?
  end
end

# :nodoc:
class OptparseExample
  include FileUtils

  CODES = %w[iso-2022-jp shift_jis euc-jp utf8 binary].freeze
  CODE_ALIASES = { 'jis' => 'iso-2022-jp', 'sjis' => 'shift_jis' }.freeze

  #
  # Return a structure describing the options.
  #
  def self.parse(args)
    # The options specified on the command line will be collected in *options*.
    # We set default values here.
    options = OpenStruct.new
    options.days = 7
    options.path = nil
    options.cache = File.expand_path(File.join(ENV['HOME'], '/.rbxmltv-cache'))

    opts = OptionParser.new do |opts|
      opts.banner = 'Usage: rbxmltv.rb [options]'

      opts.separator ''
      opts.separator 'Specific options:'

      # Mandatory argument.
      opts.on('-d', '--days n',
              'Build guide for n days. Defaults to 7') do |lib|
        options.days = lib
      end

      # Optional argument; multi-line description.
      opts.on('-o', '--output [PATH]',
              'Define output file name') do |ext|
        options.path = ext
      end

      # Optional argument; multi-line description.
      opts.on('-c', '--cache [PATH]',
              'Define cache directory') do |ca|
        options.cache = ca
      end

      opts.separator ''
      opts.separator 'Common options:'

      # No argument, shows at tail.  This will print an options summary.
      # Try it and see!
      opts.on_tail('-h', '--help', 'Show this message') do
        puts opts
        exit
      end

      # Another typical switch to print the version.
      opts.on_tail('--version', 'Show version') do
        puts OptionParser::Version.join('.')
        exit
      end
    end

    opts.parse!(args)
    options
  end
end

# :nodoc:
class Channels
  include HappyMapper

  tag 'a'
  attribute :id, String
  element :name, String, tag: 'n'
  element :logo, String, tag: 'o'
end

# :nodoc:
class Shows
  include HappyMapper

  tag 'p'
  attribute :o, String
  element :category, String, xpath: 't'
end

# :nodoc:
class Descriptions
  include HappyMapper

  tag 'a'
  element  :title, String, tag: 'n'
  element  :subtitle, String, tag: 'b'
  element  :desc, String, xpath: 'p/d'
  element  :category, String, xpath: 'i/t'
  has_many :genres, String, xpath: 'i/st/tt'
  element  :country, String, xpath: 'i/z'
  element  :length, String, xpath: 'i/d'
  element  :year, String, xpath: 'i/r'
  element  :rating, String, xpath: 'i/p'
  element  :start, String, xpath: 's/@o'
  element  :stop, String, xpath: 's/@d'
end

options = OptparseExample.parse(ARGV)

if options.path.nil?
  puts 'No output file defined'
  exit
end

unless Dir.exist? File.expand_path(options.path.gsub(%r{\/.*$}, ''))
  puts "Path '#{options.path.gsub(%r{\/.*$}, '')}' doesn't exist"
  exit
end

unless Dir.exist? File.expand_path(options.cache)
  puts "Cache directory '#{options.cache}' doesn't exist"
  exit
end

puts "Building guide for #{options.days} days:"

unless Dir.exist? File.expand_path(File.join(ENV['HOME'], '/.rbxmltv-cache'))
  Dir.mkdir(File.expand_path(File.join(ENV['HOME'], '/.rbxmltv-cache')))
end

# cleanup cache directory
HTTPCache.new(options.cache).clean

base_url = 'http://programandroid.365dni.cz/android/'
cachedir = options.cache

HTTPCache.new(cachedir).get(base_url + 'v5-tv.php?locale=cz', 'channels.xml')
channels_file = Nokogiri::XML File.read("#{cachedir}/channels.xml") do |content|
  content.strict.noblanks # .css("p[p='Ostatní'] item")
end

list = channels_file #.search('s p:contains("Slovenské")').map(&:parent)

list.xpath("//a[p!='Slovenské' and p!='České' and p!='Ostatní']").remove

wanted_channels = File.open("wanted_channels.xml", 'w')
wanted_channels.write(list.to_xml(:indent => 2))
wanted_channels.close

number_of_channels = Nokogiri::XML(File.read("wanted_channels.xml"))
                             .css('n').count

progress_bar = ProgressBar.create(format: "%a %p%% %b\u{15E7}%i %t", \
                                  progress_mark: ' ', \
                                  remainder_mark: "\u{FF65}", \
                                  title: 'Updating cache', \
                                  total: number_of_channels, \
                                  length: 60)

Channels.parse(File.read("wanted_channels.xml")).each do |channel|
  date = Time.now
  progress_bar.increment
  for i in 1..options.days.to_i do
    HTTPCache.new(cachedir).get(base_url + \
                                "v5-program.php?datum=#{date.strftime('%Y-%m-%d')}&id_tv=#{channel.id}", \
                                "#{channel.id}-#{date.strftime('%Y%m%d')}.xml")

    begin
      # counter += Nokogiri::XML(File.read("#{cachedir}/#{channel.id}-#{date.strftime('%Y%m%d')}.xml")).css('p').count
      Shows.parse(File.read("#{cachedir}/#{channel.id}-#{date.strftime('%Y%m%d')}.xml")).each do |show|
        HTTPCache.new(cachedir).get(base_url + "v5-porad.php?datum=#{show.o.gsub(%r{[^0-9]}, '')}&id_tv=#{channel.id}", \
                                               "#{channel.id}-#{show.o.gsub(%r{[^0-9]}, '')}.xml")
      end
    rescue
      # puts "error: #{channel.id} #{date.strftime('%Y%m%d')} #{show.o}"
      # FileUtils.rm "#{cachedir}/#{channel.id}-#{date.strftime('%Y%m%d')}.xml"
    end
    date += 1.day.to_f
  end
end

logo_address = channels_file.at_css('s')['loga']

progress_bar = ProgressBar.create(format: "%a %p%% %b\u{15E7}%i %t", \
                                  progress_mark: ' ', \
                                  remainder_mark: "\u{FF65}", \
                                  title: 'Parsing EPG', \
                                  total: number_of_channels, \
                                  length: 60)

builder = Nokogiri::XML::Builder.new(:encoding => 'utf-8') do
  tv '', "generator-info-name": "rbxmltv", "generator-info-url": "http://www.somesite.eu/" do
    Channels.parse(File.read("wanted_channels.xml")).each do |channel|
      channel '', "id": channel.id + '-' + channel.name.downcase.to_ascii.gsub(/\s|\./, '-').gsub(/\:|\(|\)|\!/, '').gsub(/\+/, 'plus') do
        display_name channel.name, "lang": 'cz'
        icon '', "src": logo_address + channel.logo
      end
    end

    Channels.parse(File.read("wanted_channels.xml")).each do |channel|
      date = Time.now
      progress_bar.title = channel.name
      progress_bar.increment

      # combine CT :D and CT Art
      channel.id = '804' if channel.id == '805'

      for i in 1..options.days.to_i do
        begin
          Shows.parse(File.read("#{cachedir}/#{channel.id}-#{date.strftime('%Y%m%d')}.xml")).each do |show|
            # bar2.advance
            description = Descriptions.parse(File.read("#{cachedir}/#{channel.id}-#{show.o.gsub(/[^0-9]/,'')}.xml"))
            credits = Nokogiri::XML(File.read("#{cachedir}/#{channel.id}-#{show.o.gsub(/[^0-9]/,'')}.xml")).css('i l')

            begin
              series = description.title.gsub(/\(.*$/, '').gsub(/\s*$/, '') \
                                  .match(/\s(?=[MDCLXVI])M*(C[MD]|D?C{0,3})(X[CL]|L?X{0,3})(I[XV]|V?I{0,3})$/) \
                                  .to_s.gsub(/\s/, '')
            rescue
              series = nil
            end

            episode = description.title.match(/\(\d*/).to_s.gsub(/\(/, '').to_i - 1 || 0
            if episode.to_s == '-1'
              episode = '0'
            end
            episodes = description.title.match(%r{\/\d*\)}).to_s.gsub(%r{\/|\)}, '')
            if episodes.to_s != ''
              episodes = '/' + episodes.to_s
            end

            description.title = description.title.gsub(/\s\(\d.*$/, '')
                                           .gsub(/#{series}\.?\s?$/, '')
                                           .gsub(/\s*$/, '') if description.category != 'film'

            # decimal_series = nil

            if series != ('' || nil) && episode != ('' || nil || '0') && description.category != 'film'
              decimal_series = RomanNumerals.to_decimal(series)
              show_episode = (decimal_series-1).to_s + '.' + episode.to_s + episodes.to_s + '.0/1'
            elsif series != ('' || nil) && episode == nil && show_category != 'film'
              decimal_series = RomanNumerals.to_decimal(series)
              show_episode = (decimal_series-1).to_s + '.' + '0.0/1'
            elsif series == ('' || nil) && episode != ('' || nil) && episodes != ('' || nil || '0') && show_category != 'film'
              show_episode = '0.' + episode.to_s + episodes.to_s + '.0/1'
            elsif series == ('' || nil) && episode == nil
              show_episode = nil
            elsif description.category == 'film'
              show_episode = nil
            else
              show_episode = nil
            end

            programme '', "start": description.start.gsub(/[^0-9]/,'') + ' +0200', \
                          "stop": description.stop.gsub(/[^0-9]/,'') + ' +0200', \
                          "channel": channel.id + '-' + channel.name.downcase.to_ascii.gsub(/\s|\./, '-').gsub(/\:|\(|\)|\!/, '').gsub(/\+/, 'plus') do
              title description.title.gsub(%r{\s(\(R\)|\/R\/|\(P\)|\/P\/)}, ''), "lang": 'cz'

              sub_title description.subtitle, "lang": 'cz' unless description.subtitle.nil?

              desc description.desc, "lang": 'cz' unless description.desc.nil?

              if show.category == 'Z'
                category 'Zprávy', "lang": 'cz'
                category 'News / Current affairs', "lang": 'en'
              end
              # puts Nokogiri::XML(File.read("#{cachedir}/#{channel.id}-#{date.strftime('%Y%m%d')}.xml")).xpath('//t')[i].text

              category description.category, "lang": 'cz' unless description.category.nil?

              case description.category
              when 'Dětem'
                category "Children's / Youth programmes", "lang": 'en'
              when 'Dokument'
                category 'Documentary', "lang": 'en'
              when 'Film'
                category 'Movie / Drama', "lang": 'en'
              # when 'Seriál'
              #   category 'Show / Game show', :"lang": 'en'
              when 'Sport'
                category 'Sports', "lang": 'en'
              when 'Zábava'
                category 'Show / Game show', "lang": 'en'
              end

              description&.genres.each do |g|
                category g.capitalize, "lang": 'cz'

                case g
                when 'dobrodružný'
                  category 'Adventure / Western / War', "lang": 'en'
                when 'western'
                  category 'Adventure / Western / War', "lang": 'en'
                when 'válečný'
                  category 'Adventure / Western / War', "lang": 'en'
                when 'komedie'
                  category 'Comedy', "lang": 'en'
                when 'historický'
                  category 'Serious / Classical / Religious / Historical movie / Drama', "lang": 'en'
                when 'drama'
                  category 'Serious / Classical / Religious / Historical movie / Drama', "lang": 'en'
                when 'psychologický'
                  category 'Serious / Classical / Religious / Historical movie / Drama', "lang": 'en'
                when 'romantický'
                  category 'Romance', "lang": 'en'
                when 'rodinný'
                  category 'Soap / Melodrama / Folkloric', "lang": 'en'
                when 'erotický'
                  category 'Adult movie / Drama', "lang": 'en'
                when 'pohádka'
                  category 'Cartoons / Puppets', "lang": 'en'
                when 'sci-fi'
                  category 'Science fiction / Fantasy / Horror', "lang": 'en'
                when 'fantasy'
                  category 'Science fiction / Fantasy / Horror', "lang": 'en'
                when 'horor'
                  category 'Science fiction / Fantasy / Horror', "lang": 'en'
                when 'krimi'
                  category 'Detective / Thriller', "lang": 'en'
                when 'mysteriozní'
                  category 'Detective / Thriller', "lang": 'en'
                when 'thriller'
                  category 'Detective / Thriller', "lang": 'en'
                end
              end

              length description.length, "units": 'minutes' unless description.length.nil?

              date description.year unless description.year.nil?

              description.country.split(/\/|\,\s/).each do |g|
                country g, :"lang" => "cz"
              end if description.country != nil

              episode_num show_episode, "system": 'xmltv_ns' unless show_episode.nil?

              rating '' do value description.rating end unless description.rating.nil?

              premiere if description.title =~ %r{\s(\(P\)|\/P\/)}

              previously_shown if description.title =~ %r{\s(\(R\)|\/R\/)}

              credits '' do
                credits.css('o[t="r"] j')&.collect.each do |d|
                  director d.text
                end

                credits.css('o[t="s"] j')&.collect.each do |w|
                  writer w.text
                end

                credits.css('o[t="m"] j')&.collect.each do |m|
                  music m.text
                end

                credits.css('o[t="k"] j')&.collect.each do |c|
                  camera c.text
                end

                credits.css('o[t="p"] j')&.collect.each do |p|
                  producer p.text
                end

                credits.css('o[t="h"] j')&.collect.each do |a|
                  actor a.text, "role": a['role'].to_s.gsub(%r{\s?\/\s\.\.\.}, '')
                end
              end unless credits.css('o[t="r"] j').nil?
            end
          end
        rescue
          # puts "error"
        end
        date += 1.day.to_f
      end
    end
  end
end

# File.open(options.path, "w").write builder.to_xml
f = File.open(options.path, 'w')
f.write(builder.to_xml.gsub(/_/, '-').gsub(%r{.*<credits\/>\n|\srole=""}, ''))
f.close

# Compress for Enigma2
XZ.compress_file("#{options.path}", "#{options.path}.xz")

