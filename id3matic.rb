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

# CONFIG_DIR = '~/.config/id3matic/id3matic'

$config = YAML.load_file(File.expand_path('config/id3mconf.yml', File.dirname(__FILE__)))
CACHED_API_FILE = File.expand_path('tmp/id3matic.json', File.dirname(__FILE__))
# $config = YAML.load_file(File.expand_path('id3mconf.yml', File.dirname(CONFIG_DIR)))
# CACHED_API_FILE = File.expand_path('id3matic.json', File.dirname(CONFIG_DIR))
$client = Google::APIClient.new($config)
$config['downloads_dir'] ||= Dir.pwd
$config['downloads_dir'] << '/' unless $config['downloads_dir'][-1] == '/' or $config['downloads_dir'][-1] == '\\'
$discogs = Discogs::Wrapper.new($config['application_name'], app_key: $config['discogs_key'], app_secret: $config['discogs_secret'])
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
Options = Struct.new(:link, :yt_title, :file, :quiet, *$tags)

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
      opts.on("-q", "--quiet", "Grabs the first song. No questions asked") do
        args.quiet = true
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
    
    input = $stdin.gets.chomp
    
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
  
  private
  
  def write_template
    puts "(#{@i}): #{@template.call(get_result)}"
  end
end

# data templates
def yt_json_template (data)
  curr_item = data['pagemap']['videoobject'][0]
  "#{curr_item['name']} (duration: #{curr_item['duration'][2..-1].gsub(/[A-Z]/,':')}) #{curr_item['description']}"
end

def wiki_json_template (data)
  curr_item = data['pagemap']['videoobject'][0]
  "#{curr_item['name']} (duration: #{curr_item['duration'][2..-1].gsub(/[A-Z]/,':')}) #{curr_item['description']}"
end

# query yt to find the best video
def query_yt (query)
  result = $client.execute(
    :api_method => $custom_search.cse.list,
    :parameters => {
      'q' => query,
      'cx' => $config['yt_cse']
    }
  )
  
  JSON.parse result.response.body
end

def get_yt_info (query, opts)
  yt_response = query_yt query
  puts yt_response.inspect
  yt_response['items'].select! do |item|
    item['pagemap']['videoobject'] and # if yt page has a video
    item['pagemap']['videoobject'].size == 1 and # if yt page isn't a playlist
    (item['pagemap']['videoobject'][0]['genre'] == 'Music' or item['pagemap']['videoobject'][0]['genre'] == 'Entertainment')
  end
  
  yt_results = ResultSet.new :yt_json_template, yt_response['items']
  
  unless opts.quiet then
    puts 'Does this file look good to you?'
    
    yt_results.h
    yt_results.choosing
  end
  
  return yt_results.get_result['pagemap']['videoobject'][0]
end

# ask wikipedia about the song (get id3 tags from wikipaedofile)
def query_wiki (query)
  result = $client.execute(
    :api_method => $custom_search.cse.list,
    :parameters => {
      'q' => query,
      'cx' => $config['wiki_cse']
    }
  )
  
  JSON.parse result.response.body
end

def get_wiki_info (query)
  response = query_wiki query
  
  puts JSON.generate(response)
  
=begin
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
=end
end

# write ID3 Tags for each option

# ----------------------------------------------------------------------------

def init (*args)
  song = Parser.parse ARGV
  arg_sentence = args.join(' ') # input from user turned into a single string
  
  # where do I get the song/vid data? locally, with a specific link, or do I search for it?
  if File.exist?(File.expand_path(arg_sentence))
    song.file = arg_sentence
    song.yt_title = song.file[0...song.file.rindex('-')]
  elsif arg_sentence.start_with? 'http'
    song.yt_title = `youtube-dl --get-title #{ arg_sentence }`
    song.link = arg_sentence
  elsif song.quiet
    top_result = get_yt_info(arg_sentence, song)
    song.yt_title = top_result['name']
    song.link = top_result['url']
  else # query for video on yt
    puts "Querying yt for \"#{ arg_sentence }\""
    top_result = get_yt_info(arg_sentence, song)
    song.yt_title = top_result['name']
    song.link = top_result['url']
  end
  
  # download the yt video
  unless song.file
    begin
      puts "Downloading #{ song.yt_title } from #{ song.link }. Please wait..." unless song.quiet
      `youtube-dl -x --prefer-ffmpeg --audio-format "mp3" -o "#{ $config['downloads_dir'] }%(title)s-%(id)s.%(ext)s" #{ song.link }`
      puts "Done downloading #{ song.link }" unless song.quiet
    rescue
      raise 'Cannot determine the URL of the video'
    end
  end
  
  # query wiki for song data
  # http://en.wikipedia.org/w/api.php?format=json&action=query&titles=No_Quarter_(song)&prop=revisions&rvprop=content
  tmp_title = song.yt_title.gsub(/\[([^\]]+)\]/, '').gsub(/\{([^}]+)\}/, '')
  # top_query = get_wiki_info tmp_title
  
  song
end
# ask wikipedia about the song (get id3 tags from wikipaedofile)
# write ID3 Tags for each option

$stdout.sync = true
song = init ARGV
