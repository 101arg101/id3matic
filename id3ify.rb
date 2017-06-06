#!/usr/bin/env ruby
=begin
  how to use id3matic:
  $ id3matic <artist> <album> []
  
  id3tag 
  Usage: id3tag [OPTIONS]... [FILES]...
     -h         --help            Print help and exit
     -V         --version         Print version and exit
     -1         --v1tag           Render only the id3v1 tag (default=off)
     -2         --v2tag           Render only the id3v2 tag (default=off)
     -aSTRING   --artist=STRING   Set the artist information
     -ASTRING   --album=STRING    Set the album title information
     -sSTRING   --song=STRING     Set the title information
     -cSTRING   --comment=STRING  Set the comment information
     -CSTRING   --desc=STRING     Set the comment description
     -ySTRING   --year=STRING     Set the year
     -tSTRING   --track=STRING    Set the track number
     -TSTRING   --total=STRING    Set the total number of tracks
     -gSHORT    --genre=SHORT     Set the genre
     -w         --warning         Turn on warnings (for debugging) (default=off)
     -n         --notice          Turn on notices (for debugging) (default=off)
  
=end

require 'optparse'
require 'google/api_client'
require 'yaml'
require 'json'
require 'discogs-wrapper'
require 'io/console'
require 'timeout'

# CONFIG_DIR = '~/.config/id3matic/id3matic'
# $config = YAML.load_file(File.expand_path('id3matic.conf.yml', File.dirname(CONFIG_DIR)))
# CACHED_API_FILE = File.expand_path('id3matic.json', File.dirname(CONFIG_DIR))

$config = YAML.load_file(File.expand_path('id3matic.conf.yml', File.dirname(__FILE__)))
CACHED_API_FILE = File.expand_path('id3matic.json', File.dirname(__FILE__))
$client = Google::APIClient.new($config)
$config['downloads_dir'] ||= Dir.pwd
$config['downloads_dir'] << '/' unless $config['downloads_dir'][-1] == '/' or $config['downloads_dir'][-1] == '\\'
$discogs = Discogs::Wrapper.new($config['application_name'], user_token: $config['discogs_access_token'])
$client.authorization = nil

$custom_search = {}
if File.exists? CACHED_API_FILE
  File.open(CACHED_API_FILE) do |file|
    $custom_search = Marshal.load(file)
  end
else
  $custom_search = $client.discovered_api('customsearch')
  File.open(CACHED_API_FILE, 'w') do |file|
    Marshal.dump($custom_search, file)
  end
end

# Makes options from arguments
$tags = [:artist, :album, :song, :comment, :desc, :year, :track, :total, :genre]
Options = Struct.new(:link, :yt_title, :file, *$tags)

class Parser
  def self.parse(options)
    # defaults
    args = Options.new

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: ruby id3matic.rb [options] <yt-link>"
      opts.on("-aSTRING", "--artist=STRING", "Set the artist information") do |n|
        args.artist = n
      end
      opts.on("-ASTRING", "--album=STRING", "Set the album title information") do |n|
        args.album = n
      end
      opts.on("-sSTRING", "--song=STRING", "Set the title information") do |n|
        args.song = n
      end
      opts.on("-cSTRING", "--comment=STRING", "Set the comment information") do |n|
        args.comment = n
      end
      opts.on("-CSTRING", "--desc=STRING", "Set the comment description") do |n|
        args.desc = n
      end
      opts.on("-ySTRING", "--year=STRING", "Set the year") do |n|
        args.year = n
      end
      opts.on("-tSTRING", "--track=STRING", "Set the track number") do |n|
        args.track = n
      end
      opts.on("-TSTRING", "--total=STRING", "Set the total number of tracks") do |n|
        args.total = n
      end
      opts.on("-gSHORT", "--genre=SHORT", "Set the genre") do |n|
        args.genre = n
      end
      opts.on("-h", "--help", "Prints this help") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(options)
    return args
  end
end

class ResultSet
  attr_accessor :i
  
  def initialize (template, data = [])
    @data = data.to_a
    
    @template = method(template)
    @i = 0
  end
  
  def choosing
    if @data.size < 1
      raise "No results available for #{self}"
    end
    
    write_template
    
    input = readkey
    
    # aliases for keys
    input.sub! "\e[A", 'u'
    input.sub! "\e[B", 'd'
    input.sub! "\e[C", 'n'
    input.sub! "\e[D", 'b'
    input.sub! "\r", 'y'
    
    unless input == 'y'
      if self.public_methods.include? input.to_sym
        method(input).call
      else
        h
      end
      
      choosing
    end
  end
  
  def get_result (ind = @i)
    @data[ind]
  end
  
  def h
    puts 'h for this help'
    puts 'y to select'
    puts 'n to go to next result'
    puts 'b to go to previous result'
    puts 'q to quit program'
  end
  
  def n
    @i += 1
    if @i >= @data.length
      puts 'Looping to beginning of results.'
      @i = 0
    end
    @data[@i]
  end
  
  def b
    @i -= 1
    if @i < 0
      puts 'Looping to end of results.'
      @i = @data.length - 1
    end
    
    @data[@i]
  end
  
  def q
    exit
  end
  
  private
  
  def write_template
    puts "(#{@i}): #{@template.call(get_result)}"
  end
end

def readkey
  c = ''
  result = ''
  $stdin.raw do |stdin|
    c = stdin.getc
    result << c
    if c == "\e"
      begin
        while (c = Timeout::timeout(0.0001) { stdin.getc })
          result << c
        end
      rescue Timeout::Error
        # no action required
      end
    end
  end
  result
end

def draw_frame (message, title = __FILE__)
  width  = `tput cols`.to_i
  height = `tput lines`.to_i
  
  (height - 3).times do |item|
    print "\r" + ("\e[A\e[K"*3) if item > 0
  end
  ((width / 2.0).floor - (title.length / 2.0).ceil).times do |col|
    print "="
  end
  
  print title
  
  ((width / 2.0).ceil - (title.length / 2.0).floor).times do |col|
    print "="
  end
  
  puts message
  
  (height - message.lines.count - 3).times do
    puts ''
  end
  
  width.times do |col|
    print "="
  end
end

# data templates
# data templates display info about a selection when used by a ResultSet.
def discogs_masters_template (data)
  curr_item = data
  "#{data.title} #{data.trackstr}"
end

# ask discogs about the song
def query_discogs_master (query)
  response = $discogs.search(query, :per_page => 15, :type => :master)
  response.results.each do |result|
    master = $discogs.get_master(result.id)
    result.master = master
    result.trackstr = ''
    master.tracklist.each do |track|
      result.trackstr += "\n  #{track.position} • #{track.title} (#{track.duration})"
    end
  end
  response
end

def get_discogs_info (query)
  response = query_discogs_master query
  results = ResultSet.new :discogs_masters_template, response.results
  puts 'Does this album look good to you?'
  results.h
  results.choosing
  results.get_result
end

# ask wikipedia about the song (get id3 tags from wikipedia)
def get_wiki_info (query)
  response = query_wiki query
  
  response['items'].select! do |item|
    item['pagemap']['videoobject'] and
    item['pagemap']['videoobject'].size == 1 and
    (item['pagemap']['videoobject'][0]['genre'] == 'Music' or item['pagemap']['videoobject'][0]['genre'] == 'Entertainment')
  end
  
  results = ResultSet.new :wiki_json_template, response['items']
  
  puts 'Does this file look good to you?'
  
  results.h
  results.choosing
  
  results.get_result['pagemap']['videoobject'][0]
end

# write ID3 Tags for each option

# ----------------------------------------------------------------------------

def init (*args)
  song = Parser.parse args
  arg_sentence = args.join(' ') # input from user turned into a single string
  
  puts "Querying discogs for \"#{arg_sentence}\""
  
  top_discogs_result = get_discogs_info arg_sentence
  song.album = top_discogs_result.master.title
  song.artist = top_discogs_result.master.artists.map(&:name).join(', ')
  song.total = top_discogs_result.master.tracklist.length
  song.year = top_discogs_result.year
  
  puts song
end
# ask wikipedia about the song (get id3 tags from wikipaedofile)
# write ID3 Tags for each option

# system "clear" or system "cls"
#song = init ARGV
#puts song.inspect

init ARGV